'use strict';

const fdk = require('@fnproject/fdk');
const { runRouter } = require('./router_core');

fdk.handle(async (input) => {
    try {
        return await runRouter(input);
    } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        return { status: 'error', error: message };
    }
});
