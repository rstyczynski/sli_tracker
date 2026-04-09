'use strict';
// tools/adapters/file_source_adapter.js
// Example filesystem source adapter for handler-based router processing.

const fs = require('fs');
const path = require('path');

function isObject(value) {
    return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function ensureString(value, label) {
    if (typeof value !== 'string' || value.trim() === '') {
        throw new Error(`${label} must be a non-empty string`);
    }
    return value;
}

function errorMessage(err) {
    if (err instanceof Error && typeof err.message === 'string') {
        return err.message;
    }
    return String(err);
}

function createFileSourceAdapter(options = {}) {
    if (!isObject(options)) {
        throw new Error('File source adapter options must be an object');
    }

    const sourceDir = ensureString(options.sourceDir, 'File source adapter sourceDir');
    const extension = options.extension === undefined
        ? '.json'
        : ensureString(options.extension, 'File source adapter extension');

    const state = {
        filesRead: [],
    };

    return {
        async *readItems() {
            let entries;
            try {
                entries = fs.readdirSync(sourceDir, { withFileTypes: true });
            } catch (err) {
                throw new Error(`Cannot read source directory "${sourceDir}": ${errorMessage(err)}`);
            }

            const files = entries
                .filter((entry) => entry.isFile() && entry.name.endsWith(extension))
                .map((entry) => entry.name)
                .sort((a, b) => a.localeCompare(b));

            for (const name of files) {
                const filePath = path.join(sourceDir, name);
                let raw;
                try {
                    raw = fs.readFileSync(filePath, 'utf8');
                } catch (err) {
                    throw new Error(`Cannot read source file "${filePath}": ${errorMessage(err)}`);
                }

                let parsed;
                try {
                    parsed = JSON.parse(raw);
                } catch (err) {
                    yield {
                        fileName: name,
                        filePath,
                        rawSource: raw,
                        error: `source file is not valid JSON: ${errorMessage(err)}`,
                    };
                    continue;
                }

                if (isObject(parsed)) {
                    const sourceMeta = isObject(parsed.source_meta) ? parsed.source_meta : {};
                    parsed.source_meta = {
                        ...sourceMeta,
                        file_name: name,
                        file_path: filePath,
                    };
                }

                state.filesRead.push(filePath);
                yield {
                    fileName: name,
                    filePath,
                    rawSource: raw,
                    envelope: parsed,
                };
            }
        },

        async *readEnvelopes() {
            for await (const item of this.readItems()) {
                if (item.error) {
                    throw new Error(`Source file "${item.filePath}" is not valid JSON: ${item.error.replace(/^source file is not valid JSON: /, '')}`);
                }
                yield item.envelope;
            }
        },

        getState() {
            return {
                filesRead: [...state.filesRead],
            };
        },
    };
}

module.exports = {
    createFileSourceAdapter,
};
