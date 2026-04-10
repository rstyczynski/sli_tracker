'use strict';
// tools/adapters/source_loader.js
// Resolve definition.source via adapters into a concrete source adapter.

const path = require('path');

const fileSource = require('./file_source_adapter');
const createFileSourceAdapter = fileSource.createFileSourceAdapter;
const ociSource = require('./oci_object_storage_source_adapter');
const createOciObjectStorageSourceAdapter = ociSource.createOciObjectStorageSourceAdapter;

function isObject(value) {
    return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function destinationKey(destination) {
    const type = destination && typeof destination.type === 'string' ? destination.type : '';
    const name = destination && typeof destination.name === 'string' ? destination.name : '';
    return name === '' ? type : `${type}:${name}`;
}

function resolveDestinationTarget(destination, destinationMap) {
    if (!isObject(destinationMap)) {
        throw new Error('Source loader destinationMap must be an object');
    }
    const exactKey = destinationKey(destination);
    if (exactKey && destinationMap[exactKey] !== undefined) {
        return destinationMap[exactKey];
    }
    if (destination && typeof destination.type === 'string' && destinationMap[destination.type] !== undefined) {
        return destinationMap[destination.type];
    }
    throw new Error(`Source loader has no target configured for destination "${exactKey}"`);
}

function ensureString(value, label) {
    if (typeof value !== 'string' || value.trim() === '') {
        throw new Error(`${label} must be a non-empty string`);
    }
    return value;
}

function createSourceAdapterFromDefinition(definition, options = {}) {
    if (!isObject(definition) || !isObject(definition.source)) {
        throw new Error('Source loader requires definition.source');
    }
    if (!isObject(definition.adapters)) {
        throw new Error('Source loader requires definition.adapters');
    }

    const baseDir = definition.baseDir || process.cwd();
    const source = definition.source;
    const target = resolveDestinationTarget(source, definition.adapters);

    if (source.type === 'file_system') {
        if (!isObject(target)) {
            throw new Error('File source adapter target must be an object');
        }
        const dir = ensureString(target.directory || target.sourceDir, 'File source adapter directory');
        const sourceDir = path.resolve(baseDir, dir);
        const extension = target.extension;
        return createFileSourceAdapter({ sourceDir, extension });
    }

    if (source.type === 'oci_object_storage') {
        if (!isObject(target)) {
            throw new Error('OCI Object Storage source adapter target must be an object');
        }
        const bucket = ensureString(target.bucket, 'OCI Object Storage source adapter bucket');
        const prefix = target.prefix === undefined ? '' : String(target.prefix);
        const extension = target.extension;

        const listObjects = options.listObjects;
        const getObject = options.getObject;
        if (typeof listObjects !== 'function' || typeof getObject !== 'function') {
            throw new Error('OCI Object Storage source adapter requires listObjects and getObject');
        }
        return createOciObjectStorageSourceAdapter({ bucket, prefix, extension, listObjects, getObject });
    }

    throw new Error(`Unsupported source type "${source.type}"`);
}

module.exports = {
    createSourceAdapterFromDefinition,
};

