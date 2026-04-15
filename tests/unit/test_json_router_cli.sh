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

single_tmp_dir=$(mktemp -d /tmp/sli48_router_cli_single.XXXXXX)
cat > "${single_tmp_dir}/routing.json" <<'EOF'
{
  "adapters": {
    "file_system:audit_copy": { "directory": "out/audit" }
  },
  "routes": [
    {
      "id": "audit_to_file",
      "mode": "exclusive",
      "match": { "required_fields": ["audit.id"] },
      "transform": { "mapping": "./mapping.jsonata" },
      "destination": { "type": "file_system", "name": "audit_copy" }
    }
  ]
}
EOF
printf '$\n' > "${single_tmp_dir}/mapping.jsonata"
cat > "${single_tmp_dir}/envelope.json" <<'EOF'
{
  "source_meta": { "file_name": "audit.json" },
  "body": {
    "audit": {
      "id": "A-1",
      "message": "copied to file adapter"
    }
  }
}
EOF

EXPECTED_SINGLE='{"status":"routed","deliveries":[{"route":{"id":"audit_to_file","mode":"exclusive","destination":{"type":"file_system","name":"audit_copy"}},"output":{"audit":{"id":"A-1","message":"copied to file adapter"}}}]}'
result=$(node "$CLI" --routing "${single_tmp_dir}/routing.json" --input "${single_tmp_dir}/envelope.json")
assert_eq "UT-88 router CLI single envelope executes delivery path" "$EXPECTED_SINGLE" "$result"
EXPECTED_FILE='{
  "audit": {
    "id": "A-1",
    "message": "copied to file adapter"
  }
}'
if [[ -f "${single_tmp_dir}/out/audit/audit.json" ]]; then
    actual_file=$(cat "${single_tmp_dir}/out/audit/audit.json")
    assert_eq "UT-88 router CLI single envelope writes destination file" "$EXPECTED_FILE" "$actual_file"
else
    fail "UT-88 router CLI single envelope writes destination file (missing output file)"
fi

result=$(cat "${single_tmp_dir}/envelope.json" | node "$CLI" --routing "${single_tmp_dir}/routing.json")
assert_eq "UT-89 router CLI stdin envelope executes delivery path" "$EXPECTED_SINGLE" "$result"
if [[ -f "${single_tmp_dir}/out/audit/audit.json" ]]; then
    actual_file=$(cat "${single_tmp_dir}/out/audit/audit.json")
    assert_eq "UT-89 router CLI stdin writes destination file" "$EXPECTED_FILE" "$actual_file"
else
    fail "UT-89 router CLI stdin writes destination file (missing output file)"
fi
rm -rf "${single_tmp_dir}"

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
