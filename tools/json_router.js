'use strict';
// tools/json_router.js
// Router: identify source payload type, select mapping, and transform.
// Sprint 19 / SLI-27

const fs = require('fs');
const path = require('path');
const { loadMapping, transform } = require('./json_transformer');

function isObject(value) {
    return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function getPath(obj, dotPath) {
    return String(dotPath).split('.').reduce((acc, key) => {
        if (acc === undefined || acc === null) return undefined;
        return acc[key];
    }, obj);
}

function hasPath(obj, dotPath) {
    return getPath(obj, dotPath) !== undefined;
}

function normalizeHeaders(headers) {
    const normalized = {};
    if (!isObject(headers)) return normalized;
    for (const [key, value] of Object.entries(headers)) {
        normalized[String(key).toLowerCase()] = value;
    }
    return normalized;
}

function loadRoutingDefinitionFromObject(obj, options = {}) {
    if (!isObject(obj)) {
        throw new Error('Routing definition must be a JSON object');
    }
    if (!Array.isArray(obj.routes) || obj.routes.length === 0) {
        throw new Error('Routing definition must contain a non-empty "routes" array');
    }

    const baseDir = options.baseDir || process.cwd();

    return {
        routes: obj.routes.map((route, index) => {
            if (!isObject(route)) {
                throw new Error(`Route at index ${index} must be an object`);
            }
            if (typeof route.id !== 'string' || route.id.trim() === '') {
                throw new Error(`Route at index ${index} must contain a non-empty "id"`);
            }
            if (!isObject(route.transform) || typeof route.transform.mapping !== 'string' || route.transform.mapping.trim() === '') {
                throw new Error(`Route "${route.id}" must define transform.mapping`);
            }
            if (!isObject(route.destination) || typeof route.destination.type !== 'string' || route.destination.type.trim() === '') {
                throw new Error(`Route "${route.id}" must define destination.type`);
            }
            if (route.match !== undefined && !isObject(route.match)) {
                throw new Error(`Route "${route.id}" match must be an object`);
            }

            return {
                id: route.id,
                priority: Number.isFinite(route.priority) ? route.priority : 0,
                match: route.match || {},
                transform: {
                    mapping: path.resolve(baseDir, route.transform.mapping),
                },
                destination: route.destination,
            };
        }),
    };
}

function loadRoutingDefinition(filePath) {
    let raw;
    try {
        raw = fs.readFileSync(filePath, 'utf8');
    } catch (err) {
        throw new Error(`Cannot read routing definition "${filePath}": ${err.message}`);
    }
    let parsed;
    try {
        parsed = JSON.parse(raw);
    } catch (err) {
        throw new Error(`Routing definition "${filePath}" is not valid JSON: ${err.message}`);
    }
    return loadRoutingDefinitionFromObject(parsed, { baseDir: path.dirname(filePath) });
}

function matchesRoute(envelope, route) {
    const match = route.match || {};
    const headers = normalizeHeaders(envelope.headers);
    const body = envelope.body;

    if (!isObject(body) && !Array.isArray(body)) {
        return false;
    }

    if (isObject(match.headers)) {
        for (const [key, value] of Object.entries(match.headers)) {
            if (headers[String(key).toLowerCase()] !== value) {
                return false;
            }
        }
    }

    if (match.endpoint !== undefined && envelope.endpoint !== match.endpoint) {
        return false;
    }

    if (match.schema !== undefined) {
        if (!isObject(match.schema) || typeof match.schema.path !== 'string') {
            throw new Error(`Route "${route.id}" schema matcher must define { path, equals }`);
        }
        if (getPath(body, match.schema.path) !== match.schema.equals) {
            return false;
        }
    }

    if (Array.isArray(match.required_fields)) {
        for (const fieldPath of match.required_fields) {
            if (!hasPath(body, fieldPath)) {
                return false;
            }
        }
    }

    return true;
}

function selectRoute(envelope, definition) {
    if (!isObject(envelope)) {
        throw new Error('Envelope must be an object');
    }
    const matches = definition.routes.filter((route) => matchesRoute(envelope, route));
    if (matches.length === 0) {
        throw new Error('No route matched envelope');
    }

    const topPriority = Math.max(...matches.map((route) => route.priority));
    const topMatches = matches.filter((route) => route.priority === topPriority);

    if (topMatches.length > 1) {
        throw new Error(`Ambiguous routes matched envelope: ${topMatches.map((route) => route.id).join(', ')}`);
    }

    return topMatches[0];
}

async function routeTransform(envelope, definition) {
    const route = selectRoute(envelope, definition);
    const mapping = loadMapping(route.transform.mapping);
    const output = await transform(envelope.body, mapping);
    return {
        route: {
            id: route.id,
            destination: route.destination,
        },
        output,
    };
}

module.exports = {
    loadRoutingDefinition,
    loadRoutingDefinitionFromObject,
    selectRoute,
    routeTransform,
};
