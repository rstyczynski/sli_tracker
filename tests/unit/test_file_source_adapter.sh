#!/usr/bin/env bash
# tests/unit/test_file_source_adapter.sh
# Unit tests for tools/adapters/file_source_adapter.js

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ROUTER="${REPO_ROOT}/tools/json_router.js"
SOURCE_ADAPTER="${REPO_ROOT}/tools/adapters/file_source_adapter.js"
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
const { createFileSourceAdapter } = require('${SOURCE_ADAPTER}');
(async () => {
  const adapter = createFileSourceAdapter({ sourceDir: '${BATCH_FX}/ut83_bulk_mixed_delivery/source' });
  const items = [];
  for await (const envelope of adapter.readEnvelopes()) {
    items.push({
      endpoint: envelope.endpoint || null,
      file_name: envelope.source_meta && envelope.source_meta.file_name
    });
  }
  const state = adapter.getState();
  process.stdout.write(JSON.stringify({
    items,
    files: state.filesRead.map((value) => value.split('/').slice(-1)[0])
  }));
})().catch((err) => { process.stderr.write(String(err.message) + '\\n'); process.exit(1); });
NODE
)
assert_eq "UT-106 file source adapter reads JSON files in lexical order" '{"items":[{"endpoint":null,"file_name":"001_workflow_run.json"},{"endpoint":"/health","file_name":"002_health.json"},{"endpoint":null,"file_name":"003_unknown.json"}],"files":["001_workflow_run.json","002_health.json","003_unknown.json"]}' "$result"

result=$(node - <<NODE
const { loadRoutingDefinition, processEnvelopes } = require('${ROUTER}');
const { createFileSourceAdapter } = require('${SOURCE_ADAPTER}');
const definition = loadRoutingDefinition('${BATCH_FX}/ut83_bulk_mixed_delivery/routing.json');
(async () => {
  const adapter = createFileSourceAdapter({ sourceDir: '${BATCH_FX}/ut83_bulk_mixed_delivery/source' });
  const routes = [];
  const dead = [];
  const result = await processEnvelopes(adapter.readEnvelopes(), definition, {
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
assert_eq "UT-107 file source adapter feeds processEnvelopes mixed batch" '{"processed":3,"routed":2,"dead_lettered":1,"route_calls":3,"dead_letter_calls":1}' "$result"

result=$(node - <<NODE
const { createFileSourceAdapter } = require('${SOURCE_ADAPTER}');
(async () => {
  const adapter = createFileSourceAdapter({ sourceDir: '${BATCH_FX}/ut77_bulk_all_in_one/source' });
  try {
    for await (const _envelope of adapter.readEnvelopes()) {
      // consume until malformed JSON is hit
    }
    process.stdout.write('unexpected-success');
  } catch (err) {
    const state = adapter.getState();
    process.stdout.write(JSON.stringify({
      files_read: state.filesRead.length,
      has_bad_file: String(err.message).includes('008_bad.json'),
      has_json_error: String(err.message).includes('not valid JSON')
    }));
  }
})().catch((err) => { process.stderr.write(String(err.message) + '\\n'); process.exit(1); });
NODE
)
assert_eq "UT-108 file source adapter stops on malformed JSON file" '{"files_read":7,"has_bad_file":true,"has_json_error":true}' "$result"

echo ""
echo "=== file source adapter: $((PASS+FAIL)) tests, $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
