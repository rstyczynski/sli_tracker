#!/usr/bin/env bash
# tests/unit/test_json_router_mapping_source.sh
# Unit test: when definition.mapping is present, mapping can be loaded via handler.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ROUTER="${REPO_ROOT}/tools/json_router.js"
FX="${REPO_ROOT}/tests/fixtures/router_destinations/ut111_mixed_destinations"

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

(async () => {
  const definition = loadRoutingDefinition('${FX}/routing.json');
  const envelope = JSON.parse(fs.readFileSync('${FX}/source/001_workflow_run.json', 'utf8'));

  let seenKey = null;
  let outputValue = null;

  await processEnvelope(envelope, definition, {
    loadMapping: async ({ mappingKey }) => {
      seenKey = mappingKey;
      // Return the workflow conclusion only; proves handler result is used.
      return '$.workflow_run.conclusion';
    },
    onRoute: async ({ output }) => {
      outputValue = output;
    }
  });

  process.stdout.write(JSON.stringify({ seenKey, outputValue }));
})().catch((err) => { process.stderr.write(String(err.message) + '\\n'); process.exit(1); });
NODE
)

assert_eq "UT-119 mapping source uses handler-provided mapping when definition.mapping is present" \
  '{"seenKey":"./mapping_log.jsonata","outputValue":"success"}' "$result"

echo ""
echo "=== json_router mapping source: $((PASS+FAIL)) tests, $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]

