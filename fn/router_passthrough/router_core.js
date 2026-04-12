'use strict';

const crypto = require('crypto');
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

function headerValueToString(value) {
    if (value == null) {
        return null;
    }
    if (Array.isArray(value)) {
        return value.length > 0 ? String(value[0]) : null;
    }
    return String(value);
}

/**
 * Copy inbound HTTP headers from the Fn FDK (API Gateway → Fn uses Fn-Http-H-* on Context;
 * ctx.httpGateway exposes the original client headers) into envelope.headers when missing.
 * Does not overwrite non-empty header values already on the envelope.
 */
function mergeHttpGatewayHeadersIntoEnvelope(envelope, fdkContext) {
    if (!isObject(envelope)) {
        return;
    }
    if (!fdkContext || typeof fdkContext.httpGateway !== 'object' || fdkContext.httpGateway === null) {
        return;
    }
    let gw;
    try {
        gw = fdkContext.httpGateway;
    } catch (_) {
        return;
    }
    const gh = gw && gw.headers;
    if (!isObject(gh)) {
        return;
    }

    const h = isObject(envelope.headers) ? { ...envelope.headers } : {};
    const hasNonEmpty = new Map();
    for (const [k, v] of Object.entries(h)) {
        if (v !== undefined && v !== null && String(v).trim() !== '') {
            hasNonEmpty.set(String(k).toLowerCase(), true);
        }
    }

    for (const [k, vRaw] of Object.entries(gh)) {
        const lk = String(k).toLowerCase();
        if (hasNonEmpty.has(lk)) {
            continue;
        }
        const val = headerValueToString(vRaw);
        if (val != null && val.trim() !== '') {
            h[lk] = val;
            hasNonEmpty.set(lk, true);
        }
    }
    envelope.headers = h;
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

async function readGetObjectBodyToString(getObjectResponse) {
    const stream = getObjectResponse && getObjectResponse.value;
    if (!stream) {
        throw new Error('Object Storage getObject returned no body stream');
    }
    const chunks = [];
    // Node OCI SDK returns a Readable stream
    // eslint-disable-next-line no-restricted-syntax
    for await (const chunk of stream) {
        chunks.push(chunk);
    }
    return Buffer.concat(chunks).toString('utf8');
}

const RAW_INGEST_ADAPTER_KEY = 'oci_object_storage:raw_ingest';

/**
 * Inject runtime ingest bucket into the parsed routing object (same bucket the Fn writes to).
 */
function applyIngestBucketToRoutingObject(obj) {
    const bucket = process.env.OCI_INGEST_BUCKET;
    if (typeof bucket !== 'string' || bucket.trim() === '') {
        throw new Error('OCI_INGEST_BUCKET must be set (function configuration)');
    }
    if (!isObject(obj.adapters) || !isObject(obj.adapters[RAW_INGEST_ADAPTER_KEY])) {
        throw new Error(`routing definition must define adapters["${RAW_INGEST_ADAPTER_KEY}"]`);
    }
    const b = bucket.trim();
    for (const [key, val] of Object.entries(obj.adapters)) {
        if (String(key).startsWith('oci_object_storage:') && isObject(val)) {
            val.bucket = b;
        }
    }
    return loadRoutingDefinitionFromObject(obj, { baseDir: __dirname });
}

/**
 * Load routing definition: Object Storage (production) or in-memory (tests via options.routingDefinition).
 *
 * Env (production):
 * - SLI_ROUTING_BUCKET — bucket containing routing JSON (defaults to OCI_INGEST_BUCKET)
 * - SLI_ROUTING_OBJECT — object name (default config/routing.json)
 */
async function loadRoutingDefinitionForRun(options = {}) {
    if (options.routingDefinition !== undefined && options.routingDefinition !== null) {
        const cloned = JSON.parse(JSON.stringify(options.routingDefinition));
        return applyIngestBucketToRoutingObject(cloned);
    }

    const routingBucket = (process.env.SLI_ROUTING_BUCKET || process.env.OCI_INGEST_BUCKET || '').trim();
    const routingObject = (process.env.SLI_ROUTING_OBJECT || 'config/routing.json').trim();
    if (routingBucket === '') {
        throw new Error(
            'SLI_ROUTING_BUCKET or OCI_INGEST_BUCKET must be set, or pass options.routingDefinition (tests)',
        );
    }

    const os = options.getObjectStorage ? await options.getObjectStorage() : await getDefaultObjectStorageClient();
    let raw;
    try {
        const getResp = await os.client.getObject({
            namespaceName: os.namespaceName,
            bucketName: routingBucket,
            objectName: routingObject,
        });
        raw = await readGetObjectBodyToString(getResp);
    } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        throw new Error(
            `Failed to load routing definition from Object Storage ` +
                `(bucket=${routingBucket}, object=${routingObject}): ${msg}`,
        );
    }

    let obj;
    try {
        obj = JSON.parse(raw);
    } catch (e) {
        const msg = e instanceof Error ? e.message : String(e);
        throw new Error(`Routing object ${routingObject} is not valid JSON: ${msg}`);
    }

    return applyIngestBucketToRoutingObject(obj);
}

/**
 * Resolve JSONata mapping text when it is not bundled in the image (Object Storage).
 * Basename `passthrough.jsonata` is loaded from SLI_PASSTHROUGH_OBJECT (default config/passthrough.jsonata).
 */
function buildLoadMappingFromRef(options) {
    if (typeof options.loadMappingFromRef === 'function') {
        return options.loadMappingFromRef;
    }
    return async ({ mappingRef }) => {
        const base = path.basename(String(mappingRef));
        if (base !== 'passthrough.jsonata') {
            return null;
        }
        const mappingBucket = (
            process.env.SLI_MAPPING_BUCKET ||
            process.env.SLI_ROUTING_BUCKET ||
            process.env.OCI_INGEST_BUCKET ||
            ''
        ).trim();
        const mappingObject = (process.env.SLI_PASSTHROUGH_OBJECT || 'config/passthrough.jsonata').trim();
        if (mappingBucket === '') {
            throw new Error(
                'Set SLI_MAPPING_BUCKET, SLI_ROUTING_BUCKET, or OCI_INGEST_BUCKET to load passthrough.jsonata from Object Storage, ' +
                    'or pass options.loadMappingFromRef (local tests)',
            );
        }
        const os = options.getObjectStorage ? await options.getObjectStorage() : await getDefaultObjectStorageClient();
        let raw;
        try {
            const getResp = await os.client.getObject({
                namespaceName: os.namespaceName,
                bucketName: mappingBucket,
                objectName: mappingObject,
            });
            raw = await readGetObjectBodyToString(getResp);
        } catch (err) {
            const msg = err instanceof Error ? err.message : String(err);
            throw new Error(
                `Failed to load mapping from Object Storage (bucket=${mappingBucket}, object=${mappingObject}): ${msg}`,
            );
        }
        return raw.trim();
    };
}

/**
 * @param {unknown} fnInput - Fn / FDK input (object, string, or Buffer)
 * @param {object} [options]
 * @param {function} [options.getObjectStorage] async () => ({ client, namespaceName })
 * @param {function} [options.putObject] async ({ bucket, objectName, content, contentType }) => void
 * @param {function} [options.loadMappingFromRef] async ({ mappingRef, route, definition }) => string|null — override OS mapping load (tests)
 * @param {object} [options.fdkContext] Fn FDK invocation context (second arg to handler) — merges ctx.httpGateway headers for raw POST bodies
 */
async function runRouter(fnInput, options = {}) {
    const parsed = parseFnInput(fnInput);
    const envelope = envelopeFromPayload(parsed);
    mergeHttpGatewayHeadersIntoEnvelope(envelope, options.fdkContext);
    const definition = await loadRoutingDefinitionForRun(options);

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
        loadMappingFromRef: buildLoadMappingFromRef(options),
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
    mergeHttpGatewayHeadersIntoEnvelope,
    loadRoutingDefinitionForRun,
    buildLoadMappingFromRef,
};
