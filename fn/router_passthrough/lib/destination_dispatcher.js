'use strict';
// tools/adapters/destination_dispatcher.js
// Dispatch routed outputs to the first adapter that supports the logical destination.
// Dead letters are resolved through the same adapter selection using deadLetterDestination.

function isObject(value) {
    return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function createDestinationDispatcher(options = {}) {
    if (!isObject(options)) {
        throw new Error('Destination dispatcher options must be an object');
    }

    const adapters = Array.isArray(options.adapters) ? options.adapters : [];
    const deadLetterDestination = options.deadLetterDestination;

    if (adapters.length === 0) {
        throw new Error('Destination dispatcher requires at least one adapter');
    }
    for (const adapter of adapters) {
        if (!isObject(adapter) || typeof adapter.onRoute !== 'function') {
            throw new Error('Each destination adapter must provide onRoute');
        }
    }
    if (deadLetterDestination !== undefined && !isObject(deadLetterDestination)) {
        throw new Error('Destination dispatcher deadLetterDestination must be an object');
    }

    function findAdapter(destination) {
        return adapters.find((adapter) => typeof adapter.supports !== 'function' || adapter.supports(destination));
    }

    return {
        async onRoute(context) {
            const destination = context && context.route ? context.route.destination : undefined;
            const adapter = findAdapter(destination);
            if (!adapter) {
                const type = destination && destination.type ? destination.type : 'unknown';
                throw new Error(`No adapter supports destination type "${type}"`);
            }
            return adapter.onRoute(context);
        },

        async onDeadLetter(context) {
            if (!deadLetterDestination) {
                throw new Error('No deadLetterDestination configured');
            }
            const adapter = findAdapter(deadLetterDestination);
            if (!adapter) {
                throw new Error(`No adapter supports dead letter destination type "${deadLetterDestination.type}"`);
            }
            // deliver via onRoute with the dead letter destination injected
            return adapter.onRoute({
                route: { id: 'dead_letter', destination: deadLetterDestination },
                output: context,
                envelope: context.envelope,
            });
        },
    };
}

module.exports = {
    createDestinationDispatcher,
};
