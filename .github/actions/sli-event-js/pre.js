#!/usr/bin/env node
// pre.js — pre hook for sli-event-js action.
// If oci-config-payload is provided, restores ~/.oci profile via oci_profile_setup.sh.
// Uses OCI_AUTH_MODE=none (curl backend does its own signing; no oci CLI wrapper needed).

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

const payload = getInput('oci-config-payload');
if (!payload) {
  githubDebug('oci-config-payload not provided — skipping OCI profile setup in pre hook');
  process.exit(0);
}

const profile    = getInput('profile') || 'SLI_TEST';
const setupScript = path.join(__dirname, '../oci-profile-setup/oci_profile_setup.sh');

if (!fs.existsSync(setupScript)) {
  githubError('oci_profile_setup.sh not found at ' + setupScript);
  process.exit(1);
}

githubDebug('Running oci_profile_setup.sh for profile ' + profile);

const result = spawnSync('bash', [setupScript], {
  env: Object.assign({}, process.env, {
    OCI_CONFIG_PAYLOAD: payload,
    OCI_PROFILE_VERIFY: profile,
    OCI_AUTH_MODE: 'none',
  }),
  stdio: 'inherit',
});

if (result.error) {
  githubError('Failed to spawn oci_profile_setup.sh: ' + result.error.message);
  process.exit(1);
}

if (result.status !== 0) {
  githubError('OCI profile setup failed (exit ' + result.status + ')');
  process.exit(result.status || 1);
}

githubNotice("OCI profile '" + profile + "' configured by sli-event-js pre hook");
