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

const fileSourceAdapter = require('./adapters/file_source_adapter');
const createFileSourceAdapter = fileSourceAdapter.createFileSourceAdapter;
const fileAdapter = require('./adapters/file_adapter');
const createFileAdapter = fileAdapter.createFileAdapter;

function destinationPath(destination) {
    if (typeof destination.directory === 'string' && destination.directory.trim() !== '') {
        return destination.directory;
    }
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
        result = await routeTransformAll(envelope, definition);
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
