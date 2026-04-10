'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const common = require('oci-common');
const objectstorage = require('oci-objectstorage');

const { loadRoutingDefinitionFromObject, processEnvelope } = require('./lib/json_router');
const { createDestinationDispatcher } = require('./lib/destination_dispatcher');
const { createOciObjectStorageAdapter } = require('./lib/oci_object_storage_adapter');

function isObject(value) {
    return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function joinPrefix(prefix, name) {
    const p = typeof prefix === 'string' ? prefix : '';
    const trimmed = p === '' ? '' : p.replace(/^\/+/, '').replace(/\/?$/, '/');
    return `${trimmed}${name}`;
}

function parseFnInput(input) {
    if (input === undefined || input === null) {
        throw new Error('Empty function input');
    }
    if (Buffer.isBuffer(input)) {
        const s = input.toString('utf8').trim();
        if (s === '') throw new Error('Empty function input');
        try {
            return JSON.parse(s);
        } catch (err) {
            throw new Error(`Invalid JSON body: ${err.message}`);
        }
    }
    if (typeof input === 'string') {
        const s = input.trim();
        if (s === '') throw new Error('Empty function input');
        try {
            return JSON.parse(s);
        } catch (err) {
            throw new Error(`Invalid JSON body: ${err.message}`);
        }
    }
    if (typeof input === 'object') {
        return input;
    }
    throw new Error('Function input must be JSON object, string, or Buffer');
}

function envelopeFromPayload(parsed) {
    if (parsed && isObject(parsed) && Object.prototype.hasOwnProperty.call(parsed, 'body')) {
        const b = parsed.body;
        if (isObject(b) || Array.isArray(b)) {
            return {
                endpoint: parsed.endpoint,
                headers: isObject(parsed.headers) ? parsed.headers : {},
                body: b,
                source_meta: parsed.source_meta,
            };
        }
    }
    if (isObject(parsed) || Array.isArray(parsed)) {
        return { endpoint: 'fn', headers: {}, body: parsed };
    }
    throw new Error('Payload must be a JSON object or array (or envelope with .body)');
}

let cachedOs = null;

async function getDefaultObjectStorageClient() {
    if (cachedOs) return cachedOs;
    const provider = common.ResourcePrincipalAuthenticationDetailsProvider.builder();
    const client = new objectstorage.ObjectStorageClient({ authenticationDetailsProvider: provider });
    const namespaceName = (await client.getNamespace({})).value;
    cachedOs = { client, namespaceName };
    return cachedOs;
}

function loadRoutingDefinitionForRun() {
    const routingPath = path.join(__dirname, 'routing.json');
    const raw = fs.readFileSync(routingPath, 'utf8');
    const obj = JSON.parse(raw);
    const bucket = process.env.OCI_INGEST_BUCKET;
    if (typeof bucket !== 'string' || bucket.trim() === '') {
        throw new Error('OCI_INGEST_BUCKET must be set (function configuration)');
    }
    const adapterKey = 'oci_object_storage:raw_ingest';
    if (!isObject(obj.adapters) || !isObject(obj.adapters[adapterKey])) {
        throw new Error(`routing.json must define adapters["${adapterKey}"]`);
    }
    obj.adapters[adapterKey].bucket = bucket.trim();
    return loadRoutingDefinitionFromObject(obj, { baseDir: __dirname });
}

/**
 * @param {unknown} fnInput - Fn / FDK input (object, string, or Buffer)
 * @param {object} [options]
 * @param {function} [options.getObjectStorage] async () => ({ client, namespaceName })
 * @param {function} [options.putObject] async ({ bucket, objectName, content, contentType }) => void
 */
async function runRouter(fnInput, options = {}) {
    const parsed = parseFnInput(fnInput);
    const envelope = envelopeFromPayload(parsed);
    const definition = loadRoutingDefinitionForRun();

    let putObjectImpl = options.putObject;
    if (!putObjectImpl) {
        putObjectImpl = async ({ bucket, objectName, content, contentType }) => {
            const os = options.getObjectStorage ? await options.getObjectStorage() : await getDefaultObjectStorageClient();
            await os.client.putObject({
                namespaceName: os.namespaceName,
                bucketName: bucket,
                objectName,
                putObjectBody: typeof content === 'string' ? Buffer.from(content, 'utf8') : content,
                contentType: contentType || 'application/json',
            });
        };
    }

    const bucketAdapter = createOciObjectStorageAdapter({
        destinationMap: definition.adapters,
        emit: async ({ output, envelope: env, target }) => {
            const meta = env && env.source_meta;
            const fromMeta = meta && typeof meta.file_name === 'string' && meta.file_name.trim() !== '' ? meta.file_name.trim() : null;
            const fileName =
                fromMeta ||
                `fn-${Date.now()}-${crypto.randomBytes(4).toString('hex')}.json`;
            const objectName = joinPrefix(target.prefix, fileName);
            await putObjectImpl({
                bucket: target.bucket,
                objectName,
                content: JSON.stringify(output),
                contentType: 'application/json',
            });
        },
    });

    const dispatcher = createDestinationDispatcher({
        adapters: [bucketAdapter],
        deadLetterDestination: definition.dead_letter,
    });

    const handlers = {
        onRoute: dispatcher.onRoute,
    };
    if (definition.dead_letter) {
        handlers.onDeadLetter = dispatcher.onDeadLetter;
    }

    return processEnvelope(envelope, definition, handlers);
}

module.exports = {
    runRouter,
    parseFnInput,
    envelopeFromPayload,
    loadRoutingDefinitionForRun,
};
