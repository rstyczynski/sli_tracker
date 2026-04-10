'use strict';
// tools/adapters/mapping_loader.js
// Resolve transform.mapping keys via a mapping source destination + mapping sources.

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
        throw new Error('Mapping loader destinationMap must be an object');
    }
    const exactKey = destinationKey(destination);
    if (exactKey && destinationMap[exactKey] !== undefined) {
        return destinationMap[exactKey];
    }
    if (destination && typeof destination.type === 'string' && destinationMap[destination.type] !== undefined) {
        return destinationMap[destination.type];
    }
    throw new Error(`Mapping loader has no target configured for destination "${exactKey}"`);
}

function normalizeMappingKey(mappingKey) {
    let key = String(mappingKey);
    // Common config uses "./file.jsonata" as a relative ref; mapping keys should be simple.
    key = key.replace(/^[.][\\/]/, '');
    key = key.replace(/^\/+/, '');
    if (key.includes('..')) {
        throw new Error('Mapping key must not contain ".."');
    }
    return key;
}

function createMappingLoader(options = {}) {
    if (!isObject(options)) {
        throw new Error('Mapping loader options must be an object');
    }
    const mappingSources = Array.isArray(options.mappingSources) ? options.mappingSources : [];
    const destinationMap = options.destinationMap;

    if (!isObject(destinationMap)) {
        throw new Error('Mapping loader requires destinationMap');
    }
    if (mappingSources.length === 0) {
        throw new Error('Mapping loader requires at least one mapping source');
    }
    for (const src of mappingSources) {
        if (!isObject(src) || typeof src.load !== 'function') {
            throw new Error('Each mapping source must provide load()');
        }
    }

    function findSource(destination) {
        return mappingSources.find((src) => typeof src.supports !== 'function' || src.supports(destination));
    }

    return async function loadMapping({ mapping, mappingKey, route, definition }) {
        if (!isObject(mapping) || typeof mapping.type !== 'string' || mapping.type.trim() === '') {
            throw new Error('Mapping loader requires a mapping destination with type');
        }
        const normalizedKey = normalizeMappingKey(mappingKey);
        const source = findSource(mapping);
        if (!source) {
            throw new Error(`No mapping source supports mapping destination type "${mapping.type}"`);
        }
        const target = resolveDestinationTarget(mapping, destinationMap);
        return await source.load({
            mapping,
            mappingKey: normalizedKey,
            target,
            route,
            definition,
        });
    };
}

module.exports = {
    createMappingLoader,
};

