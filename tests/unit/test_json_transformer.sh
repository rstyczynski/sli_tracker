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
    local actual tmpfile
    actual=$(run_fixture "${case_dir}/source.json" "${case_dir}/mapping.jsonata")
    tmpfile=$(mktemp /tmp/sli26_actual.XXXXXX)
    printf '%s' "$actual" > "$tmpfile"
    if node -e "
const fs = require('fs');
const actual = JSON.parse(fs.readFileSync('${tmpfile}', 'utf8'));
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
"; then
        ok "$label"
    else
        fail "$label"
    fi
    rm -f "$tmpfile"
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

# ── complex real-world scenarios ─────────────────────────────────────────────
# UT-28/29 use the same mapping — tests that one mapping handles both outcomes.
# UT-30/31 use the same mapping — tests that $each correctly computes per-component values.

assert_fixture        "UT-28 github workflow_run success → SLI event + duration_s"  ut28_github_workflow_run_success
assert_fixture        "UT-29 github workflow_run failure → outcome_value=0"          ut29_github_workflow_run_failure
assert_fixture_subset "UT-30 /health all UP → metric value=1 per component"          ut30_health_all_up
assert_fixture_subset "UT-31 /health db DOWN → db value=0, others value=1"           ut31_health_db_down
assert_fixture        "UT-32 github workflow_run → OCI PostMetricData"               ut32_github_to_oci_metric
assert_fixture_subset "UT-33 /health all UP → OCI PostMetricData per component"      ut33_health_to_oci_metric_all_up
assert_fixture_subset "UT-34 /health db DOWN → OCI PostMetricData db=0"             ut34_health_to_oci_metric_db_down
assert_fixture        "UT-35 OCI bucket CloudEvent → log entry + \$substringAfter"  ut35_oci_bucket_event_to_log
assert_fixture        "UT-36 OCI compute CloudEvent → OCI metric with freeformTags" ut36_oci_compute_event_to_metric
assert_fixture        "UT-37 OCI PostgreSQL backup CloudEvent → log entry"           ut37_oci_postgres_event_to_log

# ── negative tests: errors in source (a) and transformation (b) ──────────────
# Each case has a fixture directory: source.json + mapping.jsonata.
# (a) cases degrade gracefully — checked with assert_fixture / assert_fixture_subset.
# (b) cases must throw an error — checked with assert_fixture_error.

# Error-expected helper: transform must reject, not resolve
assert_fixture_error() {
    local label="$1" case_dir="${FX}/$2"
    if node -e "
const { loadMapping, transform } = require('${TRANSFORMER}');
const fs = require('fs');
const src = JSON.parse(fs.readFileSync('${case_dir}/source.json', 'utf8'));
const mapping = loadMapping('${case_dir}/mapping.jsonata');
transform(src, mapping).then(() => process.exit(1)).catch(() => process.exit(0));
"; then ok "$label"; else fail "$label"; fi
}

# (a) source problems — graceful degradation
assert_fixture        "UT-38 (a1) missing conclusion → outcome absent, outcome_value=0" neg_a1_source_missing_conclusion
assert_fixture_subset "UT-39 (a2) component missing status → value=0"                   neg_a2_source_component_no_status
assert_fixture        "UT-40 (a3) freeformTags absent → env dimension omitted"          neg_a3_source_missing_tags

# (b) transformation problems — error must be thrown
assert_fixture        "UT-41 (b1) division by zero → ratio=null (JSONata does not throw)" neg_b1_division_by_zero
assert_fixture_error  "UT-42 (b2) undefined function in expression → error"             neg_b2_undefined_function
assert_fixture_error  "UT-43 (b3) \$toMillis on non-ISO string → error"                 neg_b3_invalid_date

# ── corner cases: bad / unusual source data ───────────────────────────────────

assert_fixture "UT-10 missing field in source omitted"        ut10_missing_field
assert_fixture "UT-11 null field value passes through"        ut11_null_field
assert_fixture "UT-12 number-to-string coercion"              ut12_type_coercion
assert_fixture "UT-13 empty source with \$exists guard"       ut13_empty_source
assert_fixture "UT-14 source is array at root"                ut14_array_at_root

# ── corner cases: bad mapping ─────────────────────────────────────────────────

# UT-15: .json envelope missing expression field
if node -e "
const { loadMappingFromObject } = require('${TRANSFORMER}');
const m = JSON.parse(require('fs').readFileSync('${FX}/ut15_missing_expression/mapping.json','utf8'));
try { loadMappingFromObject(m); process.exit(1); }
catch(e) { process.exit(0); }
"; then ok "UT-15 missing expression field → error"; else fail "UT-15 missing expression field → error"; fi

# UT-16: .json envelope where expression is a number, not a string
if node -e "
const { loadMappingFromObject } = require('${TRANSFORMER}');
const m = JSON.parse(require('fs').readFileSync('${FX}/ut16_expression_not_string/mapping.json','utf8'));
try { loadMappingFromObject(m); process.exit(1); }
catch(e) { process.exit(0); }
"; then ok "UT-16 expression not a string → error"; else fail "UT-16 expression not a string → error"; fi

# UT-17: .jsonata file with syntactically invalid expression
if node -e "
const { loadMapping, transform } = require('${TRANSFORMER}');
const mapping = loadMapping('${FX}/ut17_invalid_syntax/mapping.jsonata');
transform({}, mapping).then(() => process.exit(1)).catch(() => process.exit(0));
"; then ok "UT-17 invalid JSONata syntax → error"; else fail "UT-17 invalid JSONata syntax → error"; fi

# UT-18: .json file that is not valid JSON
if node -e "
const { loadMapping } = require('${TRANSFORMER}');
try { loadMapping('${FX}/ut18_invalid_json/mapping.json'); process.exit(1); }
catch(e) { process.exit(0); }
"; then ok "UT-18 mapping file not valid JSON → error"; else fail "UT-18 mapping file not valid JSON → error"; fi

# UT-19: mapping file does not exist
if node -e "
const { loadMapping } = require('${TRANSFORMER}');
try { loadMapping('/tmp/__no_such_file_sli26__.jsonata'); process.exit(1); }
catch(e) { process.exit(0); }
"; then ok "UT-19 mapping file does not exist → error"; else fail "UT-19 mapping file does not exist → error"; fi

# ── summary ───────────────────────────────────────────────────────────────────
echo ""
echo "=== json_transformer.js: $((PASS+FAIL)) tests, $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
