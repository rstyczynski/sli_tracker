'use strict';
// tools/json_transformer.js
// Library: JSON-to-JSON transformation via JSONata mapping file.
// Sprint 18 / SLI-26

const fs = require('fs');
const jsonata = require('jsonata');

/**
 * Load and validate a mapping definition from an object (already parsed).
 * @param {object} obj
 * @returns {{ version: string, description?: string, expression: string }}
 * @throws if `expression` is missing or not a string
 */
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

/**
 * Load and validate a mapping definition from a file.
 * @param {string} filePath
 * @returns {{ version: string, description?: string, expression: string }}
 * @throws on missing file, invalid JSON, or missing/bad expression field
 */
function loadMapping(filePath) {
    let raw;
    try {
        raw = fs.readFileSync(filePath, 'utf8');
    } catch (err) {
        throw new Error(`Cannot read mapping file "${filePath}": ${err.message}`);
    }
    let parsed;
    try {
        parsed = JSON.parse(raw);
    } catch (err) {
        throw new Error(`Mapping file "${filePath}" is not valid JSON: ${err.message}`);
    }
    return loadMappingFromObject(parsed);
}

/**
 * Apply a mapping to a source document.
 * @param {any}    source   — parsed JSON source document
 * @param {object} mapping  — mapping object from loadMapping / loadMappingFromObject
 * @returns {Promise<any>}  — transformed document
 * @throws (async) on invalid JSONata expression or evaluation error
 */
async function transform(source, mapping) {
    let expr;
    try {
        expr = jsonata(mapping.expression);
    } catch (err) {
        throw new Error(`Invalid JSONata expression: ${err.message}`);
    }
    return expr.evaluate(source);
}

module.exports = { loadMapping, loadMappingFromObject, transform };
