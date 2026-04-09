'use strict';
// tools/json_router.js
// Router: identify source payload type, select mapping, and transform.
// Sprint 19 / SLI-27

const fs = require('fs');
const path = require('path');
const Ajv2020 = require('ajv/dist/2020');
const jsonTransformer = require('./json_transformer');
const loadMappingFromObject = jsonTransformer.loadMappingFromObject;
const transform = jsonTransformer.transform;
const routingDefinitionSchema = require('./schemas/json_router_definition.schema.json');

const ajv = new Ajv2020({ allErrors: true, strict: false });
const validateRoutingDefinitionSchema = ajv.compile(routingDefinitionSchema);

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

function loadMapping(filePath) {
    if (typeof filePath !== 'string' || filePath.trim() === '') {
        throw new Error('Mapping file path must be a non-empty string');
    }
    let raw;
    try {
        raw = fs.readFileSync(filePath, 'utf8');
    } catch (err) {
        throw new Error(`Cannot read mapping file "${filePath}": ${errorMessage(err)}`);
    }
    if (filePath.endsWith('.jsonata')) {
        return raw.trim();
    }
    let parsed;
    try {
        parsed = JSON.parse(raw);
    } catch (err) {
        throw new Error(`Mapping file "${filePath}" is not valid JSON: ${errorMessage(err)}`);
    }
    return loadMappingFromObject(parsed);
}

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

function schemaErrorMessage(errors) {
    const first = Array.isArray(errors) && errors.length > 0 ? errors[0] : null;
    if (!first) {
        return 'Routing definition schema validation failed';
    }
    const where = first.instancePath && first.instancePath !== '' ? first.instancePath : '/';
    return `Routing definition schema validation failed: ${where} ${first.message}`;
}

function loadRoutingDefinitionFromObject(obj, options = {}) {
    if (!isObject(obj)) {
        throw new Error('Routing definition must be a JSON object');
    }
    if (!validateRoutingDefinitionSchema(obj)) {
        throw new Error(schemaErrorMessage(validateRoutingDefinitionSchema.errors));
    }

    const baseDir = options.baseDir || process.cwd();
    const seenRouteIds = new Set();

    const definition = {
        routes: obj.routes.map((route, index) => {
            if (!isObject(route)) {
                throw new Error(`Route at index ${index} must be an object`);
            }
            if (seenRouteIds.has(route.id)) {
                throw new Error(`Route id "${route.id}" is duplicated`);
            }
            seenRouteIds.add(route.id);

            return {
                id: route.id,
                mode: route.mode || 'exclusive',
                priority: Number.isFinite(route.priority) ? route.priority : 0,
                match: route.match || {},
                transform: {
                    mapping: path.resolve(baseDir, route.transform.mapping),
                },
                destination: route.destination,
            };
        }),
    };

    if (obj.dead_letter !== undefined) {
        if (!isObject(obj.dead_letter) || typeof obj.dead_letter.type !== 'string' || obj.dead_letter.type.trim() === '') {
            throw new Error('Routing definition dead_letter must define destination type');
        }
        definition.dead_letter = obj.dead_letter;
    }

    return definition;
}

function loadRoutingDefinition(filePath) {
    if (typeof filePath !== 'string' || filePath.trim() === '') {
        throw new Error('Routing definition path must be a non-empty string');
    }
    let raw;
    try {
        raw = fs.readFileSync(filePath, 'utf8');
    } catch (err) {
        throw new Error(`Cannot read routing definition "${filePath}": ${errorMessage(err)}`);
    }
    let parsed;
    try {
        parsed = JSON.parse(raw);
    } catch (err) {
        throw new Error(`Routing definition "${filePath}" is not valid JSON: ${errorMessage(err)}`);
    }
    return loadRoutingDefinitionFromObject(parsed, { baseDir: path.dirname(filePath) });
}

function normalizeRoutingDefinition(router, options = {}) {
    if (typeof router === 'string') {
        return loadRoutingDefinition(router);
    }
    if (isObject(router)) {
        return loadRoutingDefinitionFromObject(router, options);
    }
    throw new Error('Router argument must be a routing definition path or object');
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

function resolveExclusiveMatch(matches) {
    if (matches.length === 0) {
        return [];
    }

    const topPriority = Math.max(...matches.map((route) => route.priority));
    const topMatches = matches.filter((route) => route.priority === topPriority);

    if (topMatches.length > 1) {
        throw new Error(`Ambiguous routes matched envelope: ${topMatches.map((route) => route.id).join(', ')}`);
    }

    return [topMatches[0]];
}

function normalizeHandlers(handlers = {}) {
    if (!isObject(handlers)) {
        throw new Error('Handlers must be an object');
    }
    if (handlers.onRoute !== undefined && typeof handlers.onRoute !== 'function') {
        throw new Error('Handler onRoute must be a function');
    }
    if (handlers.onDeadLetter !== undefined && typeof handlers.onDeadLetter !== 'function') {
        throw new Error('Handler onDeadLetter must be a function');
    }
    return handlers;
}

function selectRoutes(envelope, definition) {
    const normalizedDefinition = normalizeRoutingDefinition(definition);
    if (!isObject(envelope)) {
        throw new Error('Envelope must be an object');
    }
    const matches = normalizedDefinition.routes.filter((route) => matchesRoute(envelope, route));
    if (matches.length === 0) {
        throw new Error('No route matched envelope');
    }

    const exclusiveMatches = matches.filter((route) => route.mode === 'exclusive');
    const fanoutMatches = matches.filter((route) => route.mode === 'fanout');

    return [...resolveExclusiveMatch(exclusiveMatches), ...fanoutMatches];
}

function selectRoute(envelope, definition) {
    const matches = selectRoutes(envelope, definition);
    if (matches.length !== 1) {
        throw new Error(`Multiple routes selected for envelope: ${matches.map((route) => route.id).join(', ')}`);
    }
    return matches[0];
}

async function routeTransformAll(envelope, definition) {
    const normalizedDefinition = normalizeRoutingDefinition(definition);
    const routes = selectRoutes(envelope, normalizedDefinition);
    const transformedRoutes = [];

    for (const route of routes) {
        const mapping = loadMapping(route.transform.mapping);
        const output = await transform(envelope.body, mapping);
        transformedRoutes.push({
            id: route.id,
            mode: route.mode,
            destination: route.destination,
            output,
        });
    }

    return { routes: transformedRoutes };
}

async function routeTransform(envelope, definition) {
    const routed = await routeTransformAll(envelope, definition);
    if (routed.routes.length !== 1) {
        throw new Error(`Multiple routes selected for envelope: ${routed.routes.map((route) => route.id).join(', ')}`);
    }
    const route = routed.routes[0];
    return {
        route: {
            id: route.id,
            destination: route.destination,
        },
        output: route.output,
    };
}

async function processEnvelope(envelope, definition, handlers = {}) {
    const normalizedHandlers = normalizeHandlers(handlers);
    const normalizedDefinition = normalizeRoutingDefinition(definition);

    try {
        const routed = await routeTransformAll(envelope, normalizedDefinition);
        const deliveries = [];

        for (const route of routed.routes) {
            const delivery = {
                route: {
                    id: route.id,
                    mode: route.mode,
                    destination: route.destination,
                },
                output: route.output,
            };
            if (normalizedHandlers.onRoute) {
                await normalizedHandlers.onRoute({
                    route: delivery.route,
                    output: delivery.output,
                    envelope,
                });
            }
            deliveries.push(delivery);
        }

        return {
            status: 'routed',
            deliveries,
        };
    } catch (err) {
        if (!normalizedHandlers.onDeadLetter) {
            throw err;
        }
        const message = errorMessage(err);
        await normalizedHandlers.onDeadLetter({
            error: message,
            envelope,
        });
        return {
            status: 'dead_letter',
            error: message,
        };
    }
}

async function processEnvelopes(envelopes, definition, handlers = {}) {
    const normalizedHandlers = normalizeHandlers(handlers);
    const normalizedDefinition = normalizeRoutingDefinition(definition);
    const results = [];
    let routed = 0;
    let deadLettered = 0;

    for await (const envelope of envelopes) {
        const result = await processEnvelope(envelope, normalizedDefinition, normalizedHandlers);
        results.push(result);
        if (result.status === 'routed') {
            routed += 1;
        } else if (result.status === 'dead_letter') {
            deadLettered += 1;
        }
    }

    return {
        processed: results.length,
        routed,
        dead_lettered: deadLettered,
        results,
    };
}

function destinationPath(route) {
    if (typeof route.destination.directory === 'string' && route.destination.directory.trim() !== '') {
        return route.destination.directory;
    }
    if (typeof route.destination.name === 'string' && route.destination.name.trim() !== '') {
        return path.join(route.destination.type, route.destination.name);
    }
    return route.destination.type;
}

function destinationPathFromDefinition(destination) {
    if (typeof destination.directory === 'string' && destination.directory.trim() !== '') {
        return destination.directory;
    }
    if (typeof destination.name === 'string' && destination.name.trim() !== '') {
        return path.join(destination.type, destination.name);
    }
    return destination.type;
}

function writeJsonFile(targetPath, value) {
    try {
        fs.mkdirSync(path.dirname(targetPath), { recursive: true });
        fs.writeFileSync(targetPath, JSON.stringify(value, null, 2) + '\n', 'utf8');
    } catch (err) {
        throw new Error(`Cannot write JSON file "${targetPath}": ${errorMessage(err)}`);
    }
}

async function routeDirectory(sourceDir, definition, destinationRoot) {
    const normalizedDefinition = normalizeRoutingDefinition(definition);
    let entries;
    try {
        entries = fs.readdirSync(sourceDir, { withFileTypes: true });
    } catch (err) {
        throw new Error(`Cannot read source directory "${sourceDir}": ${errorMessage(err)}`);
    }

    const files = entries
        .filter((entry) => entry.isFile() && entry.name.endsWith('.json'))
        .map((entry) => entry.name)
        .sort();

    const results = [];

    for (const fileName of files) {
        const sourcePath = path.join(sourceDir, fileName);
        let rawSource;
        let envelope;
        try {
            rawSource = fs.readFileSync(sourcePath, 'utf8');
            envelope = JSON.parse(rawSource);
        } catch (err) {
            if (!normalizedDefinition.dead_letter) {
                throw new Error(`Failed processing "${fileName}": source file is not valid JSON: ${errorMessage(err)}`);
            }
            const relDir = destinationPathFromDefinition(normalizedDefinition.dead_letter);
            const targetPath = path.join(destinationRoot, relDir, fileName);
            writeJsonFile(targetPath, {
                file: fileName,
                error: `source file is not valid JSON: ${errorMessage(err)}`,
                raw_source: rawSource,
            });
            results.push({
                file: fileName,
                route: null,
                destination: relDir,
                output_path: targetPath,
                dead_letter: true,
            });
            continue;
        }

        let routed;
        try {
            routed = await routeTransformAll(envelope, normalizedDefinition);
        } catch (err) {
            if (!normalizedDefinition.dead_letter) {
                throw new Error(`Failed processing "${fileName}": ${errorMessage(err)}`);
            }
            const relDir = destinationPathFromDefinition(normalizedDefinition.dead_letter);
            const targetPath = path.join(destinationRoot, relDir, fileName);
            writeJsonFile(targetPath, {
                file: fileName,
                error: errorMessage(err),
                envelope,
            });
            results.push({
                file: fileName,
                route: null,
                destination: relDir,
                output_path: targetPath,
                dead_letter: true,
            });
            continue;
        }

        for (const route of routed.routes) {
            const relDir = destinationPath(route);
            const targetDir = path.join(destinationRoot, relDir);
            const targetPath = path.join(targetDir, fileName);

            writeJsonFile(targetPath, route.output);

            results.push({
                file: fileName,
                route: route.id,
                destination: relDir,
                output_path: targetPath,
            });
        }
    }

    return { processed: results.length, results };
}

module.exports = {
    loadRoutingDefinition,
    loadRoutingDefinitionFromObject,
    normalizeRoutingDefinition,
    processEnvelope,
    processEnvelopes,
    selectRoutes,
    selectRoute,
    routeTransformAll,
    routeTransform,
    routeDirectory,
    errorMessage,
};
