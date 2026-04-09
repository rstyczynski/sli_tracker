#!/usr/bin/env bash
# tests/unit/test_json_router_adapters.sh
# Unit tests for handler-based adapter API in tools/json_router.js

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ROUTER="${REPO_ROOT}/tools/json_router.js"
ROUTER_FX="${REPO_ROOT}/tests/fixtures/router"
BATCH_FX="${REPO_ROOT}/tests/fixtures/router_batch"

PASS=0
FAIL=0

ok()   { echo "[PASS] $1"; PASS=$((PASS+1)); }
fail() { echo "[FAIL] $1"; FAIL=$((FAIL+1)); }

assert_eq() {
    local label="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then ok "$label"; else
        fail "$label"
        echo "       expected: $expected"
        echo "       actual:   $actual"
    fi
}

result=$(node - <<NODE
const fs = require('fs');
const { loadRoutingDefinition, processEnvelope } = require('${ROUTER}');
const definition = loadRoutingDefinition('${ROUTER_FX}/ut78_fanout_match/routing.json');
const envelope = JSON.parse(fs.readFileSync('${ROUTER_FX}/ut78_fanout_match/envelope.json', 'utf8'));
(async () => {
  const routes = [];
  const result = await processEnvelope(envelope, definition, {
    onRoute: async ({ route }) => { routes.push(route.id); }
  });
  process.stdout.write(JSON.stringify({ status: result.status, routes }));
})().catch((err) => { process.stderr.write(String(err.message) + '\\n'); process.exit(1); });
NODE
)
assert_eq "UT-97 processEnvelope fanout onRoute callbacks" '{"status":"routed","routes":["workflow_log","workflow_metric"]}' "$result"

result=$(node - <<NODE
const fs = require('fs');
const { loadRoutingDefinition, processEnvelope } = require('${ROUTER}');
const definition = loadRoutingDefinition('${ROUTER_FX}/ut79_exclusive_plus_fanout/routing.json');
const envelope = JSON.parse(fs.readFileSync('${ROUTER_FX}/ut79_exclusive_plus_fanout/envelope.json', 'utf8'));
(async () => {
  const routes = [];
  const result = await processEnvelope(envelope, definition, {
    onRoute: async ({ route }) => { routes.push(route.id); }
  });
  process.stdout.write(JSON.stringify({ status: result.status, routes }));
})().catch((err) => { process.stderr.write(String(err.message) + '\\n'); process.exit(1); });
NODE
)
assert_eq "UT-98 processEnvelope mixed exclusive and fanout callbacks" '{"status":"routed","routes":["specific_workflow","workflow_metric"]}' "$result"

result=$(node - <<NODE
const fs = require('fs');
const { loadRoutingDefinition, processEnvelope } = require('${ROUTER}');
const definition = loadRoutingDefinition('${ROUTER_FX}/ut62_no_match/routing.json');
const envelope = JSON.parse(fs.readFileSync('${ROUTER_FX}/ut62_no_match/envelope.json', 'utf8'));
(async () => {
  const dead = [];
  const result = await processEnvelope(envelope, definition, {
    onDeadLetter: async ({ error }) => { dead.push(error); }
  });
  process.stdout.write(JSON.stringify({ status: result.status, dead_letter_calls: dead.length, error: result.error }));
})().catch((err) => { process.stderr.write(String(err.message) + '\\n'); process.exit(1); });
NODE
)
assert_eq "UT-99 processEnvelope no-match goes to onDeadLetter" '{"status":"dead_letter","dead_letter_calls":1,"error":"No route matched envelope"}' "$result"

result=$(node - <<NODE
const fs = require('fs');
const { loadRoutingDefinition, processEnvelope } = require('${ROUTER}');
const definition = loadRoutingDefinition('${ROUTER_FX}/ut64_transform_error/routing.json');
const envelope = JSON.parse(fs.readFileSync('${ROUTER_FX}/ut64_transform_error/envelope.json', 'utf8'));
(async () => {
  const dead = [];
  const result = await processEnvelope(envelope, definition, {
    onDeadLetter: async ({ error }) => { dead.push(error); }
  });
  process.stdout.write(JSON.stringify({ status: result.status, dead_letter_calls: dead.length, has_missing: result.error.includes('missing: workflow_run.conclusion') }));
})().catch((err) => { process.stderr.write(String(err.message) + '\\n'); process.exit(1); });
NODE
)
assert_eq "UT-100 processEnvelope transform failure goes to onDeadLetter" '{"status":"dead_letter","dead_letter_calls":1,"has_missing":true}' "$result"

result=$(node - <<NODE
const fs = require('fs');
const { loadRoutingDefinition, processEnvelopes } = require('${ROUTER}');
const definition = loadRoutingDefinition('${BATCH_FX}/ut83_bulk_mixed_delivery/routing.json');
const envelopes = [
  JSON.parse(fs.readFileSync('${BATCH_FX}/ut83_bulk_mixed_delivery/source/001_workflow_run.json', 'utf8')),
  JSON.parse(fs.readFileSync('${BATCH_FX}/ut83_bulk_mixed_delivery/source/002_health.json', 'utf8')),
  JSON.parse(fs.readFileSync('${BATCH_FX}/ut83_bulk_mixed_delivery/source/003_unknown.json', 'utf8'))
];
(async () => {
  const routes = [];
  const dead = [];
  const result = await processEnvelopes(envelopes, definition, {
    onRoute: async ({ route }) => { routes.push(route.id); },
    onDeadLetter: async ({ error }) => { dead.push(error); }
  });
  process.stdout.write(JSON.stringify({
    processed: result.processed,
    routed: result.routed,
    dead_lettered: result.dead_lettered,
    route_calls: routes.length,
    dead_letter_calls: dead.length
  }));
})().catch((err) => { process.stderr.write(String(err.message) + '\\n'); process.exit(1); });
NODE
)
assert_eq "UT-101 processEnvelopes array mixed summary" '{"processed":3,"routed":2,"dead_lettered":1,"route_calls":3,"dead_letter_calls":1}' "$result"

result=$(node - <<NODE
const fs = require('fs');
const { loadRoutingDefinition, processEnvelopes } = require('${ROUTER}');
const definition = loadRoutingDefinition('${BATCH_FX}/ut83_bulk_mixed_delivery/routing.json');
async function* envelopes() {
  yield JSON.parse(fs.readFileSync('${BATCH_FX}/ut83_bulk_mixed_delivery/source/001_workflow_run.json', 'utf8'));
  yield JSON.parse(fs.readFileSync('${BATCH_FX}/ut83_bulk_mixed_delivery/source/002_health.json', 'utf8'));
}
(async () => {
  const routes = [];
  const result = await processEnvelopes(envelopes(), definition, {
    onRoute: async ({ route }) => { routes.push(route.id); }
  });
  process.stdout.write(JSON.stringify({
    processed: result.processed,
    routed: result.routed,
    dead_lettered: result.dead_lettered,
    route_calls: routes.length
  }));
})().catch((err) => { process.stderr.write(String(err.message) + '\\n'); process.exit(1); });
NODE
)
assert_eq "UT-102 processEnvelopes async iterable" '{"processed":2,"routed":2,"dead_lettered":0,"route_calls":3}' "$result"

echo ""
echo "=== json_router adapters: $((PASS+FAIL)) tests, $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
