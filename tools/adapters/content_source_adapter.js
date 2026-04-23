'use strict';
// tools/adapters/content_source_adapter.js
// Unified ContentSourceAdapter interface for loading routing definitions and mappings.
// Sprint 30 / SLI-60

const fs = require('fs');
const path = require('path');

function isObject(value) {
    return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function errorMessage(err) {
    if (err instanceof Error && typeof err.message === 'string') {
        return err.message;
    }
    return String(err);
}

/**
 * Create a FileSystem-backed ContentSourceAdapter.
 * @param {Object} options
 * @param {string} [options.basePath] - Base directory for resolving keys. Defaults to process.cwd().
 * @returns {Object} ContentSourceAdapter with readContent(key) method.
 */
function createFileSystemContentSourceAdapter(options = {}) {
    if (!isObject(options)) {
        throw new Error('FileSystem content source adapter options must be an object');
    }

    const basePath = typeof options.basePath === 'string' && options.basePath.trim() !== ''
        ? options.basePath
        : process.cwd();

    return {
        /**
         * Read content from the filesystem.
         * @param {string} key - File path (absolute or relative to basePath).
         * @returns {Promise<string>} File content as string.
         */
        async readContent(key) {
            if (typeof key !== 'string' || key.trim() === '') {
                throw new Error('Content key must be a non-empty string');
            }

            const resolvedPath = path.isAbsolute(key) ? key : path.resolve(basePath, key);

            try {
                return fs.readFileSync(resolvedPath, 'utf8');
            } catch (err) {
                throw new Error(`Cannot read content "${resolvedPath}": ${errorMessage(err)}`);
            }
        },
    };
}

/**
 * Parse an oci:// URI into bucket and object key components.
 * Format: oci://bucket/object-key or oci://bucket/prefix/
 * @param {string} uri - The URI to parse.
 * @returns {Object} { bucket, objectKey } or null if not an oci:// URI.
 */
function parseOciUri(uri) {
    if (typeof uri !== 'string') {
        return null;
    }

    const match = uri.match(/^oci:\/\/([^/]+)\/(.*)$/);
    if (!match) {
        return null;
    }

    return {
        bucket: match[1],
        objectKey: match[2],
    };
}

/**
 * Check if a string is an oci:// URI.
 * @param {string} value - The value to check.
 * @returns {boolean} True if value is an oci:// URI.
 */
function isOciUri(value) {
    return typeof value === 'string' && value.startsWith('oci://');
}

module.exports = {
    createFileSystemContentSourceAdapter,
    parseOciUri,
    isOciUri,
};
