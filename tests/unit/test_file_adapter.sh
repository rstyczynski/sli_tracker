#!/usr/bin/env bash
# tests/unit/test_file_adapter.sh
# Unit tests for tools/adapters/file_adapter.js

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ROUTER="${REPO_ROOT}/tools/json_router.js"
ADAPTER="${REPO_ROOT}/tools/adapters/file_adapter.js"
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

tmp_dir=$(mktemp -d /tmp/sli20_file_adapter.XXXXXX)
result=$(node - <<NODE
const fs = require('fs');
const { loadRoutingDefinition, processEnvelope } = require('${ROUTER}');
const { createFileAdapter } = require('${ADAPTER}');
const definition = loadRoutingDefinition('${ROUTER_FX}/ut78_fanout_match/routing.json');
const envelope = JSON.parse(fs.readFileSync('${ROUTER_FX}/ut78_fanout_match/envelope.json', 'utf8'));
(async () => {
  const adapter = createFileAdapter({ rootDir: '${tmp_dir}' });
  await processEnvelope(envelope, definition, adapter);
  const state = adapter.getState();
  process.stdout.write(JSON.stringify({
    routeWrites: state.routeWrites.map((x) => x.path.split('/').slice(-3).join('/')),
    deadLetterWrites: state.deadLetterWrites.length
  }));
})().catch((err) => { process.stderr.write(String(err.message) + '\\n'); process.exit(1); });
NODE
)
assert_eq "UT-103 file adapter writes fanout destinations" '{"routeWrites":["oci_log/github_events/001_workflow_log.json","oci_metric/workflow_status/002_workflow_metric.json"],"deadLetterWrites":0}' "$result"
rm -rf "$tmp_dir"

tmp_dir=$(mktemp -d /tmp/sli20_file_adapter.XXXXXX)
result=$(node - <<NODE
const fs = require('fs');
const { loadRoutingDefinition, processEnvelope } = require('${ROUTER}');
const { createFileAdapter } = require('${ADAPTER}');
const definition = loadRoutingDefinition('${ROUTER_FX}/ut62_no_match/routing.json');
const envelope = JSON.parse(fs.readFileSync('${ROUTER_FX}/ut62_no_match/envelope.json', 'utf8'));
(async () => {
  const adapter = createFileAdapter({ rootDir: '${tmp_dir}' });
  await processEnvelope(envelope, definition, adapter);
  const state = adapter.getState();
  process.stdout.write(JSON.stringify({
    routeWrites: state.routeWrites.length,
    deadLetterWrites: state.deadLetterWrites.map((x) => x.path.split('/').slice(-3).join('/'))
  }));
})().catch((err) => { process.stderr.write(String(err.message) + '\\n'); process.exit(1); });
NODE
)
assert_eq "UT-104 file adapter writes dead letter output" '{"routeWrites":0,"deadLetterWrites":["dead_letter/errors/001_dead_letter.json"]}' "$result"
rm -rf "$tmp_dir"

tmp_dir=$(mktemp -d /tmp/sli20_file_adapter.XXXXXX)
result=$(node - <<NODE
const fs = require('fs');
const { loadRoutingDefinition, processEnvelopes } = require('${ROUTER}');
const { createFileAdapter } = require('${ADAPTER}');
const definition = loadRoutingDefinition('${BATCH_FX}/ut83_bulk_mixed_delivery/routing.json');
const envelopes = [
  JSON.parse(fs.readFileSync('${BATCH_FX}/ut83_bulk_mixed_delivery/source/001_workflow_run.json', 'utf8')),
  JSON.parse(fs.readFileSync('${BATCH_FX}/ut83_bulk_mixed_delivery/source/002_health.json', 'utf8')),
  JSON.parse(fs.readFileSync('${BATCH_FX}/ut83_bulk_mixed_delivery/source/003_unknown.json', 'utf8'))
];
(async () => {
  const adapter = createFileAdapter({ rootDir: '${tmp_dir}' });
  const summary = await processEnvelopes(envelopes, definition, adapter);
  const state = adapter.getState();
  process.stdout.write(JSON.stringify({
    processed: summary.processed,
    routed: summary.routed,
    dead_lettered: summary.dead_lettered,
    routeWrites: state.routeWrites.length,
    deadLetterWrites: state.deadLetterWrites.length
  }));
})().catch((err) => { process.stderr.write(String(err.message) + '\\n'); process.exit(1); });
NODE
)
assert_eq "UT-105 file adapter writes mixed batch outputs" '{"processed":3,"routed":2,"dead_lettered":1,"routeWrites":3,"deadLetterWrites":1}' "$result"
rm -rf "$tmp_dir"

echo ""
echo "=== file adapter: $((PASS+FAIL)) tests, $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
