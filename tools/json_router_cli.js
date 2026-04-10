#!/usr/bin/env node
'use strict';
// tools/json_router_cli.js
// CLI wrapper: apply a routing definition to one envelope or a batch source directory.
// Sprint 19 / SLI-27, SLI-28, SLI-29
//
// Usage:
//   node tools/json_router_cli.js --routing <file> [--input <file>] [--pretty]
//   cat envelope.json | node tools/json_router_cli.js --routing <file>
//   node tools/json_router_cli.js --routing <file> --source-dir <dir> --output-dir <dir> [--pretty]

const fs = require('fs');
const path = require('path');

const jsonRouter = require('./json_router');
const loadRoutingDefinition = jsonRouter.loadRoutingDefinition;
const routeTransformAll = jsonRouter.routeTransformAll;
const processEnvelope = jsonRouter.processEnvelope;
const errorMessage = jsonRouter.errorMessage;

const routerRuntime = require('./router_runtime');
const runFromRoutingFile = routerRuntime.runFromRoutingFile;

const mappingLoader = require('./adapters/mapping_loader');
const createMappingLoader = mappingLoader.createMappingLoader;
const ociMappingSource = require('./adapters/oci_object_storage_mapping_source');
const createOciObjectStorageMappingSource = ociMappingSource.createOciObjectStorageMappingSource;

const common = require('oci-common');
const objectstorage = require('oci-objectstorage');

const fileSourceAdapter = require('./adapters/file_source_adapter');
const createFileSourceAdapter = fileSourceAdapter.createFileSourceAdapter;
const fileAdapter = require('./adapters/file_adapter');
const createFileAdapter = fileAdapter.createFileAdapter;

function destinationPath(destination) {
    if (typeof destination.name === 'string' && destination.name.trim() !== '') {
        return path.join(destination.type, destination.name);
    }
    return destination.type;
}

function usage(code) {
    process.stderr.write([
        'Usage: node json_router_cli.js --routing <file> [--input <file>] [--pretty]',
        '       cat envelope.json | node json_router_cli.js --routing <file>',
        '       node json_router_cli.js --routing <file> --source-dir <dir> --output-dir <dir> [--pretty]',
        '',
        'Options:',
        '  --routing     Path to routing.json (required)',
        '  --input       Path to one envelope JSON file (optional; reads stdin if omitted)',
        '  --source-dir  Path to a source directory for batch routing',
        '  --output-dir  Path to output directory for batch routing',
        '  --pretty      Pretty-print output (default: compact)',
        '  --help        Show this help',
    ].join('\n') + '\n');
    process.exit(code);
}

function parseArgs(argv) {
    const args = { routing: null, input: null, sourceDir: null, outputDir: null, pretty: false };
    const known = new Set(['--routing', '--input', '--source-dir', '--output-dir', '--pretty', '--help']);
    for (let i = 0; i < argv.length; i++) {
        const a = argv[i];
        if (!known.has(a)) {
            process.stderr.write(`Unknown option: ${a}\n`);
            usage(1);
        }
        if (a === '--help') usage(0);
        if (a === '--pretty') { args.pretty = true; continue; }
        const val = argv[++i];
        if (a === '--routing')    args.routing = val;
        if (a === '--input')      args.input = val;
        if (a === '--source-dir') args.sourceDir = val;
        if (a === '--output-dir') args.outputDir = val;
    }
    return args;
}

function readStdin() {
    return new Promise((resolve, reject) => {
        const chunks = [];
        process.stdin.on('data', (c) => chunks.push(c));
        process.stdin.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
        process.stdin.on('error', reject);
    });
}

function isObject(value) {
    return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function readNodeStreamToString(stream) {
    return new Promise((resolve, reject) => {
        const chunks = [];
        stream.on('data', (c) => chunks.push(Buffer.isBuffer(c) ? c : Buffer.from(c)));
        stream.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
        stream.on('error', reject);
    });
}

async function readWebStreamToString(readableStream) {
    const reader = readableStream.getReader();
    const chunks = [];
    // eslint-disable-next-line no-constant-condition
    while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        chunks.push(Buffer.from(value));
    }
    return Buffer.concat(chunks).toString('utf8');
}

async function buildOciObjectStorageGetObject(profile) {
    const provider = new common.ConfigFileAuthenticationDetailsProvider(undefined, profile);
    const client = new objectstorage.ObjectStorageClient({ authenticationDetailsProvider: provider });

    let regionId = null;
    if (typeof provider.getRegion === 'function' && provider.getRegion()) {
        const r = provider.getRegion();
        regionId = typeof r === 'string' ? r : (r.regionId || r.regionIdentifier || null);
    }
    if (regionId) {
        try {
            client.region = common.Region.fromRegionId(regionId);
        } catch (_) {
            client.region = regionId;
        }
        client.endpoint = `https://objectstorage.${regionId}.oraclecloud.com`;
    }

    const namespaceName = (await client.getNamespace({})).value;

    return async function getObject({ bucket, objectName }) {
        let resp = null;
        let lastErr = null;
        for (let attempt = 1; attempt <= 8; attempt++) {
            try {
                resp = await client.getObject({ namespaceName, bucketName: bucket, objectName });
                lastErr = null;
                break;
            } catch (e) {
                lastErr = e;
                await new Promise((r) => setTimeout(r, 3000));
            }
        }
        if (lastErr) throw lastErr;

        const v = resp.value;
        if (v && typeof v.on === 'function') return await readNodeStreamToString(v);
        if (v && typeof v.getReader === 'function') return await readWebStreamToString(v);
        if (Buffer.isBuffer(v)) return v.toString('utf8');
        if (typeof v === 'string') return v;
        return String(v);
    };
}

async function buildLoadMapping(definition) {
    if (!definition || !definition.mapping) return undefined;
    if (!isObject(definition.adapters)) {
        throw new Error('Routing definition uses mapping but does not define adapters');
    }
    const profile = process.env.OCI_CLI_PROFILE || 'DEFAULT';
    const sources = [];
    if (definition.mapping.type === 'oci_object_storage') {
        const getObject = await buildOciObjectStorageGetObject(profile);
        sources.push(createOciObjectStorageMappingSource({ getObject }));
    }
    if (sources.length === 0) {
        throw new Error(`No mapping source configured for mapping type "${definition.mapping.type}"`);
    }
    return createMappingLoader({
        destinationMap: definition.adapters,
        mappingSources: sources,
    });
}

async function main() {
    const args = parseArgs(process.argv.slice(2));

    if (!args.routing) {
        process.stderr.write('Error: --routing is required\n');
        usage(1);
    }

    const batchMode = Boolean(args.sourceDir || args.outputDir);
    if (batchMode) {
        if (!args.sourceDir || !args.outputDir) {
            process.stderr.write('Error: batch mode requires both --source-dir and --output-dir\n');
            process.exit(1);
        }
        let definition;
        try {
            definition = loadRoutingDefinition(args.routing);
        } catch (err) {
            process.stderr.write(`Error: ${errorMessage(err)}\n`);
            process.exit(1);
        }
        let loadMapping;
        try {
            loadMapping = await buildLoadMapping(definition);
        } catch (err) {
            process.stderr.write(`Error: ${errorMessage(err)}\n`);
            process.exit(1);
        }
        let result;
        try {
            const sourceAdapter = createFileSourceAdapter({ sourceDir: args.sourceDir });
            const deadLetterRelDir = definition.dead_letter ? destinationPath(definition.dead_letter) : 'dead_letter/errors';
            const targetAdapter = createFileAdapter({
                rootDir: args.outputDir,
                deadLetterDir: deadLetterRelDir,
                preserveSourceFileName: true,
                formatDeadLetter: ({ error, envelope, rawSource, fileName }) => {
                    const payload = {
                        file: fileName,
                        error,
                    };
                    if (rawSource !== undefined) {
                        payload.raw_source = rawSource;
                    } else {
                        if (envelope && typeof envelope === 'object' && !Array.isArray(envelope)) {
                            const { source_meta, ...rest } = envelope;
                            payload.envelope = rest;
                        } else {
                            payload.envelope = envelope;
                        }
                    }
                    return payload;
                },
            });
            const results = [];
            for await (const item of sourceAdapter.readItems()) {
                if (item.error) {
                    if (!definition.dead_letter) {
                        throw new Error(`Failed processing "${item.fileName}": ${item.error}`);
                    }
                    const write = await targetAdapter.onDeadLetter({
                        error: item.error,
                        rawSource: item.rawSource,
                        fileName: item.fileName,
                    });
                    results.push({
                        file: item.fileName,
                        route: null,
                        destination: deadLetterRelDir,
                        output_path: write.path,
                        dead_letter: true,
                    });
                    continue;
                }

                await processEnvelope(item.envelope, definition, {
                    loadMapping,
                    onRoute: async ({ route, output }) => {
                        const relDir = destinationPath(route.destination);
                        const write = await targetAdapter.onRoute({
                            route,
                            output,
                            envelope: item.envelope,
                        });
                        results.push({
                            file: item.fileName,
                            route: route.id,
                            destination: relDir,
                            output_path: write.path,
                        });
                    },
                    onDeadLetter: async ({ error, envelope: deadEnvelope }) => {
                        if (!definition.dead_letter) {
                            throw new Error(error);
                        }
                        const write = await targetAdapter.onDeadLetter({
                            error,
                            envelope: deadEnvelope,
                            fileName: item.fileName,
                        });
                        results.push({
                            file: item.fileName,
                            route: null,
                            destination: deadLetterRelDir,
                            output_path: write.path,
                            dead_letter: true,
                        });
                    },
                });
            }

            result = {
                processed: results.length,
                results,
            };
        } catch (err) {
            process.stderr.write(`Error: Batch routing failed: ${errorMessage(err)}\n`);
            process.exit(1);
        }
        process.stdout.write((args.pretty ? JSON.stringify(result, null, 2) : JSON.stringify(result)) + '\n');
        return;
    }

    let definition;
    try {
        definition = loadRoutingDefinition(args.routing);
    } catch (err) {
        process.stderr.write(`Error: ${errorMessage(err)}\n`);
        process.exit(1);
    }

    // New behavior: if routing.json declares a source, execute end-to-end (source + mapping + destinations)
    // instead of stdin/single-envelope transform mode.
    if (definition && definition.source) {
        let result;
        try {
            result = await runFromRoutingFile(args.routing, {
                ociProfile: process.env.OCI_CLI_PROFILE || 'DEFAULT',
                fileRootDir: definition.baseDir || path.dirname(args.routing),
            });
        } catch (err) {
            process.stderr.write(`Error: Routing runtime failed: ${errorMessage(err)}\n`);
            process.exit(1);
        }
        process.stdout.write((args.pretty ? JSON.stringify(result, null, 2) : JSON.stringify(result)) + '\n');
        return;
    }

    let loadMapping;
    try {
        loadMapping = await buildLoadMapping(definition);
    } catch (err) {
        process.stderr.write(`Error: ${errorMessage(err)}\n`);
        process.exit(1);
    }

    let rawEnvelope;
    if (args.input) {
        try {
            rawEnvelope = fs.readFileSync(args.input, 'utf8');
        } catch (err) {
            process.stderr.write(`Error: Cannot read input file "${args.input}": ${errorMessage(err)}\n`);
            process.exit(1);
        }
    } else {
        rawEnvelope = await readStdin();
    }

    let envelope;
    try {
        envelope = JSON.parse(rawEnvelope);
    } catch (err) {
        process.stderr.write(`Error: Input is not valid JSON: ${errorMessage(err)}\n`);
        process.exit(1);
    }

    let result;
    try {
        result = await routeTransformAll(envelope, definition, { loadMapping });
    } catch (err) {
        process.stderr.write(`Error: Routing failed: ${errorMessage(err)}\n`);
        process.exit(1);
    }

    process.stdout.write((args.pretty ? JSON.stringify(result, null, 2) : JSON.stringify(result)) + '\n');
}

main().catch((err) => {
    process.stderr.write(`Fatal: ${errorMessage(err)}\n`);
    process.exit(1);
});
