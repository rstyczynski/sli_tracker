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

run_router_fixture_all() {
    local case_dir="$1"
    node -e "
const { loadRoutingDefinition, routeTransformAll } = require('${ROUTER}');
const fs = require('fs');
const envelope = JSON.parse(fs.readFileSync('${case_dir}/envelope.json', 'utf8'));
const definition = loadRoutingDefinition('${case_dir}/routing.json');
routeTransformAll(envelope, definition)
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

assert_router_multi_fixture() {
    local label="$1" case_dir="${FX}/$2"
    local actual expected
    actual=$(run_router_fixture_all "${case_dir}")
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
Promise.resolve()
  .then(() => {
    const definition = loadRoutingDefinition('${case_dir}/routing.json');
    return routeTransform(envelope, definition);
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
}

assert_router_fixture        "UT-57 header-based route selection"             ut57_header_match
assert_router_fixture        "UT-58 endpoint-based route selection"           ut58_endpoint_match
assert_router_fixture        "UT-59 schema-based route selection"             ut59_schema_match
assert_router_fixture        "UT-60 required-fields route selection"          ut60_required_fields_match
assert_router_fixture        "UT-61 highest-priority route wins"              ut61_priority_match
assert_router_error_contains "UT-62 no route matched → error"                 ut62_no_match
assert_router_error_contains "UT-63 ambiguous top-priority routes → error"    ut63_ambiguous_match
assert_router_error_contains "UT-64 route matched but strict mapping fails"   ut64_transform_error
assert_router_error_contains "UT-75 invalid schema matcher rejected at definition load" ut75_invalid_schema_match_definition
assert_router_error_contains "UT-76 non-object body does not crash and reports no route" ut76_non_object_body_no_match
assert_router_multi_fixture "UT-78 fanout routes produce multiple outputs"    ut78_fanout_match
assert_router_multi_fixture "UT-79 exclusive winner and fanout route both selected" ut79_exclusive_plus_fanout
assert_router_error_contains "UT-80 invalid route mode rejected at definition load" ut80_invalid_mode_definition
assert_router_fixture        "UT-111 header value comparison is case-insensitive (generic header, BUG-1)" ut111_header_value_case_insensitive

result=$(node - <<NODE
const fs = require('fs');
const path = require('path');
const { routeTransform } = require('${ROUTER}');
const envelope = JSON.parse(fs.readFileSync('${FX}/ut57_header_match/envelope.json', 'utf8'));
const router = JSON.parse(fs.readFileSync('${FX}/ut57_header_match/routing.json', 'utf8'));
router.routes[0].transform.mapping = path.resolve('${FX}/ut57_header_match', router.routes[0].transform.mapping);
routeTransform(envelope, router)
  .then(r => process.stdout.write(JSON.stringify(r)))
  .catch(e => { process.stderr.write(String(e.message) + '\\n'); process.exit(1); });
NODE
)
expected=$(node -e "const fs=require('fs'); process.stdout.write(JSON.stringify(JSON.parse(fs.readFileSync('${FX}/ut57_header_match/expected.json','utf8'))))")
if [[ "$result" == "$expected" ]]; then ok "UT-109 router accepts routing object variable"; else
    fail "UT-109 router accepts routing object variable"
    echo "       expected: $expected"
    echo "       actual:   $result"
fi

result=$(node - <<NODE
const fs = require('fs');
const { loadRoutingDefinition, routeTransform } = require('${ROUTER}');
const envelope = JSON.parse(fs.readFileSync('${FX}/ut57_header_match/envelope.json', 'utf8'));
const router = loadRoutingDefinition('${FX}/ut57_header_match/routing.json');
routeTransform(envelope, router)
  .then(r => process.stdout.write(JSON.stringify(r)))
  .catch(e => { process.stderr.write(String(e.message) + '\\n'); process.exit(1); });
NODE
)
if [[ "$result" == "$expected" ]]; then ok "UT-110 router accepts preloaded routing variable"; else
    fail "UT-110 router accepts preloaded routing variable"
    echo "       expected: $expected"
    echo "       actual:   $result"
fi

echo ""
echo "=== json_router.js: $((PASS+FAIL)) tests, $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
