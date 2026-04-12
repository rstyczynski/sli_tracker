'use strict';
// tools/adapters/oci_monitoring_adapter.js
// Example OCI Monitoring target adapter for handler-based router processing.

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
        throw new Error('OCI Monitoring adapter destinationMap must be an object');
    }
    const exactKey = destinationKey(destination);
    if (exactKey && destinationMap[exactKey] !== undefined) {
        return destinationMap[exactKey];
    }
    if (destination && typeof destination.type === 'string' && destinationMap[destination.type] !== undefined) {
        return destinationMap[destination.type];
    }
    throw new Error(`OCI Monitoring adapter has no target configured for destination "${exactKey}"`);
}

function createOciMonitoringAdapter(options = {}) {
    if (!isObject(options)) {
        throw new Error('OCI Monitoring adapter options must be an object');
    }
    const destinationMap = options.destinationMap || {};
    const emit = typeof options.emit === 'function' ? options.emit : async () => {};
    const supportedTypes = new Set(['oci_monitoring', 'oci_metric']);
    const state = { deliveries: [] };

    return {
        supports(destination) {
            return isObject(destination) && supportedTypes.has(destination.type);
        },

        async onRoute({ route, output, envelope }) {
            const target = resolveDestinationTarget(route.destination, destinationMap);
            await emit({ route, output, envelope, target });
            state.deliveries.push({
                route: route.id,
                target,
            });
            return { target };
        },

        getState() {
            return { deliveries: [...state.deliveries] };
        },
    };
}

module.exports = {
    createOciMonitoringAdapter,
};
