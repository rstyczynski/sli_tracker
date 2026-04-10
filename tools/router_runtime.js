'use strict';
// tools/router_runtime.js
// Execute a routing definition end-to-end (source -> route+transform -> destinations).

const path = require('path');
const common = require('oci-common');
const objectstorage = require('oci-objectstorage');

const jsonRouter = require('./json_router');
const loadRoutingDefinition = jsonRouter.loadRoutingDefinition;
const processEnvelopes = jsonRouter.processEnvelopes;

const { createDestinationDispatcher } = require('./adapters/destination_dispatcher');
const { createFileAdapter } = require('./adapters/file_adapter');
const { createOciObjectStorageAdapter } = require('./adapters/oci_object_storage_adapter');
const { createMappingLoader } = require('./adapters/mapping_loader');
const { createOciObjectStorageMappingSource } = require('./adapters/oci_object_storage_mapping_source');
const { createSourceAdapterFromDefinition } = require('./adapters/source_loader');

function isObject(v) {
    return typeof v === 'object' && v !== null && !Array.isArray(v);
}

async function readObjectToString(respValue) {
    const v = respValue;
    if (v && typeof v.on === 'function') {
        const chunks = [];
        await new Promise((resolve, reject) => {
            v.on('data', (c) => chunks.push(Buffer.isBuffer(c) ? c : Buffer.from(c)));
            v.on('end', resolve);
            v.on('error', reject);
        });
        return Buffer.concat(chunks).toString('utf8');
    }
    if (v && typeof v.getReader === 'function') {
        const reader = v.getReader();
        const chunks = [];
        // eslint-disable-next-line no-constant-condition
        while (true) {
            const { done, value } = await reader.read();
            if (done) break;
            chunks.push(Buffer.from(value));
        }
        return Buffer.concat(chunks).toString('utf8');
    }
    if (Buffer.isBuffer(v)) return v.toString('utf8');
    if (typeof v === 'string') return v;
    return String(v);
}

function joinPrefix(prefix, name) {
    const p = typeof prefix === 'string' ? prefix : '';
    const trimmed = p === '' ? '' : p.replace(/^\/+/, '').replace(/\/?$/, '/');
    return `${trimmed}${name}`;
}

async function withRetry(fn, options = {}) {
    const attempts = Number.isFinite(options.attempts) ? options.attempts : 8;
    const baseDelayMs = Number.isFinite(options.baseDelayMs) ? options.baseDelayMs : 400;
    let lastErr;
    for (let i = 0; i < attempts; i += 1) {
        try {
            return await fn(i + 1);
        } catch (err) {
            lastErr = err;
            const delay = baseDelayMs * Math.pow(1.6, i);
            await new Promise((r) => setTimeout(r, delay));
        }
    }
    throw lastErr;
}

async function createOciObjectStorageClient(profile) {
    const provider = new common.ConfigFileAuthenticationDetailsProvider(undefined, profile);
    const client = new objectstorage.ObjectStorageClient({ authenticationDetailsProvider: provider });
    const namespaceName = (await withRetry(() => client.getNamespace({}))).value;
    return { client, namespaceName };
}

async function createRuntimeFromRoutingDefinition(definition, options = {}) {
    if (!isObject(definition)) {
        throw new Error('Runtime requires a routing definition object');
    }
    if (!isObject(definition.adapters)) {
        throw new Error('Runtime requires routing.json adapters');
    }

    const profile = options.ociProfile || process.env.OCI_CLI_PROFILE || 'DEFAULT';
    const oci = await createOciObjectStorageClient(profile);
    const client = oci.client;
    const namespaceName = oci.namespaceName;

    const getObject = async ({ bucket, objectName }) => {
        const resp = await withRetry(() => client.getObject({ namespaceName, bucketName: bucket, objectName }));
        return await readObjectToString(resp.value);
    };
    const listObjects = async ({ bucket, prefix }) => {
        const resp = await withRetry(() => client.listObjects({ namespaceName, bucketName: bucket, prefix }));
        return resp.listObjects && resp.listObjects.objects ? resp.listObjects.objects : [];
    };
    const putObject = async ({ bucket, objectName, content, contentType }) => {
        await withRetry(() =>
            client.putObject({
                namespaceName,
                bucketName: bucket,
                objectName,
                putObjectBody: content,
                contentType: contentType || 'application/json',
            })
        );
    };

    // mapping loader (optional)
    let loadMapping = undefined;
    if (definition.mapping) {
        const sources = [];
        if (definition.mapping.type === 'oci_object_storage') {
            sources.push(createOciObjectStorageMappingSource({ getObject }));
        }
        if (sources.length === 0) {
            throw new Error(`No mapping source configured for mapping type "${definition.mapping.type}"`);
        }
        loadMapping = createMappingLoader({
            destinationMap: definition.adapters,
            mappingSources: sources,
        });
    }

    const source = createSourceAdapterFromDefinition(definition, { listObjects, getObject });

    // Destination adapters
    const baseDir = definition.baseDir || process.cwd();
    const fileAdapter = createFileAdapter({
        rootDir: options.fileRootDir || baseDir,
        supportedTypes: ['file_system'],
        preserveSourceFileName: true,
        destinationMap: definition.adapters,
    });

    const bucketAdapter = createOciObjectStorageAdapter({
        destinationMap: definition.adapters,
        emit: async ({ output, envelope, target }) => {
            const fileName = envelope && envelope.source_meta ? envelope.source_meta.file_name : 'item.json';
            const objectName = joinPrefix(target.prefix, fileName);
            await putObject({
                bucket: target.bucket,
                objectName,
                content: JSON.stringify(output),
                contentType: 'application/json',
            });
        },
    });

    const dispatcher = createDestinationDispatcher({
        adapters: [bucketAdapter, fileAdapter],
        deadLetterDestination: definition.dead_letter,
    });

    return {
        definition,
        source,
        handlers: {
            loadMapping,
            onRoute: dispatcher.onRoute,
            onDeadLetter: dispatcher.onDeadLetter,
        },
    };
}

async function runFromRoutingFile(routingPath, options = {}) {
    const definition = loadRoutingDefinition(routingPath);
    const runtime = await createRuntimeFromRoutingDefinition(definition, options);
    return await processEnvelopes(runtime.source.readEnvelopes(), runtime.definition, runtime.handlers);
}

module.exports = {
    createRuntimeFromRoutingDefinition,
    runFromRoutingFile,
};

