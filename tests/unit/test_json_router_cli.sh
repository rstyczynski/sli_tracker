#!/usr/bin/env bash
# tests/unit/test_json_router_cli.sh
# Unit tests for tools/json_router_cli.js

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CLI="${REPO_ROOT}/tools/json_router_cli.js"
ROUTER_FX="${REPO_ROOT}/tests/fixtures/router"
BATCH_FX="${REPO_ROOT}/tests/fixtures/router_batch"
CLI_FX="${REPO_ROOT}/tests/fixtures/router_cli"

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

assert_exit() {
    local label="$1" expected_code="$2"
    shift 2
    local actual_code=0
    "$@" >/dev/null 2>&1 || actual_code=$?
    if [[ "$actual_code" -eq "$expected_code" ]]; then ok "$label"
    else fail "$label (expected exit $expected_code, got $actual_code)"; fi
}

assert_exit_and_stderr_contains() {
    local label="$1" expected_code="$2" expected_fragment="$3"
    shift 3
    local actual_code=0 stderr_file
    stderr_file=$(mktemp /tmp/sli19_router_cli_stderr.XXXXXX)
    "$@" >/dev/null 2>"$stderr_file" || actual_code=$?
    if [[ "$actual_code" -eq "$expected_code" ]] && grep -q "$expected_fragment" "$stderr_file"; then
        ok "$label"
    else
        fail "$label (expected exit $expected_code and stderr containing '$expected_fragment', got exit $actual_code)"
    fi
    rm -f "$stderr_file"
}

EXPECTED_SINGLE=$(node -e "process.stdout.write(JSON.stringify(JSON.parse(require('fs').readFileSync('${ROUTER_FX}/ut79_exclusive_plus_fanout/expected.json','utf8'))))")
result=$(node "$CLI" --routing "${ROUTER_FX}/ut79_exclusive_plus_fanout/routing.json" --input "${ROUTER_FX}/ut79_exclusive_plus_fanout/envelope.json")
assert_eq "UT-88 router CLI single envelope" "$EXPECTED_SINGLE" "$result"

result=$(cat "${ROUTER_FX}/ut79_exclusive_plus_fanout/envelope.json" | node "$CLI" --routing "${ROUTER_FX}/ut79_exclusive_plus_fanout/routing.json")
assert_eq "UT-89 router CLI stdin envelope" "$EXPECTED_SINGLE" "$result"

batch_actual_dir=$(mktemp -d /tmp/sli19_router_cli_batch.XXXXXX)
EXPECTED_BATCH_SUMMARY=$(node -e "process.stdout.write(JSON.stringify({processed:4}))")
batch_result=$(node "$CLI" --routing "${BATCH_FX}/ut83_bulk_mixed_delivery/routing.json" --source-dir "${BATCH_FX}/ut83_bulk_mixed_delivery/source" --output-dir "$batch_actual_dir")
batch_processed=$(node -e "const x=JSON.parse(process.argv[1]); process.stdout.write(JSON.stringify({processed:x.processed}))" "$batch_result")
assert_eq "UT-90 router CLI batch summary" "$EXPECTED_BATCH_SUMMARY" "$batch_processed"
if diff -ru "${BATCH_FX}/ut83_bulk_mixed_delivery/expected_destinations" "$batch_actual_dir" >/dev/null; then
    ok "UT-90 router CLI batch destinations"
else
    fail "UT-90 router CLI batch destinations"
    diff -ru "${BATCH_FX}/ut83_bulk_mixed_delivery/expected_destinations" "$batch_actual_dir" || true
fi
rm -rf "$batch_actual_dir"

assert_exit "UT-91 router CLI missing --routing" 1 node "$CLI" --input "${ROUTER_FX}/ut57_header_match/envelope.json"
assert_exit "UT-92 router CLI missing batch output-dir" 1 node "$CLI" --routing "${BATCH_FX}/ut81_bulk_fanout_delivery/routing.json" --source-dir "${BATCH_FX}/ut81_bulk_fanout_delivery/source"
BAD_INPUT_ERROR=$(tr -d '\n' < "${CLI_FX}/ut92_bad_envelope_json/expected_error.txt")
assert_exit_and_stderr_contains "UT-93 router CLI malformed envelope JSON" 1 "$BAD_INPUT_ERROR" \
    node "$CLI" --routing "${ROUTER_FX}/ut57_header_match/routing.json" --input "${CLI_FX}/ut92_bad_envelope_json/input_bad.json"

echo ""
echo "=== json_router CLI: $((PASS+FAIL)) tests, $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
