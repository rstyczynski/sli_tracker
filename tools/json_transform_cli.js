#!/usr/bin/env node
'use strict';
// tools/json_transform_cli.js
// CLI wrapper: apply a JSONata mapping file to a JSON source document.
// Sprint 18 / SLI-26
//
// Usage:
//   node tools/json_transform_cli.js --mapping <file> [--input <file>] [--pretty]
//   cat source.json | node tools/json_transform_cli.js --mapping <file>

const fs = require('fs');
const jsonTransformer = require('./json_transformer');
const transform = jsonTransformer.transform;
const loadMappingFromObject = jsonTransformer.loadMappingFromObject;

function usage(code) {
    process.stderr.write([
        'Usage: node json_transform_cli.js --mapping <file> [--input <file>] [--pretty]',
        '       cat source.json | node json_transform_cli.js --mapping <file>',
        '',
        'Options:',
        '  --mapping  Path to JSONata mapping JSON file (required)',
        '  --input    Path to source JSON file (optional; reads stdin if omitted)',
        '  --pretty   Pretty-print output (default: compact)',
        '  --help     Show this help',
    ].join('\n') + '\n');
    process.exit(code);
}

function parseArgs(argv) {
    const args = { mapping: null, input: null, pretty: false };
    const known = new Set(['--mapping', '--input', '--pretty', '--help']);
    for (let i = 0; i < argv.length; i++) {
        const a = argv[i];
        if (!known.has(a)) {
            process.stderr.write(`Unknown option: ${a}\n`);
            usage(1);
        }
        if (a === '--help') usage(0);
        if (a === '--pretty') { args.pretty = true; continue; }
        const val = argv[++i];
        if (a === '--mapping') args.mapping = val;
        if (a === '--input')   args.input   = val;
    }
    return args;
}

function readStdin() {
    return new Promise((resolve, reject) => {
        const chunks = [];
        process.stdin.on('data', c => chunks.push(c));
        process.stdin.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
        process.stdin.on('error', reject);
    });
}

async function main() {
    const args = parseArgs(process.argv.slice(2));

    if (!args.mapping) {
        process.stderr.write('Error: --mapping is required\n');
        usage(1);
    }

    let rawMapping;
    try {
        rawMapping = fs.readFileSync(args.mapping, 'utf8');
    } catch (err) {
        process.stderr.write(`Error: Cannot read mapping file "${args.mapping}": ${err.message}\n`);
        process.exit(1);
    }

    let mapping;
    if (args.mapping.endsWith('.jsonata')) {
        mapping = rawMapping;
    } else {
        let parsedMapping;
        try {
            parsedMapping = JSON.parse(rawMapping);
        } catch (err) {
            process.stderr.write(`Error: Mapping file "${args.mapping}" is not valid JSON: ${err.message}\n`);
            process.exit(1);
        }
        try {
            mapping = loadMappingFromObject(parsedMapping);
        } catch (err) {
            process.stderr.write(`Error: ${err.message}\n`);
            process.exit(1);
        }
    }

    // Read source
    let rawSource;
    if (args.input) {
        try {
            rawSource = fs.readFileSync(args.input, 'utf8');
        } catch (err) {
            process.stderr.write(`Error: Cannot read input file "${args.input}": ${err.message}\n`);
            process.exit(1);
        }
    } else {
        rawSource = await readStdin();
    }

    // Parse source
    let source;
    try {
        source = JSON.parse(rawSource);
    } catch (err) {
        process.stderr.write(`Error: Source is not valid JSON: ${err.message}\n`);
        process.exit(1);
    }

    // Transform
    let result;
    try {
        result = await transform(source, mapping);
    } catch (err) {
        process.stderr.write(`Error: Transform failed: ${err.message}\n`);
        process.exit(1);
    }

    const out = args.pretty
        ? JSON.stringify(result, null, 2)
        : JSON.stringify(result);
    process.stdout.write(out + '\n');
}

main().catch(err => {
    process.stderr.write(`Fatal: ${err.message}\n`);
    process.exit(1);
});
