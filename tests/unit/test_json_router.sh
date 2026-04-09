#!/usr/bin/env bash
# tests/unit/test_json_router.sh
# Unit tests for tools/json_router.js
# Sprint 19 / SLI-27

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ROUTER="${REPO_ROOT}/tools/json_router.js"
FX="${REPO_ROOT}/tests/fixtures/router"

PASS=0
FAIL=0

ok()   { echo "[PASS] $1"; PASS=$((PASS+1)); }
fail() { echo "[FAIL] $1"; FAIL=$((FAIL+1)); }

run_router_fixture() {
    local case_dir="$1"
    node -e "
const { loadRoutingDefinition, routeTransform } = require('${ROUTER}');
const fs = require('fs');
const envelope = JSON.parse(fs.readFileSync('${case_dir}/envelope.json', 'utf8'));
const definition = loadRoutingDefinition('${case_dir}/routing.json');
routeTransform(envelope, definition)
  .then(r => process.stdout.write(JSON.stringify(r)))
  .catch(e => { process.stderr.write(String(e.message) + '\n'); process.exit(1); });
"
}

assert_router_fixture() {
    local label="$1" case_dir="${FX}/$2"
    local actual expected
    actual=$(run_router_fixture "${case_dir}")
    expected=$(node -e "const fs=require('fs'); process.stdout.write(JSON.stringify(JSON.parse(fs.readFileSync('${case_dir}/expected.json','utf8'))))")
    if [[ "$actual" == "$expected" ]]; then ok "$label"; else
        fail "$label"
        echo "       expected: $expected"
        echo "       actual:   $actual"
    fi
}

assert_router_error_contains() {
    local label="$1" case_dir="${FX}/$2"
    local expected
    expected=$(tr -d '\n' < "${case_dir}/expected_error.txt")
    if node -e "
const { loadRoutingDefinition, routeTransform } = require('${ROUTER}');
const fs = require('fs');
const envelope = JSON.parse(fs.readFileSync('${case_dir}/envelope.json', 'utf8'));
const definition = loadRoutingDefinition('${case_dir}/routing.json');
routeTransform(envelope, definition)
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

assert_router_fixture        "UT-57 header-based route selection"             ut57_header_match
assert_router_fixture        "UT-58 endpoint-based route selection"           ut58_endpoint_match
assert_router_fixture        "UT-59 schema-based route selection"             ut59_schema_match
assert_router_fixture        "UT-60 required-fields route selection"          ut60_required_fields_match
assert_router_fixture        "UT-61 highest-priority route wins"              ut61_priority_match
assert_router_error_contains "UT-62 no route matched → error"                 ut62_no_match
assert_router_error_contains "UT-63 ambiguous top-priority routes → error"    ut63_ambiguous_match
assert_router_error_contains "UT-64 route matched but strict mapping fails"   ut64_transform_error

echo ""
echo "=== json_router.js: $((PASS+FAIL)) tests, $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
