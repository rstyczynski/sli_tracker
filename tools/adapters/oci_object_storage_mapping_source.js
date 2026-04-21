'use strict';
// tools/adapters/oci_object_storage_mapping_source.js
// Mapping source backed by OCI Object Storage.
// Supports both ContentSourceAdapter (SLI-60) and legacy getObject injection.

const jsonTransformer = require('../json_transformer');
const loadMappingFromObject = jsonTransformer.loadMappingFromObject;

function isObject(value) {
    return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function ensureFunction(value, label) {
    if (typeof value !== 'function') {
        throw new Error(`${label} must be a function`);
    }
    return value;
}

function ensureString(value, label) {
    if (typeof value !== 'string' || value.trim() === '') {
        throw new Error(`${label} must be a non-empty string`);
    }
    return value;
}

function joinPrefix(prefix, key) {
    const p = typeof prefix === 'string' ? prefix : '';
    const trimmedPrefix = p === '' ? '' : p.replace(/^\/+/, '').replace(/\/?$/, '/');
    return `${trimmedPrefix}${key}`;
}

function parseMappingPayload(mappingKey, raw) {
    if (mappingKey.endsWith('.jsonata')) {
        return String(raw).trim();
    }
    let parsed;
    try {
        parsed = JSON.parse(String(raw));
    } catch (err) {
        throw new Error(`Mapping payload for "${mappingKey}" is not valid JSON`);
    }
    return loadMappingFromObject(parsed);
}

/**
 * Create OCI Object Storage mapping source.
 * @param {Object} options
 * @param {Object} [options.contentSourceAdapter] - ContentSourceAdapter with readContent(key).
 * @param {Function} [options.getObject] - Legacy: async ({ bucket, objectName }) => string.
 * One of contentSourceAdapter or getObject must be provided.
 */
function createOciObjectStorageMappingSource(options = {}) {
    if (!isObject(options)) {
        throw new Error('OCI Object Storage mapping source options must be an object');
    }

    const contentSourceAdapter = options.contentSourceAdapter;
    const getObject = options.getObject;

    // Validate: one of contentSourceAdapter or getObject must be provided
    if (contentSourceAdapter && typeof contentSourceAdapter.readContent === 'function') {
        // New pattern: use ContentSourceAdapter
        return {
            supports(destination) {
                return isObject(destination) && destination.type === 'oci_object_storage';
            },

            async load({ mappingKey }) {
                const raw = await contentSourceAdapter.readContent(mappingKey);
                return parseMappingPayload(mappingKey, raw);
            },
        };
    }

    // Legacy pattern: use getObject function
    if (typeof getObject === 'function') {
        return {
            supports(destination) {
                return isObject(destination) && destination.type === 'oci_object_storage';
            },

            async load({ mappingKey, target }) {
                if (!isObject(target)) {
                    throw new Error('OCI Object Storage mapping source target must be an object');
                }
                const bucket = ensureString(target.bucket, 'OCI Object Storage mapping source target.bucket');
                const prefix = target.prefix === undefined ? '' : String(target.prefix);
                const objectName = joinPrefix(prefix, mappingKey);
                const raw = await getObject({ bucket, objectName, target });
                return parseMappingPayload(mappingKey, raw);
            },
        };
    }

    throw new Error('OCI Object Storage mapping source requires contentSourceAdapter or getObject');
}

module.exports = {
    createOciObjectStorageMappingSource,
};

