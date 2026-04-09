#!/usr/bin/env bash
# tests/unit/test_json_router_schema.sh
# Unit tests for routing.json schema validation in tools/json_router.js

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ROUTER="${REPO_ROOT}/tools/json_router.js"
FX="${REPO_ROOT}/tests/fixtures/router_schema"

PASS=0
FAIL=0

ok()   { echo "[PASS] $1"; PASS=$((PASS+1)); }
fail() { echo "[FAIL] $1"; FAIL=$((FAIL+1)); }

assert_schema_valid() {
    local label="$1" case_dir="${FX}/$2"
    if node -e "
const { loadRoutingDefinition } = require('${ROUTER}');
loadRoutingDefinition('${case_dir}/routing.json');
"; then
        ok "$label"
    else
        fail "$label"
    fi
}

assert_schema_error_contains() {
    local label="$1" case_dir="${FX}/$2"
    local expected
    expected=$(tr -d '\n' < "${case_dir}/expected_error.txt")
    if node -e "
const { loadRoutingDefinition } = require('${ROUTER}');
Promise.resolve()
  .then(() => loadRoutingDefinition('${case_dir}/routing.json'))
  .then(() => process.exit(1))
  .catch((e) => {
    if (String(e.message).includes(${expected@Q})) process.exit(0);
    process.stderr.write(String(e.message) + '\n');
    process.exit(2);
  });
"; then
        ok "$label"
    else
        fail "$label"
    fi
}

assert_schema_valid          "UT-85 routing.json schema accepts valid definition"                  ut85_valid_routing_definition_schema
assert_schema_error_contains "UT-86 routing.json schema rejects invalid route definition critically" ut86_invalid_routing_definition_schema
assert_schema_error_contains "UT-87 routing.json schema rejects invalid dead-letter definition critically" ut87_invalid_dead_letter_definition_schema

echo ""
echo "=== json_router schema: $((PASS+FAIL)) tests, $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
