#!/usr/bin/env node
// post.js — post hook for sli-event-js action.
// Emits SLI event to OCI Logging via curl backend (reuses emit.sh).
// Outcome resolution: INPUT_OUTCOME -> GITHUB_JOB_STATUS env -> "success" fallback.

'use strict';

const { spawnSync } = require('child_process');
const path = require('path');
const fs   = require('fs');

function getInput(name) {
  const key = 'INPUT_' + name.toUpperCase().replace(/-/g, '_');
  return (process.env[key] || '').trim();
}

function githubNotice(msg) { process.stdout.write('::notice::' + msg + '\n'); }
function githubDebug(msg)  { process.stdout.write('::debug::'  + msg + '\n'); }
function githubError(msg)  { process.stderr.write('::error::'  + msg + '\n'); }

const outcome   = getInput('outcome') || process.env.GITHUB_JOB_STATUS || 'success';
const logId     = getInput('log-id')  || process.env.SLI_OCI_LOG_ID    || '';
const profile   = getInput('profile') || 'SLI_TEST';
const domain    = getInput('oci-api-domain') || 'oraclecloud.com';
const home      = process.env.HOME || process.env.USERPROFILE || '';

githubDebug('sli-event-js post hook: outcome=' + outcome + ' profile=' + profile);

const emitScript = path.join(__dirname, '../sli-event/emit.sh');

if (!fs.existsSync(emitScript)) {
  githubError('emit.sh not found at ' + emitScript);
  // Never fail the job due to SLI reporting — exit 0.
  process.exit(0);
}

const ociBlock = {
  'config-file': home + '/.oci/config',
  profile:       profile,
};
if (logId) {
  ociBlock['log-id'] = logId;
}

const contextJson = JSON.stringify({ oci: ociBlock });

const result = spawnSync('bash', [emitScript], {
  env: Object.assign({}, process.env, {
    SLI_OUTCOME:      outcome,
    SLI_OCI_LOG_ID:   logId,
    SLI_CONTEXT_JSON: contextJson,
    EMIT_BACKEND:     'curl',
    OCI_API_DOMAIN:   domain,
    INPUTS_JSON:      '{}',
    STEPS_JSON:       '{}',
  }),
  stdio: 'inherit',
});

if (result.error) {
  githubError('Failed to spawn emit.sh: ' + result.error.message);
  // Never fail the job due to SLI reporting.
  process.exit(0);
}

if (result.status !== 0) {
  githubNotice('SLI emit exited ' + result.status + ' — continuing (SLI reporting must not break jobs)');
}

// Always exit 0 from the post hook — SLI emit must never break the workflow.
process.exit(0);
