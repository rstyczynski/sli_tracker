#!/usr/bin/env bash
# Unit tests for tools/ensure_dashboard.sh substitution logic.
# Sprint 32, SLI-64
#
# Tests the dashboard_var_* substitution block in isolation — no OCI CLI calls,
# no oci_scaffold sourcing. _run_subst reimplements the logic directly so it
# can be called and observed cleanly.
#
# Usage (run from repo root):
#   bash tests/unit/test_dashboard.sh

set -euo pipefail

passed=0
failed=0

_pass() { echo "PASS: $*"; ((passed += 1)) || true; }
_fail() { echo "FAIL: $*"; ((failed += 1)) || true; }

assert_eq() {
  local got="$1" want="$2" msg="$3"
  if [[ "$got" == "$want" ]]; then _pass "$msg"
  else _fail "$msg — want='$want' got='$got'"; fi
}

assert_contains() {
  local haystack="$1" needle="$2" msg="$3"
  if [[ "$haystack" == *"$needle"* ]]; then _pass "$msg"
  else _fail "$msg — '$needle' not found in output"; fi
}

assert_not_contains() {
  local haystack="$1" needle="$2" msg="$3"
  if [[ "$haystack" != *"$needle"* ]]; then _pass "$msg"
  else _fail "$msg — '$needle' unexpectedly found in output"; fi
}

# ── _run_subst ────────────────────────────────────────────────────────────────
# Reimplements the substitution + unwrap block from ensure_dashboard.sh.
# Does NOT source oci_scaffold — no side effects, no extra output.
# Writes WIDGETS_JSON to stdout. Exits non-zero and writes to stderr on error.
_run_subst() {
  local state_json="$1"
  local tiles_content="$2"

  local state_tmp tiles_tmp subst_tmp
  state_tmp="$(mktemp /tmp/test-state.XXXXXX)"
  tiles_tmp="$(mktemp /tmp/test-tiles.XXXXXX)"
  subst_tmp="$(mktemp /tmp/test-subst.XXXXXX)"
  printf '%s' "$state_json"    > "$state_tmp"
  printf '%s' "$tiles_content" > "$tiles_tmp"

  local SED_ARGS=()
  while IFS=$'\t' read -r var_name value; do
    [[ -z "$var_name" ]] && continue
    if [[ -z "$value" || "$value" == "null" ]]; then
      echo "ERROR: dashboard_var_${var_name} is empty or null" >&2
      rm -f "$state_tmp" "$tiles_tmp" "$subst_tmp"
      return 1
    fi
    SED_ARGS+=(-e "s|__${var_name}__|${value}|g")
  done < <(jq -r '
    .inputs // {} |
    to_entries[] |
    select(.key | startswith("dashboard_var_")) |
    [(.key | ltrimstr("dashboard_var_")), (.value // "")] |
    @tsv' "$state_tmp")

  if [[ ${#SED_ARGS[@]} -gt 0 ]]; then
    sed "${SED_ARGS[@]}" "$tiles_tmp" > "$subst_tmp"
  else
    cp "$tiles_tmp" "$subst_tmp"
  fi

  local remaining
  remaining=$(grep -oE '__[A-Z0-9_]+__' "$subst_tmp" | sort -u | tr '\n' ' ') || true
  if [[ -n "$remaining" ]]; then
    echo "ERROR: Unsubstituted placeholders remain: ${remaining}" >&2
    rm -f "$state_tmp" "$tiles_tmp" "$subst_tmp"
    return 1
  fi

  jq -c 'if type == "object" and has("widgets") then .widgets else . end' "$subst_tmp"
  rm -f "$state_tmp" "$tiles_tmp" "$subst_tmp"
}

# ── UT-1: substitution with all vars set correctly ────────────────────────────
echo "=== UT-1: substitution with all vars set ==="
state='{
  "inputs": {
    "name_prefix": "test",
    "dashboard_var_COMPARTMENT_OCID": "ocid1.compartment.oc1..aaa",
    "dashboard_var_LOG_GROUP_OCID":   "ocid1.loggroup.oc1..bbb",
    "dashboard_var_LOG_OCID":         "ocid1.log.oc1..ccc",
    "dashboard_var_REGION_ID":        "eu-zurich-1"
  }
}'
tiles='[{"id":"w1","query":"__COMPARTMENT_OCID__/__LOG_GROUP_OCID__/__LOG_OCID__","region":"__REGION_ID__"}]'
out=$(_run_subst "$state" "$tiles")
assert_contains     "$out" "ocid1.compartment.oc1..aaa" "UT-1: COMPARTMENT_OCID substituted"
assert_contains     "$out" "ocid1.loggroup.oc1..bbb"    "UT-1: LOG_GROUP_OCID substituted"
assert_contains     "$out" "ocid1.log.oc1..ccc"         "UT-1: LOG_OCID substituted"
assert_contains     "$out" "eu-zurich-1"                "UT-1: REGION_ID substituted"
assert_not_contains "$out" "__COMPARTMENT_OCID__"       "UT-1: no leftover __COMPARTMENT_OCID__"
assert_not_contains "$out" "__LOG_GROUP_OCID__"         "UT-1: no leftover __LOG_GROUP_OCID__"
assert_not_contains "$out" "__LOG_OCID__"               "UT-1: no leftover __LOG_OCID__"
assert_not_contains "$out" "__REGION_ID__"              "UT-1: no leftover __REGION_ID__"

# ── UT-2: empty value causes exit 1 ──────────────────────────────────────────
echo "=== UT-2: empty value causes failure ==="
state='{
  "inputs": {
    "name_prefix": "test",
    "dashboard_var_COMPARTMENT_OCID": "ocid1.compartment.oc1..aaa",
    "dashboard_var_LOG_GROUP_OCID":   "",
    "dashboard_var_LOG_OCID":         "ocid1.log.oc1..ccc",
    "dashboard_var_REGION_ID":        "eu-zurich-1"
  }
}'
tiles='[{"id":"w1","q":"__COMPARTMENT_OCID__/__LOG_GROUP_OCID__"}]'
err=$(_run_subst "$state" "$tiles" 2>&1) && rc=$? || rc=$?
if [[ $rc -ne 0 ]]; then _pass "UT-2: exits non-zero on empty value"
else _fail "UT-2: expected exit 1, got 0"; fi
assert_contains "$err" "dashboard_var_LOG_GROUP_OCID" "UT-2: error names the empty var"

# ── UT-3: null value causes exit 1 ───────────────────────────────────────────
echo "=== UT-3: null value causes failure ==="
state='{
  "inputs": {
    "name_prefix": "test",
    "dashboard_var_COMPARTMENT_OCID": "ocid1.compartment.oc1..aaa",
    "dashboard_var_LOG_GROUP_OCID":   "ocid1.loggroup.oc1..bbb",
    "dashboard_var_LOG_OCID":         "ocid1.log.oc1..ccc",
    "dashboard_var_REGION_ID":        null
  }
}'
tiles='[{"id":"w1","region":"__REGION_ID__"}]'
err=$(_run_subst "$state" "$tiles" 2>&1) && rc=$? || rc=$?
if [[ $rc -ne 0 ]]; then _pass "UT-3: exits non-zero on null value"
else _fail "UT-3: expected exit 1, got 0"; fi
assert_contains "$err" "dashboard_var_REGION_ID" "UT-3: error names the null var"

# ── UT-4: unsubstituted placeholder detected ─────────────────────────────────
echo "=== UT-4: unsubstituted placeholder detected ==="
state='{
  "inputs": {
    "name_prefix": "test",
    "dashboard_var_COMPARTMENT_OCID": "ocid1.compartment.oc1..aaa"
  }
}'
tiles='[{"id":"w1","q":"__COMPARTMENT_OCID__","extra":"__UNKNOWN_KEY__"}]'
err=$(_run_subst "$state" "$tiles" 2>&1) && rc=$? || rc=$?
if [[ $rc -ne 0 ]]; then _pass "UT-4: exits non-zero on leftover placeholder"
else _fail "UT-4: expected exit 1, got 0"; fi
assert_contains "$err" "Unsubstituted placeholders" "UT-4: error mentions unsubstituted placeholders"
assert_contains "$err" "__UNKNOWN_KEY__"            "UT-4: error names the missing key"

# ── UT-5: OCI export format {"widgets":[...]} unwrapped to plain array ────────
echo "=== UT-5: OCI export format unwrapped ==="
state='{
  "inputs": {
    "name_prefix": "test",
    "dashboard_var_COMPARTMENT_OCID": "ocid1.compartment.oc1..aaa"
  }
}'
tiles='{"widgets":[{"id":"w1","q":"__COMPARTMENT_OCID__"}]}'
out=$(_run_subst "$state" "$tiles")
first_char="${out:0:1}"
assert_eq          "$first_char" "["                          "UT-5: output is plain array"
assert_not_contains "$out"       '"widgets"'                  "UT-5: wrapper object removed"
assert_contains     "$out"       "ocid1.compartment.oc1..aaa" "UT-5: substitution applied after unwrap"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "Results: $passed passed, $failed failed"
[[ $failed -eq 0 ]]
