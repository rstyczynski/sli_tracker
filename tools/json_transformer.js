'use strict';
// tools/json_transformer.js
// Library: JSON-to-JSON transformation via JSONata mapping expression/object.
// Sprint 18 / SLI-26

const jsonata = require('jsonata');

function errorMessage(err) {
    if (err instanceof Error && typeof err.message === 'string') {
        return err.message;
    }
    if (err && typeof err === 'object') {
        if (typeof err.message === 'string' && err.message.trim() !== '') {
            return err.message;
        }
        try {
            return JSON.stringify(err);
        } catch (_) {
            // Fall through to String(err).
        }
    }
    return String(err);
}

function loadMappingFromObject(obj) {
    if (typeof obj !== 'object' || obj === null || Array.isArray(obj)) {
        throw new Error('Mapping must be a JSON object');
    }
    if (!('expression' in obj)) {
        throw new Error('Mapping file must contain an "expression" field');
    }
    if (typeof obj.expression !== 'string') {
        throw new Error('"expression" must be a string');
    }
    return obj;
}

function normalizeMapping(mapping) {
    if (typeof mapping === 'string') {
        if (mapping.trim() === '') {
            throw new Error('Mapping expression must be a non-empty string');
        }
        return { expression: mapping };
    }
    return loadMappingFromObject(mapping);
}

/**
 * Apply a mapping to a source document.
 * @param {any}    source   — parsed JSON source document
 * @param {object|string} mapping  — mapping object or raw JSONata expression
 * @returns {Promise<any>}  — transformed document
 * @throws (async) on invalid JSONata expression or evaluation error
 */
async function transform(source, mapping) {
    const normalizedMapping = normalizeMapping(mapping);
    let expr;
    try {
        expr = jsonata(normalizedMapping.expression);
    } catch (err) {
        throw new Error(`Invalid JSONata expression: ${errorMessage(err)}`);
    }
    try {
        return await expr.evaluate(source);
    } catch (err) {
        throw new Error(errorMessage(err));
    }
}

module.exports = { loadMappingFromObject, normalizeMapping, transform };
