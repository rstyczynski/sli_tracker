#!/usr/bin/env bash
# tests/unit/test_json_transformer_cli.sh
# Unit tests for tools/json_transform_cli.js
# Sprint 18 / SLI-26

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CLI="${REPO_ROOT}/tools/json_transform_cli.js"
FX="${REPO_ROOT}/tests/fixtures/transformer"

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

MAPPING="${FX}/cli_basic/mapping.jsonata"
SOURCE="${FX}/cli_basic/source.json"
EXPECTED=$(node -e "process.stdout.write(JSON.stringify(JSON.parse(require('fs').readFileSync('${FX}/cli_basic/expected.json','utf8'))))")

# UT-20: --input file produces correct output
result=$(node "$CLI" --mapping "$MAPPING" --input "$SOURCE")
assert_eq "UT-20 --input file" "$EXPECTED" "$result"

# UT-21: reads from stdin
result=$(cat "$SOURCE" | node "$CLI" --mapping "$MAPPING")
assert_eq "UT-21 stdin" "$EXPECTED" "$result"

# UT-22: --pretty produces indented (multi-line) output
result=$(node "$CLI" --mapping "$MAPPING" --input "$SOURCE" --pretty)
lines=$(echo "$result" | wc -l | tr -d ' ')
if [[ "$lines" -gt 1 ]]; then ok "UT-22 --pretty indented"
else fail "UT-22 --pretty indented (output was single line)"; fi

# UT-23: unknown flag → exit 1
assert_exit "UT-23 unknown flag"             1  node "$CLI" --mapping "$MAPPING" --unknown-flag

# UT-24: missing --mapping → exit 1
assert_exit "UT-24 missing --mapping"        1  node "$CLI" --input "$SOURCE"

# UT-25: non-existent mapping file → exit 1
assert_exit "UT-25 non-existent mapping"     1  node "$CLI" --mapping /tmp/__no_such_mapping__.jsonata --input "$SOURCE"

# UT-26: non-existent input file → exit 1
assert_exit "UT-26 non-existent input"       1  node "$CLI" --mapping "$MAPPING" --input /tmp/__no_such_input__.json

# UT-27: malformed source JSON → exit 1
assert_exit "UT-27 malformed source JSON"    1  node "$CLI" --mapping "$MAPPING" --input "${FX}/cli_bad_source/source_bad.json"

echo ""
echo "=== json_transform_cli.js: $((PASS+FAIL)) tests, $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
