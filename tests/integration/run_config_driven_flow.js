#!/usr/bin/env node
'use strict';

// Generic integration runner: fully driven by routing.json
// - definition.source decides how envelopes are read (file_system or oci_object_storage)
// - definition.mapping (optional) decides how mappings are loaded (local fallback or oci_object_storage)
// - routes decide destinations; delivery uses file_adapter and oci_object_storage_adapter via dispatcher

const path = require('path');

const common = require('oci-common');
const objectstorage = require('oci-objectstorage');

const { loadRoutingDefinition, processEnvelopes } = require('../../tools/json_router');
const { createDestinationDispatcher } = require('../../tools/adapters/destination_dispatcher');
const { createFileAdapter } = require('../../tools/adapters/file_adapter');
const { createOciObjectStorageAdapter } = require('../../tools/adapters/oci_object_storage_adapter');
const { createMappingLoader } = require('../../tools/adapters/mapping_loader');
const { createOciObjectStorageMappingSource } = require('../../tools/adapters/oci_object_storage_mapping_source');
const { createSourceAdapterFromDefinition } = require('../../tools/adapters/source_loader');

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

async function main() {
  const routingPath = process.env.ROUTING_JSON;
  if (!routingPath) throw new Error('ROUTING_JSON env var is required');

  const outDir = process.env.OUT_DIR || path.join(process.cwd(), 'out');
  const profile = process.env.OCI_CLI_PROFILE || 'DEFAULT';

  const provider = new common.ConfigFileAuthenticationDetailsProvider(undefined, profile);
  const client = new objectstorage.ObjectStorageClient({ authenticationDetailsProvider: provider });
  const namespaceName = (await client.getNamespace({})).value;

  const definition = loadRoutingDefinition(routingPath);
  if (!isObject(definition.adapters)) throw new Error('routing.json must define adapters for integration flows');

  // mapping loader (optional)
  let loadMapping = undefined;
  if (definition.mapping) {
    const mappingSource = createOciObjectStorageMappingSource({
      getObject: async ({ bucket, objectName }) => {
        const resp = await withRetry(() => client.getObject({ namespaceName, bucketName: bucket, objectName }));
        return await readObjectToString(resp.value);
      }
    });
    loadMapping = createMappingLoader({
      destinationMap: definition.adapters,
      mappingSources: [mappingSource]
    });
  }

  // source adapter is always configured via definition.source
  const source = createSourceAdapterFromDefinition(definition, {
    listObjects: async ({ bucket, prefix }) => {
      const resp = await withRetry(() => client.listObjects({ namespaceName, bucketName: bucket, prefix }));
      return resp.listObjects && resp.listObjects.objects ? resp.listObjects.objects : [];
    },
    getObject: async ({ bucket, objectName }) => {
      const resp = await withRetry(() => client.getObject({ namespaceName, bucketName: bucket, objectName }));
      return await readObjectToString(resp.value);
    }
  });

  // destination adapters (file + bucket)
  const fileAdapter = createFileAdapter({
    rootDir: outDir,
    supportedTypes: ['file_system'],
    preserveSourceFileName: true,
    destinationMap: definition.adapters,
  });

  const bucketAdapter = createOciObjectStorageAdapter({
    destinationMap: definition.adapters,
    emit: async ({ output, envelope, target }) => {
      const fileName = envelope && envelope.source_meta ? envelope.source_meta.file_name : 'item.json';
      const objectName = joinPrefix(target.prefix, fileName);
      await withRetry(() =>
        client.putObject({
          namespaceName,
          bucketName: target.bucket,
          objectName,
          putObjectBody: JSON.stringify(output),
          contentType: 'application/json'
        })
      );
    }
  });

  const dispatcher = createDestinationDispatcher({
    adapters: [bucketAdapter, fileAdapter],
    deadLetterDestination: definition.dead_letter
  });

  await processEnvelopes(source.readEnvelopes(), definition, {
    loadMapping,
    onRoute: dispatcher.onRoute,
    onDeadLetter: dispatcher.onDeadLetter
  });

  process.stdout.write(JSON.stringify({ ok: true }) + '\n');
}

main().catch((err) => {
  process.stderr.write(String(err && err.message ? err.message : err) + '\n');
  process.exit(1);
});

