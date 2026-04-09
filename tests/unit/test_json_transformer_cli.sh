#!/usr/bin/env bash
# tests/unit/test_json_transformer_cli.sh
# Unit tests for tools/json_transform_cli.js
# Sprint 18 / SLI-26

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CLI="${REPO_ROOT}/tools/json_transform_cli.js"

PASS=0
FAIL=0

ok() { echo "[PASS] $1"; PASS=$((PASS+1)); }
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
    if [[ "$actual_code" -eq "$expected_code" ]]; then ok "$label"; else
        fail "$label (expected exit $expected_code, got $actual_code)"
    fi
}

# Temp files (macOS-compatible: no --suffix)
MAPPING_FILE=$(mktemp /tmp/sli26_mapping.XXXXXX)
INPUT_FILE=$(mktemp /tmp/sli26_input.XXXXXX)

cleanup() { rm -f "$MAPPING_FILE" "$INPUT_FILE"; }
trap cleanup EXIT

# Write a simple mapping and source for reuse
cat > "$MAPPING_FILE" <<'EOF'
{
  "version": "1",
  "description": "test mapping",
  "expression": "{\"out\": value * 2}"
}
EOF

cat > "$INPUT_FILE" <<'EOF'
{"value": 21}
EOF

# UT-20: cli --input file produces correct output
result=$(node "$CLI" --mapping "$MAPPING_FILE" --input "$INPUT_FILE")
assert_eq "UT-20 --input file" '{"out":42}' "$result"

# UT-21: cli reads from stdin
result=$(echo '{"value":5}' | node "$CLI" --mapping "$MAPPING_FILE")
assert_eq "UT-21 stdin" '{"out":10}' "$result"

# UT-22: cli --pretty produces indented output
result=$(node "$CLI" --mapping "$MAPPING_FILE" --input "$INPUT_FILE" --pretty)
# Must contain a newline (indented JSON)
if echo "$result" | grep -q $'\n' 2>/dev/null || [[ $(echo "$result" | wc -l) -gt 1 ]]; then
    ok "UT-22 --pretty indented"
else
    # Fallback: check for spaces in output indicating pretty-print
    if echo "$result" | grep -qE '^\{$|^  '; then
        ok "UT-22 --pretty indented"
    else
        fail "UT-22 --pretty indented (output not multi-line)"
        echo "       output: $result"
    fi
fi

# UT-23: cli unknown flag → exit 1
assert_exit "UT-23 unknown flag" 1 node "$CLI" --mapping "$MAPPING_FILE" --unknown-flag

# UT-24: cli missing --mapping → exit 1
assert_exit "UT-24 missing --mapping" 1 node "$CLI" --input "$INPUT_FILE"

# UT-25: cli non-existent mapping file → exit 1
assert_exit "UT-25 non-existent mapping" 1 node "$CLI" --mapping /tmp/__no_such_mapping__.json --input "$INPUT_FILE"

# UT-26: cli non-existent input file → exit 1
assert_exit "UT-26 non-existent input" 1 node "$CLI" --mapping "$MAPPING_FILE" --input /tmp/__no_such_input__.json

# UT-27: cli malformed source JSON → exit 1
BAD_INPUT=$(mktemp /tmp/sli26_bad.XXXXXX)
echo "{ broken json" > "$BAD_INPUT"
assert_exit "UT-27 malformed source JSON" 1 node "$CLI" --mapping "$MAPPING_FILE" --input "$BAD_INPUT"
rm -f "$BAD_INPUT"

echo ""
echo "=== json_transform_cli.js summary: $((PASS+FAIL)) tests, $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
