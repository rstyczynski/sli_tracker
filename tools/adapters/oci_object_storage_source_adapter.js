'use strict';
// tools/adapters/oci_object_storage_source_adapter.js
// OCI Object Storage source adapter for handler-based router processing.

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

function joinPrefix(prefix, name) {
    const p = typeof prefix === 'string' ? prefix : '';
    const trimmedPrefix = p === '' ? '' : p.replace(/^\/+/, '').replace(/\/?$/, '/');
    return `${trimmedPrefix}${name}`;
}

function stripPrefix(prefix, objectName) {
    const p = typeof prefix === 'string' ? prefix : '';
    const norm = p.replace(/^\/+/, '').replace(/\/?$/, '/');
    if (norm === '') return objectName;
    return objectName.startsWith(norm) ? objectName.slice(norm.length) : objectName;
}

function createOciObjectStorageSourceAdapter(options = {}) {
    if (!isObject(options)) {
        throw new Error('OCI Object Storage source adapter options must be an object');
    }

    const bucket = ensureString(options.bucket, 'OCI Object Storage source adapter bucket');
    const prefix = options.prefix === undefined ? '' : String(options.prefix);
    const extension = options.extension === undefined ? '.json' : ensureString(options.extension, 'OCI Object Storage source adapter extension');
    const listObjects = options.listObjects;
    const getObject = options.getObject;

    if (typeof listObjects !== 'function') {
        throw new Error('OCI Object Storage source adapter listObjects must be a function');
    }
    if (typeof getObject !== 'function') {
        throw new Error('OCI Object Storage source adapter getObject must be a function');
    }

    const state = { objectsRead: [] };

    return {
        async *readItems() {
            let objects;
            try {
                objects = await listObjects({ bucket, prefix });
            } catch (err) {
                throw new Error(`Cannot list objects for bucket "${bucket}": ${errorMessage(err)}`);
            }
            const names = (Array.isArray(objects) ? objects : [])
                .map((o) => (o && typeof o === 'object' ? o.name : o))
                .filter((n) => typeof n === 'string')
                .filter((n) => n.startsWith(joinPrefix(prefix, '')) && n.endsWith(extension))
                .sort((a, b) => a.localeCompare(b));

            for (const objectName of names) {
                let raw;
                try {
                    raw = await getObject({ bucket, objectName });
                } catch (err) {
                    throw new Error(`Cannot read object "${bucket}/${objectName}": ${errorMessage(err)}`);
                }

                let parsed;
                try {
                    parsed = JSON.parse(String(raw));
                } catch (err) {
                    yield {
                        objectName,
                        rawSource: String(raw),
                        error: `source object is not valid JSON: ${errorMessage(err)}`,
                    };
                    continue;
                }

                if (isObject(parsed)) {
                    const sourceMeta = isObject(parsed.source_meta) ? parsed.source_meta : {};
                    parsed.source_meta = {
                        ...sourceMeta,
                        file_name: stripPrefix(prefix, objectName),
                        object_name: objectName,
                        bucket,
                    };
                }

                state.objectsRead.push(objectName);
                yield {
                    objectName,
                    rawSource: String(raw),
                    envelope: parsed,
                };
            }
        },

        async *readEnvelopes() {
            for await (const item of this.readItems()) {
                if (item.error) {
                    throw new Error(`Source object "${bucket}/${item.objectName}" is not valid JSON: ${item.error.replace(/^source object is not valid JSON: /, '')}`);
                }
                yield item.envelope;
            }
        },

        getState() {
            return { objectsRead: [...state.objectsRead] };
        },
    };
}

module.exports = {
    createOciObjectStorageSourceAdapter,
};

