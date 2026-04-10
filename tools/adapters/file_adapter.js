'use strict';
// tools/adapters/file_adapter.js
// Example filesystem target adapter for handler-based router processing.

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

function sanitizeSegment(value) {
    return String(value).replace(/[^A-Za-z0-9._-]+/g, '_');
}

function formatIndex(index) {
    return String(index).padStart(3, '0');
}

function destinationPath(destination) {
    if (typeof destination.directory === 'string' && destination.directory.trim() !== '') {
        return destination.directory;
    }
    if (typeof destination.name === 'string' && destination.name.trim() !== '') {
        return path.join(destination.type, destination.name);
    }
    return destination.type;
}

function writeJsonFile(targetPath, value) {
    fs.mkdirSync(path.dirname(targetPath), { recursive: true });
    fs.writeFileSync(targetPath, JSON.stringify(value, null, 2) + '\n', 'utf8');
}

function createFileAdapter(options = {}) {
    if (!isObject(options)) {
        throw new Error('File adapter options must be an object');
    }

    const rootDir = ensureString(options.rootDir, 'File adapter rootDir');
    const destinationMap = options.destinationMap;
    const deadLetterDir = options.deadLetterDir === undefined
        ? 'dead_letter/errors'
        : ensureString(options.deadLetterDir, 'File adapter deadLetterDir');
    const preserveSourceFileName = options.preserveSourceFileName === true;
    const supportedTypes = Array.isArray(options.supportedTypes) ? new Set(options.supportedTypes) : null;
    const formatDeadLetter = options.formatDeadLetter === undefined
        ? ({ error, envelope }) => ({ error, envelope })
        : options.formatDeadLetter;

    if (typeof formatDeadLetter !== 'function') {
        throw new Error('File adapter formatDeadLetter must be a function');
    }

    let routeIndex = 0;
    let deadIndex = 0;
    const state = {
        routeWrites: [],
        deadLetterWrites: [],
    };

    function resolveFileName(envelope, explicitFileName, fallbackName) {
        if (typeof explicitFileName === 'string' && explicitFileName.trim() !== '') {
            return explicitFileName;
        }
        const sourceName = isObject(envelope) && isObject(envelope.source_meta) ? envelope.source_meta.file_name : undefined;
        if (preserveSourceFileName && typeof sourceName === 'string' && sourceName.trim() !== '') {
            return sourceName;
        }
        return fallbackName;
    }

    function destinationPath(destination) {
        if (isObject(destinationMap)) {
            const exactKey = typeof destination.name === 'string' && destination.name.trim() !== ''
                ? `${destination.type}:${destination.name}`
                : destination.type;
            const mapped = destinationMap[exactKey] !== undefined ? destinationMap[exactKey] : destinationMap[destination.type];
            if (isObject(mapped) && typeof mapped.directory === 'string' && mapped.directory.trim() !== '') {
                return mapped.directory;
            }
            // legacy: plain string value
            if (typeof mapped === 'string' && mapped.trim() !== '') {
                return mapped;
            }
        }
        if (typeof destination.name === 'string' && destination.name.trim() !== '') {
            return path.join(destination.type, destination.name);
        }
        return destination.type;
    }

    return {
        supports(destination) {
            return isObject(destination) && (!supportedTypes || supportedTypes.has(destination.type));
        },

        async onRoute({ route, output, envelope }) {
            routeIndex += 1;
            if (!this.supports(route.destination)) {
                throw new Error(`File adapter does not support destination type "${route.destination.type}"`);
            }
            const relDir = destinationPath(route.destination);
            const fileName = resolveFileName(envelope, undefined, `${formatIndex(routeIndex)}_${sanitizeSegment(route.id)}.json`);
            const targetPath = path.join(rootDir, relDir, fileName);
            writeJsonFile(targetPath, output);
            state.routeWrites.push({
                route: route.id,
                path: targetPath,
            });
            return {
                path: targetPath,
            };
        },

        async onDeadLetter({ error, envelope, rawSource, fileName: explicitFileName }) {
            deadIndex += 1;
            const fileName = resolveFileName(envelope, explicitFileName, `${formatIndex(deadIndex)}_dead_letter.json`);
            const targetPath = path.join(rootDir, deadLetterDir, fileName);
            writeJsonFile(targetPath, formatDeadLetter({
                error,
                envelope,
                rawSource,
                fileName,
            }));
            state.deadLetterWrites.push({
                path: targetPath,
            });
            return {
                path: targetPath,
            };
        },

        getState() {
            return {
                routeWrites: [...state.routeWrites],
                deadLetterWrites: [...state.deadLetterWrites],
            };
        },
    };
}

module.exports = {
    createFileAdapter,
};
