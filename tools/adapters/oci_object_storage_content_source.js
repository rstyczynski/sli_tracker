'use strict';
// tools/adapters/oci_object_storage_content_source.js
// OCI Object Storage backed ContentSourceAdapter.
// Sprint 30 / SLI-60

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

function errorMessage(err) {
    if (err instanceof Error && typeof err.message === 'string') {
        return err.message;
    }
    return String(err);
}

/**
 * Create an OCI Object Storage backed ContentSourceAdapter.
 * @param {Object} options
 * @param {string} options.bucket - Bucket name.
 * @param {Function} options.getObject - Async function: ({ bucket, objectName }) => Promise<string>.
 * @param {string} [options.prefix] - Optional prefix prepended to keys.
 * @returns {Object} ContentSourceAdapter with readContent(key) method.
 */
function createOciObjectStorageContentSourceAdapter(options = {}) {
    if (!isObject(options)) {
        throw new Error('OCI Object Storage content source adapter options must be an object');
    }

    const bucket = ensureString(options.bucket, 'OCI Object Storage content source adapter bucket');
    const getObject = ensureFunction(options.getObject, 'OCI Object Storage content source adapter getObject');
    const prefix = typeof options.prefix === 'string' ? options.prefix : '';

    return {
        /**
         * Read content from OCI Object Storage.
         * @param {string} key - Object key (prefix is prepended if configured).
         * @returns {Promise<string>} Object content as string.
         */
        async readContent(key) {
            if (typeof key !== 'string' || key.trim() === '') {
                throw new Error('Content key must be a non-empty string');
            }

            const objectName = prefix ? `${prefix}${key}` : key;

            try {
                const content = await getObject({ bucket, objectName });
                return String(content);
            } catch (err) {
                throw new Error(`Cannot read object "${objectName}" from bucket "${bucket}": ${errorMessage(err)}`);
            }
        },
    };
}

module.exports = {
    createOciObjectStorageContentSourceAdapter,
};
