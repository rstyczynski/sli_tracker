#!/usr/bin/env bash
# tests/unit/test_json_transformer.sh
# Unit tests for tools/json_transformer.js
# Sprint 18 / SLI-26

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TRANSFORMER="${REPO_ROOT}/tools/json_transformer.js"
FIXTURES="${REPO_ROOT}/tests/fixtures"

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

# Run a transform via Node inline script
# Usage: run_transform <source_json> <expression>
run_transform() {
    local src="$1" expr="$2"
    node -e "
const { transform, loadMappingFromObject } = require('${TRANSFORMER}');
const src = ${src};
const mapping = { version: '1', expression: \`${expr}\` };
transform(src, mapping).then(r => {
    process.stdout.write(JSON.stringify(r));
}).catch(e => {
    process.stderr.write(e.message + '\n');
    process.exit(1);
});
"
}

# Run transform expecting failure
run_transform_expect_fail() {
    local src="$1" expr="$2"
    node -e "
const { transform, loadMappingFromObject } = require('${TRANSFORMER}');
const src = ${src};
const mapping = { version: '1', expression: \`${expr}\` };
transform(src, mapping).then(r => {
    process.stderr.write('Expected failure but succeeded\n');
    process.exit(1);
}).catch(e => {
    process.stdout.write(e.message);
    process.exit(0);
});
" 2>/dev/null
}

# UT-1: identity mapping
result=$(run_transform '{"a":1,"b":"x"}' '$$')
assert_eq "UT-1 identity mapping" '{"a":1,"b":"x"}' "$result"

# UT-2: field extraction and rename
result=$(run_transform '{"firstName":"John","lastName":"Doe"}' '{"name": firstName & " " & lastName}')
assert_eq "UT-2 field extraction and rename" '{"name":"John Doe"}' "$result"

# UT-3: nested field access
result=$(run_transform '{"user":{"id":42,"role":"admin"}}' '{"userId": user.id, "role": user.role}')
assert_eq "UT-3 nested field access" '{"userId":42,"role":"admin"}' "$result"

# UT-4: array transformation
result=$(run_transform '{"items":[{"v":1},{"v":2},{"v":3}]}' '{"values": items.v}')
assert_eq "UT-4 array transformation" '{"values":[1,2,3]}' "$result"

# UT-5: conditional expression
result=$(run_transform '{"status":"success"}' '{"ok": status = "success" ? true : false}')
assert_eq "UT-5 conditional expression" '{"ok":true}' "$result"

# UT-6: string concatenation
result=$(run_transform '{"host":"api.example.com","path":"/health"}' '{"url": "https://" & host & path}')
assert_eq "UT-6 string concatenation" '{"url":"https://api.example.com/health"}' "$result"

# UT-7: numeric computation
result=$(run_transform '{"success":80,"total":100}' '{"ratio": $round(success / total, 2)}')
assert_eq "UT-7 numeric computation" '{"ratio":0.8}' "$result"

# UT-8: github workflow_run → oci log shape
GH_SRC='{"action":"completed","workflow_run":{"id":123456,"name":"CI","conclusion":"success","html_url":"https://github.com/org/repo/actions/runs/123456","head_branch":"main","head_sha":"abc123"},"repository":{"full_name":"org/repo"}}'
result=$(run_transform "$GH_SRC" '{"logEntryBatches": [{"defaultlogentrytime": $now(), "entries": [{"data": {"outcome": workflow_run.conclusion, "workflow": workflow_run.name, "run_id": $string(workflow_run.id), "branch": workflow_run.head_branch, "repo": repository.full_name, "url": workflow_run.html_url}}]}]}')
# Check that key fields are present
if echo "$result" | node -e "const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); process.exit(d.logEntryBatches && d.logEntryBatches[0].entries[0].data.outcome==='success' ? 0 : 1)"; then
    ok "UT-8 github workflow_run to oci log shape"
else
    fail "UT-8 github workflow_run to oci log shape"
fi

# UT-9: health endpoint → oci metric shape
HEALTH_SRC='{"status":"UP","components":{"db":{"status":"UP"},"disk":{"status":"UP","details":{"free":1234567,"threshold":10485760}}}}'
result=$(run_transform "$HEALTH_SRC" '{"metricData": [{"namespace": "sli_tracker", "name": "health_status", "datapoints": [{"timestamp": $now(), "value": status = "UP" ? 1 : 0}], "dimensions": {"component": "app"}}]}')
if echo "$result" | node -e "const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); process.exit(d.metricData && d.metricData[0].datapoints[0].value===1 ? 0 : 1)"; then
    ok "UT-9 health endpoint to oci metric shape"
else
    fail "UT-9 health endpoint to oci metric shape"
fi

# UT-10: missing field in source → undefined omitted from output
result=$(run_transform '{"a":1}' '{"a": a, "b": b}')
# JSONata omits undefined fields from object output
if echo "$result" | node -e "const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); process.exit((d.a===1 && !('b' in d)) ? 0 : 1)"; then
    ok "UT-10 missing field omitted"
else
    fail "UT-10 missing field omitted"
fi

# UT-11: null field value passed through
result=$(run_transform '{"a":null}' '{"a": a}')
assert_eq "UT-11 null field value" '{"a":null}' "$result"

# UT-12: wrong type — JSONata coercion (number used in string context)
result=$(run_transform '{"code":404}' '{"message": "Error " & $string(code)}')
assert_eq "UT-12 type coercion" '{"message":"Error 404"}' "$result"

# UT-13: empty source object
result=$(run_transform '{}' '{"status": status, "default": $exists(status) ? status : "unknown"}')
if echo "$result" | node -e "const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); process.exit(d.default==='unknown' ? 0 : 1)"; then
    ok "UT-13 empty source object"
else
    fail "UT-13 empty source object"
fi

# UT-14: source is array at root
result=$(run_transform '[{"v":10},{"v":20}]' '$sum($.v)')
assert_eq "UT-14 source array at root" '30' "$result"

# UT-15: expression field missing → error
node -e "
const { loadMappingFromObject } = require('${TRANSFORMER}');
try { loadMappingFromObject({version:'1'}); process.exit(1); }
catch(e) { process.exit(0); }
" && ok "UT-15 missing expression field" || fail "UT-15 missing expression field"

# UT-16: expression is not a string → error
node -e "
const { loadMappingFromObject } = require('${TRANSFORMER}');
try { loadMappingFromObject({version:'1', expression: 42}); process.exit(1); }
catch(e) { process.exit(0); }
" && ok "UT-16 expression not a string" || fail "UT-16 expression not a string"

# UT-17: invalid JSONata syntax → error
node -e "
const { transform, loadMappingFromObject } = require('${TRANSFORMER}');
const mapping = { version: '1', expression: '{ broken :::' };
transform({}, mapping).then(() => process.exit(1)).catch(() => process.exit(0));
" && ok "UT-17 invalid JSONata syntax" || fail "UT-17 invalid JSONata syntax"

# UT-18: mapping file not valid JSON → error
TMPFILE=$(mktemp)
echo "not json {{{" > "$TMPFILE"
node -e "
const { loadMapping } = require('${TRANSFORMER}');
try { loadMapping('${TMPFILE}'); process.exit(1); }
catch(e) { process.exit(0); }
" && ok "UT-18 mapping file not valid JSON" || fail "UT-18 mapping file not valid JSON"
rm -f "$TMPFILE"

# UT-19: mapping file does not exist → error
node -e "
const { loadMapping } = require('${TRANSFORMER}');
try { loadMapping('/tmp/__no_such_file_sli26__.json'); process.exit(1); }
catch(e) { process.exit(0); }
" && ok "UT-19 mapping file does not exist" || fail "UT-19 mapping file does not exist"

echo ""
echo "=== json_transformer.js summary: $((PASS+FAIL)) tests, $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
