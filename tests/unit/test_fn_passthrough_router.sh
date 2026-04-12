#!/usr/bin/env bash
# Unit test: router_passthrough core (JSONata $ + stub Object Storage emit).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
FN_DIR="${REPO_ROOT}/fn/router_passthrough"

PASS=0
FAIL=0

ok()   { echo "[PASS] $1"; PASS=$((PASS + 1)); }
fail() { echo "[FAIL] $1"; FAIL=$((FAIL + 1)); }

export OCI_INGEST_BUCKET="ut-fn-router-bucket"

cd "$FN_DIR"
if [[ ! -d node_modules ]]; then
  npm install >/dev/null
fi

if ! OUT=$(node <<NODE
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const { runRouter } = require('./router_core');
const fxDir = path.join(process.cwd(), '..', '..', 'tests', 'fixtures', 'fn_router_passthrough');
const samplesDir = path.join(process.cwd(), '..', '..', 'tests', 'fixtures', 'github_webhook_samples');
const routingDefinition = JSON.parse(fs.readFileSync(path.join(fxDir, 'routing.json'), 'utf8'));
const passthroughBody = fs.readFileSync(path.join(fxDir, 'passthrough.jsonata'), 'utf8').trim();
const loadMappingFromRef = async ({ mappingRef }) =>
  (path.basename(String(mappingRef)) === 'passthrough.jsonata' ? passthroughBody : null);

function readSample(name) {
  return JSON.parse(fs.readFileSync(path.join(samplesDir, name), 'utf8'));
}

(async () => {
  const calls = [];
  const r = await runRouter({ hello: 'world', n: 42 }, {
    putObject: async (x) => { calls.push(x); },
    routingDefinition,
    loadMappingFromRef,
  });
  assert.strictEqual(r.status, 'routed');
  assert.strictEqual(calls.length, 1);
  const body = JSON.parse(calls[0].content);
  assert.strictEqual(body.hello, 'world');
  assert.strictEqual(body.n, 42);
  assert.ok(calls[0].objectName.includes('fn-'));
  assert.ok(calls[0].objectName.startsWith('ingest/'));
  assert.ok(!calls[0].objectName.startsWith('ingest/github/'));

  const calls2 = [];
  await runRouter(
    { body: { x: 1 }, source_meta: { file_name: 'fixed-name.json' } },
    { putObject: async (x) => { calls2.push(x); }, routingDefinition, loadMappingFromRef },
  );
  assert.strictEqual(calls2[0].objectName, 'ingest/fixed-name.json');

  const pingBody = readSample('ping.json');
  const callsPing = [];
  await runRouter(
    {
      body: pingBody,
      headers: { 'X-GitHub-Event': 'ping' },
      source_meta: { file_name: 'unit-ping.json' },
    },
    { putObject: async (x) => { callsPing.push(x); }, routingDefinition, loadMappingFromRef },
  );
  assert.strictEqual(callsPing[0].objectName, 'ingest/github/ping/unit-ping.json');
  assert.strictEqual(JSON.parse(callsPing[0].content).hook_id, 1);

  const pushBody = readSample('push.json');
  const callsPush = [];
  await runRouter(
    { body: pushBody, headers: { 'x-github-event': 'push' }, source_meta: { file_name: 'unit-push.json' } },
    { putObject: async (x) => { callsPush.push(x); }, routingDefinition, loadMappingFromRef },
  );
  assert.strictEqual(callsPush[0].objectName, 'ingest/github/push/unit-push.json');

  const callsPushNoHdr = [];
  await runRouter(
    {
      body: pushBody,
      headers: {},
      source_meta: { file_name: 'unit-push-no-header.json' },
    },
    { putObject: async (x) => { callsPushNoHdr.push(x); }, routingDefinition, loadMappingFromRef },
  );
  assert.strictEqual(
    callsPushNoHdr[0].objectName,
    'ingest/unit-push-no-header.json',
    'without X-GitHub-Event, catch-all ingest/ is correct',
  );

  const deadLetterRouting = {
    adapters: {
      'oci_object_storage:raw_ingest': { bucket: 'REPLACED_AT_RUNTIME', prefix: 'ingest/' },
      'oci_object_storage:dead_letter': { bucket: 'REPLACED_AT_RUNTIME', prefix: 'ingest/dead_letter/' },
      'oci_object_storage:github_push': { bucket: 'REPLACED_AT_RUNTIME', prefix: 'ingest/github/push/' },
    },
    dead_letter: { type: 'oci_object_storage', name: 'dead_letter' },
    routes: [
      {
        id: 'github_push_only',
        mode: 'exclusive',
        priority: 40,
        match: { headers: { 'x-github-event': 'push' } },
        transform: { mapping: './passthrough.jsonata' },
        destination: { type: 'oci_object_storage', name: 'github_push' },
      },
    ],
  };
  const callsDl = [];
  const rdl = await runRouter(
    { body: { no: 'match' }, headers: {}, source_meta: { file_name: 'dl-no-route.json' } },
    { putObject: async (x) => { callsDl.push(x); }, routingDefinition: deadLetterRouting, loadMappingFromRef },
  );
  assert.strictEqual(rdl.status, 'dead_letter');
  assert.ok(typeof rdl.error === 'string' && rdl.error.length > 0);
  assert.strictEqual(callsDl.length, 1);
  assert.strictEqual(callsDl[0].objectName, 'ingest/dead_letter/dl-no-route.json');
  const dlPayload = JSON.parse(callsDl[0].content);
  assert.ok(dlPayload.error);
  assert.ok(dlPayload.envelope);

  const wfBody = readSample('workflow_run.json');
  const callsWf = [];
  await runRouter(
    {
      body: wfBody,
      headers: { 'X-GitHub-Event': 'workflow_run' },
      source_meta: { file_name: 'unit-wf.json' },
    },
    { putObject: async (x) => { callsWf.push(x); }, routingDefinition, loadMappingFromRef },
  );
  assert.strictEqual(callsWf[0].objectName, 'ingest/github/workflow_run/unit-wf.json');

  const mockFdkCtx = {
    get httpGateway() {
      return { headers: { 'X-Github-Event': ['workflow_run'] } };
    },
  };
  const callsWfGw = [];
  await runRouter(
    { body: wfBody, source_meta: { file_name: 'unit-wf-gw.json' } },
    {
      putObject: async (x) => { callsWfGw.push(x); },
      routingDefinition,
      loadMappingFromRef,
      fdkContext: mockFdkCtx,
    },
  );
  assert.strictEqual(
    callsWfGw[0].objectName,
    'ingest/github/workflow_run/unit-wf-gw.json',
    'FDK httpGateway X-Github-Event classifies raw GitHub body',
  );

  const prBody = readSample('pull_request.json');
  const callsPr = [];
  await runRouter(
    {
      body: prBody,
      headers: { 'X-GitHub-Event': 'pull_request' },
      source_meta: { file_name: 'unit-pr.json' },
    },
    { putObject: async (x) => { callsPr.push(x); }, routingDefinition, loadMappingFromRef },
  );
  assert.strictEqual(callsPr[0].objectName, 'ingest/github/pull_request/unit-pr.json');

  console.log('ok');
})();
NODE
); then
  fail "router_core runRouter assertions failed"
  echo "$OUT" >&2
else
  ok "runRouter pass-through, GitHub header prefixes, and source_meta object names"
fi

echo "=== Summary ==="
echo "passed: $PASS  failed: $FAIL"

if [[ "$FAIL" -ne 0 ]]; then exit 1; fi
echo "PASS"
