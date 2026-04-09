#!/usr/bin/env bash
# tests/unit/test_json_router_batch.sh
# Bulk routing tests for tools/json_router.js

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ROUTER="${REPO_ROOT}/tools/json_router.js"
FX="${REPO_ROOT}/tests/fixtures/router_batch"

PASS=0
FAIL=0

ok()   { echo "[PASS] $1"; PASS=$((PASS+1)); }
fail() { echo "[FAIL] $1"; FAIL=$((FAIL+1)); }

assert_bulk_fixture() {
    local label="$1" case_dir="${FX}/$2"
    local actual_dir
    actual_dir="$(mktemp -d /tmp/router_batch_actual.XXXXXX)"
    if node -e "
const { loadRoutingDefinition, routeDirectory } = require('${ROUTER}');
const definition = loadRoutingDefinition('${case_dir}/routing.json');
routeDirectory('${case_dir}/source', definition, '${actual_dir}')
  .then(() => process.exit(0))
  .catch((e) => { process.stderr.write(String(e.message) + '\n'); process.exit(1); });
"; then
        if diff -ru "${case_dir}/expected_destinations" "${actual_dir}" >/dev/null; then
            ok "$label"
        else
            fail "$label"
            diff -ru "${case_dir}/expected_destinations" "${actual_dir}" || true
        fi
    else
        fail "$label"
    fi
    rm -rf "$actual_dir"
}

assert_bulk_error_contains() {
    local label="$1" case_dir="${FX}/$2"
    local expected
    expected=$(tr -d '\n' < "${case_dir}/expected_error.txt")
    local actual_dir
    actual_dir="$(mktemp -d /tmp/router_batch_actual.XXXXXX)"
    if node -e "
const { loadRoutingDefinition, routeDirectory } = require('${ROUTER}');
Promise.resolve()
  .then(() => {
    const definition = loadRoutingDefinition('${case_dir}/routing.json');
    return routeDirectory('${case_dir}/source', definition, '${actual_dir}');
  })
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
    rm -rf "$actual_dir"
}

assert_bulk_fixture        "UT-65 bulk happy-path routing covers header/endpoint/schema/required/priority" ut65_bulk_routing_success
assert_bulk_error_contains "UT-66 bulk routing reports unroutable file with filename"                        ut66_bulk_routing_no_match
assert_bulk_fixture        "UT-67 bulk dead-letter routing covers unknown/transform/invalid-json cases"     ut67_bulk_routing_dead_letter
assert_bulk_fixture        "UT-77 one omnibus batch covers happy paths and dead letters together"            ut77_bulk_all_in_one
assert_bulk_fixture        "UT-81 bulk fanout writes the same source file to multiple destinations"         ut81_bulk_fanout_delivery
assert_bulk_fixture        "UT-82 bulk exclusive selects one winning destination"                           ut82_bulk_exclusive_delivery
assert_bulk_fixture        "UT-83 bulk mixed exclusive and fanout writes selected destinations"             ut83_bulk_mixed_delivery
assert_bulk_error_contains "UT-72 bulk ambiguous top-priority routes fail with filename"                    ut72_bulk_ambiguous_match
assert_bulk_error_contains "UT-74 invalid routing definition fails before processing"                       ut74_bulk_invalid_routing_definition
assert_bulk_error_contains "UT-84 invalid dead-letter schema fails before processing"                       ut84_bulk_invalid_dead_letter_definition

echo ""
echo "=== json_router bulk: $((PASS+FAIL)) tests, $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
