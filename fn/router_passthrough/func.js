'use strict';

const fdk = require('@fnproject/fdk');
const { runRouter } = require('./router_core');

fdk.handle(async (input, ctx) => {
    try {
        return await runRouter(input, { fdkContext: ctx });
    } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        return { status: 'error', error: message };
    }
});
