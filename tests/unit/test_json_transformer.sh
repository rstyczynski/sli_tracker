#!/usr/bin/env bash
# tests/unit/test_json_transformer.sh
# Unit tests for tools/json_transformer.js
# Sprint 18 / SLI-26
#
# Fixture layout: tests/fixtures/transformer/<case>/
#   source.json          — input document
#   mapping.jsonata      — pure JSONata expression (happy-path + bad-source cases)
#   mapping.json         — JSON envelope (used only for error-case fixtures)
#   expected.json        — exact expected output
#   expected_subset.json — required subset for cases with dynamic fields (e.g. $now())

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TRANSFORMER="${REPO_ROOT}/tools/json_transformer.js"
FX="${REPO_ROOT}/tests/fixtures/transformer"

PASS=0
FAIL=0

ok()   { echo "[PASS] $1"; PASS=$((PASS+1)); }
fail() { echo "[FAIL] $1"; FAIL=$((FAIL+1)); }

# ── helpers ───────────────────────────────────────────────────────────────────

# Run transform: load source.json + mapping file, emit compact JSON to stdout
run_fixture() {
    local src_file="$1" map_file="$2"
    node -e "
const { loadMapping, transform } = require('${TRANSFORMER}');
const fs = require('fs');
const src = JSON.parse(fs.readFileSync('${src_file}', 'utf8'));
const mapping = loadMapping('${map_file}');
transform(src, mapping)
  .then(r => process.stdout.write(JSON.stringify(r)))
  .catch(e => { process.stderr.write(e.message + '\n'); process.exit(1); });
"
}

# Exact comparison — both sides normalised through JSON parse+stringify
assert_fixture() {
    local label="$1" case_dir="${FX}/$2"
    local actual expected
    actual=$(run_fixture "${case_dir}/source.json" "${case_dir}/mapping.jsonata")
    expected=$(node -e "const fs=require('fs'); process.stdout.write(JSON.stringify(JSON.parse(fs.readFileSync('${case_dir}/expected.json','utf8'))))")
    if [[ "$expected" == "$actual" ]]; then
        ok "$label"
    else
        fail "$label"
        echo "       expected: $expected"
        echo "       actual:   $actual"
    fi
}

# Subset comparison — every leaf in expected_subset.json must match (dynamic fields like $now() excluded)
assert_fixture_subset() {
    local label="$1" case_dir="${FX}/$2"
    local actual
    actual=$(run_fixture "${case_dir}/source.json" "${case_dir}/mapping.jsonata")
    node -e "
const fs = require('fs');
const actual = JSON.parse('$(echo "$actual" | sed "s/'/\\\\'/g")');
const subset = JSON.parse(fs.readFileSync('${case_dir}/expected_subset.json', 'utf8'));
function check(a, e, path) {
    if (typeof e !== 'object' || e === null) {
        if (JSON.stringify(a) !== JSON.stringify(e))
            throw new Error('at ' + path + ': expected ' + JSON.stringify(e) + ', got ' + JSON.stringify(a));
        return;
    }
    if (Array.isArray(e)) {
        e.forEach((ev, i) => check(a && a[i], ev, path + '[' + i + ']'));
        return;
    }
    for (const k of Object.keys(e)) check(a && a[k], e[k], path + '.' + k);
}
try { check(actual, subset, 'root'); process.exit(0); }
catch(e) { process.stderr.write(e.message + '\n'); process.exit(1); }
" && ok "$label" || { fail "$label"; }
}

# ── happy-path tests ──────────────────────────────────────────────────────────

assert_fixture        "UT-1  identity mapping"                ut01_identity
assert_fixture        "UT-2  field extraction and rename"     ut02_field_rename
assert_fixture        "UT-3  nested field access"             ut03_nested_access
assert_fixture        "UT-4  array transformation"            ut04_array_transform
assert_fixture        "UT-5  conditional expression"          ut05_conditional
assert_fixture        "UT-6  string concatenation"            ut06_string_concat
assert_fixture        "UT-7  numeric computation"             ut07_numeric_compute
assert_fixture_subset "UT-8  github workflow_run → oci log"   ut08_github_workflow_run
assert_fixture_subset "UT-9  health endpoint → oci metric"    ut09_health_to_metric

# ── corner cases: bad / unusual source data ───────────────────────────────────

assert_fixture "UT-10 missing field in source omitted"        ut10_missing_field
assert_fixture "UT-11 null field value passes through"        ut11_null_field
assert_fixture "UT-12 number-to-string coercion"              ut12_type_coercion
assert_fixture "UT-13 empty source with \$exists guard"       ut13_empty_source
assert_fixture "UT-14 source is array at root"                ut14_array_at_root

# ── corner cases: bad mapping ─────────────────────────────────────────────────

# UT-15: .json envelope missing expression field
node -e "
const { loadMappingFromObject } = require('${TRANSFORMER}');
const m = JSON.parse(require('fs').readFileSync('${FX}/ut15_missing_expression/mapping.json','utf8'));
try { loadMappingFromObject(m); process.exit(1); }
catch(e) { process.exit(0); }
" && ok "UT-15 missing expression field → error" || fail "UT-15 missing expression field → error"

# UT-16: .json envelope where expression is a number, not a string
node -e "
const { loadMappingFromObject } = require('${TRANSFORMER}');
const m = JSON.parse(require('fs').readFileSync('${FX}/ut16_expression_not_string/mapping.json','utf8'));
try { loadMappingFromObject(m); process.exit(1); }
catch(e) { process.exit(0); }
" && ok "UT-16 expression not a string → error" || fail "UT-16 expression not a string → error"

# UT-17: .jsonata file with syntactically invalid expression
node -e "
const { loadMapping, transform } = require('${TRANSFORMER}');
const mapping = loadMapping('${FX}/ut17_invalid_syntax/mapping.jsonata');
transform({}, mapping).then(() => process.exit(1)).catch(() => process.exit(0));
" && ok "UT-17 invalid JSONata syntax → error" || fail "UT-17 invalid JSONata syntax → error"

# UT-18: .json file that is not valid JSON
node -e "
const { loadMapping } = require('${TRANSFORMER}');
try { loadMapping('${FX}/ut18_invalid_json/mapping.json'); process.exit(1); }
catch(e) { process.exit(0); }
" && ok "UT-18 mapping file not valid JSON → error" || fail "UT-18 mapping file not valid JSON → error"

# UT-19: mapping file does not exist
node -e "
const { loadMapping } = require('${TRANSFORMER}');
try { loadMapping('/tmp/__no_such_file_sli26__.jsonata'); process.exit(1); }
catch(e) { process.exit(0); }
" && ok "UT-19 mapping file does not exist → error" || fail "UT-19 mapping file does not exist → error"

# ── summary ───────────────────────────────────────────────────────────────────
echo ""
echo "=== json_transformer.js: $((PASS+FAIL)) tests, $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
