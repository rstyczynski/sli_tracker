#!/usr/bin/env bash
# Integration test — sli-event-js action via GitHub workflow (SLI-16)
# Dispatches model-emit-js.yml (oci-profile-setup + JS action post hook, no OCI CLI) and
# verifies that SLI events land in OCI Logging.
#
# Sections:
#   T1  Dispatch success + failure runs
#   T2  Wait for completion
#   T3  Assert expected conclusions
#   T4  Verify no OCI CLI install (IT-JS-4)
#   T5  Verify OCI profile restore notice in logs (IT-JS-5)
#   T6  OCI Logging events with correct content (IT-JS-6)
#   T7  Events carry correct workflow.name (IT-JS-7)
#
# Prerequisites:  gh (authenticated), oci (with valid session), jq
# Usage:          bash tests/integration/test_sli_emit_js_workflow.sh

set -euo pipefail

REPO="rstyczynski/sli_tracker"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OCI_INT_PROFILE="${SLI_INTEGRATION_OCI_PROFILE:-SLI_TEST}"
export OCI_INT_PROFILE
export OCI_CLI_PROFILE="$OCI_INT_PROFILE"

TS="$(date -u '+%Y%m%d_%H%M%S')"
LOG_FILE="${SCRIPT_DIR}/test_run_js_${TS}.log"
OCI_LOG_FILE="${SCRIPT_DIR}/oci_logs_js_${TS}.json"

exec > >(tee -a "$LOG_FILE") 2>&1

echo "# sli-event-js workflow integration test — $(date -u)"
echo "# Log: $LOG_FILE"
echo ""

# ── Home-expansion helper ──
_sli_expand_placeholder_home_in_oci_tree() {
  if command -v perl >/dev/null 2>&1; then
    perl -pi -e "s#\\$\\{\\{HOME\\}\\}#${HOME}#g" "${HOME}/.oci/config" || true
    if [[ -d "${HOME}/.oci/sessions" ]]; then
      find "${HOME}/.oci/sessions" -type f -print0 2>/dev/null \
        | while IFS= read -r -d '' f; do
            perl -pi -e "s#\\$\\{\\{HOME\\}\\}#${HOME}#g" "$f" || true
          done
    fi
  else
    sed -i.bak "s#\${{HOME}}#${HOME}#g" "${HOME}/.oci/config" || true
    if [[ -d "${HOME}/.oci/sessions" ]]; then
      find "${HOME}/.oci/sessions" -type f -print0 2>/dev/null \
        | while IFS= read -r -d '' f; do
            sed -i.bak "s#\${{HOME}}#${HOME}#g" "$f" || true
          done
    fi
  fi
}

if [[ -f "${HOME}/.oci/config" ]]; then
  _sli_expand_placeholder_home_in_oci_tree
fi

# ── Auth gate ──
_sli_oci_region_list_ok() {
  if oci iam region list --profile "$OCI_INT_PROFILE" --auth security_token >/dev/null 2>&1; then
    return 0
  fi
  oci iam region list --profile "$OCI_INT_PROFILE" >/dev/null 2>&1
}

echo "=== Auth gate: OCI profile $OCI_INT_PROFILE ==="
_auth_attempt=0
while ! _sli_oci_region_list_ok; do
  _auth_attempt=$((_auth_attempt + 1))
  echo "OCI session not valid (attempt $_auth_attempt)."
  if [[ "${SLI_INTEGRATION_AUTH_NO_LOOP:-}" == "1" ]]; then
    echo "SLI_INTEGRATION_AUTH_NO_LOOP=1 — exiting."
    exit 1
  fi
  echo "Retrying in 20s..."
  sleep 20
done
echo "OK: OCI profile valid."
echo ""

# ── Real OCI binary for local token_based wrapper ──
_SLI_REAL_OCI_BIN=""
for _c in /opt/homebrew/bin/oci /usr/local/bin/oci; do
  if [[ -x "$_c" ]]; then _SLI_REAL_OCI_BIN="$_c"; break; fi
done
if [[ -z "$_SLI_REAL_OCI_BIN" ]]; then
  _v="$(command -v oci 2>/dev/null || true)"
  if [[ -n "$_v" && "$_v" != *oci-wrapper* ]]; then
    _SLI_REAL_OCI_BIN="$_v"
  fi
fi
unset _c _v

if [[ -n "${_SLI_REAL_OCI_BIN:-}" ]] && oci iam region list --profile "$OCI_INT_PROFILE" --auth security_token >/dev/null 2>&1; then
  _wrap_dir="${HOME}/.local/oci-wrapper/bin"
  mkdir -p "$_wrap_dir"
  {
    printf '%s\n' '#!/bin/bash'
    printf '%s\n' 'set -euo pipefail'
    printf '%s\n' "exec \"${_SLI_REAL_OCI_BIN}\" --auth security_token \"\$@\""
  } > "${_wrap_dir}/oci"
  chmod +x "${_wrap_dir}/oci"
  export PATH="${_wrap_dir}:${PATH}"
  echo "# token_based wrapper installed for local oci"
fi
echo ""

source "${REPO_ROOT}/tools/ensure_oci_resources.sh"
ensure_sli_log_resources "$REPO_ROOT" "$OCI_INT_PROFILE" "sli_test_sprint6" "//sli-events/github-actions"

echo ""

PASS=0; FAIL=0
pass() { echo "PASS: $*"; PASS=$((PASS+1)); }
fail() { echo "FAIL: $*"; FAIL=$((FAIL+1)); }
assert_eq() { local d="$1" g="$2" w="$3"; [[ "$g" == "$w" ]] && pass "$d" || fail "$d  (got=$g want=$w)"; }
assert_ge() { local d="$1" g="$2" w="$3"; (( g >= w )) && pass "$d" || fail "$d  (got=$g want>=$w)"; }

# ════════════════════════════════════════════════════════════════
# T1: Dispatch model-emit-js workflow (IT-JS-1)
# ════════════════════════════════════════════════════════════════
echo "=== T1: Dispatch model-emit-js — success + failure ==="

# TODO: implement — dispatch model-emit-js.yml with simulate-failure=false and =true
# Expected: two run IDs captured in R_OK and R_FAIL
R_OK=""
R_FAIL=""

echo "Dispatching success run..."
R_OK=$(gh workflow run model-emit-js.yml -R "$REPO" \
  -f simulate-failure=false 2>&1 | grep -o 'runs/[0-9]*' | cut -d/ -f2 || true)
sleep 2
echo "Dispatching failure run..."
R_FAIL=$(gh workflow run model-emit-js.yml -R "$REPO" \
  -f simulate-failure=true 2>&1 | grep -o 'runs/[0-9]*' | cut -d/ -f2 || true)

[[ -n "$R_OK"   ]] && pass "emit-js success triggered: $R_OK"   || fail "emit-js success trigger failed"
[[ -n "$R_FAIL" ]] && pass "emit-js failure triggered: $R_FAIL" || fail "emit-js failure trigger failed"

ALL_RUNS="$R_OK $R_FAIL"

# ════════════════════════════════════════════════════════════════
# T2: Wait for runs to complete (IT-JS-2)
# ════════════════════════════════════════════════════════════════
echo ""
echo "=== T2: Wait for runs to complete ==="
echo "    Runs: $ALL_RUNS"

# TODO: implement — wait loop (same pattern as test_sli_emit_curl_workflow.sh T2)
for _i in $(seq 1 20); do
  sleep 15
  all_done=true
  for r in $ALL_RUNS; do
    [[ -z "$r" ]] && continue
    s=$(gh run view "$r" -R "$REPO" --json status,conclusion -q '"\(.status)/\(.conclusion)"' 2>/dev/null || echo "unknown/")
    [[ "$s" == completed/* ]] || { all_done=false; break; }
  done
  $all_done && break
done

for r in $ALL_RUNS; do
  [[ -z "$r" ]] && continue
  s=$(gh run view "$r" -R "$REPO" --json status,conclusion -q '"\(.status)/\(.conclusion)"' 2>/dev/null || echo "unknown/")
  [[ "${s%%/*}" == "completed" ]] && pass "run $r completed" || fail "run $r did not complete: $s"
done

# ════════════════════════════════════════════════════════════════
# T3: Expected workflow conclusions (IT-JS-3)
# ════════════════════════════════════════════════════════════════
echo ""
echo "=== T3: Expected workflow conclusions ==="
[[ -n "$R_OK" ]] && assert_eq "emit-js success → conclusion success" \
  "$(gh run view "$R_OK"   -R "$REPO" --json conclusion -q .conclusion 2>/dev/null)" "success" || true
[[ -n "$R_FAIL" ]] && assert_eq "emit-js failure → conclusion failure" \
  "$(gh run view "$R_FAIL" -R "$REPO" --json conclusion -q .conclusion 2>/dev/null)" "failure" || true

# Collect job logs
declare -A JOB_LOGS
for RUN_ID in $ALL_RUNS; do
  [[ -z "$RUN_ID" ]] && continue
  for JOB_ID in $(gh run view "$RUN_ID" -R "$REPO" --json jobs -q '.jobs[].databaseId' 2>/dev/null || true); do
    JOB_LOGS["${RUN_ID}_${JOB_ID}"]=$(gh api "/repos/$REPO/actions/jobs/$JOB_ID/logs" 2>/dev/null || true)
  done
done

# ════════════════════════════════════════════════════════════════
# T4: No OCI CLI install (IT-JS-4)
# ════════════════════════════════════════════════════════════════
echo ""
echo "=== T4: Verify no OCI CLI install step ran ==="

# TODO: implement — check job logs do not contain OCI CLI install markers
for key in "${!JOB_LOGS[@]}"; do
  LOG="${JOB_LOGS[$key]}"
  RUN_ID="${key%%_*}"
  if echo "$LOG" | grep -qi "install-oci-cli\|Installing OCI CLI\|pip.*oci-cli"; then
    fail "run $RUN_ID — OCI CLI install detected (should not be present)"
  else
    pass "run $RUN_ID — no OCI CLI install in job logs"
  fi
done

# ════════════════════════════════════════════════════════════════
# T5: Pre hook notice (IT-JS-5)
# ════════════════════════════════════════════════════════════════
echo ""
echo "=== T5: Verify OCI profile setup step ran in workflow logs ==="

# Job logs must contain oci-profile-setup notice (e.g. "OCI profile restored under ...")
for RUN_ID in $ALL_RUNS; do
  [[ -z "$RUN_ID" ]] && continue
  _found_pre=false
  for key in "${!JOB_LOGS[@]}"; do
    [[ "$key" == "${RUN_ID}_"* ]] || continue
    if echo "${JOB_LOGS[$key]}" | grep -qi "OCI profile.*configured\|OCI profile restored"; then
      _found_pre=true
      break
    fi
  done
  $_found_pre && pass "run $RUN_ID — OCI profile restore notice found" \
              || fail "run $RUN_ID — OCI profile restore notice not found"
done

# ════════════════════════════════════════════════════════════════
# T6: OCI Logging events — content verification (IT-JS-6)
# ════════════════════════════════════════════════════════════════
echo ""
echo "=== T6: OCI Logging — verify JS action events ==="

# TODO: implement — query OCI Logging, assert at least 2 events (1 success, 1 failure)
sleep 30
TS_START=$(date -u -v-15M '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u --date='-15 min' '+%Y-%m-%dT%H:%M:%SZ')
TS_END=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
EVENTS=$(oci logging-search search-logs \
  --search-query "search \"${TENANCY}/${LOG_GROUP_OCID}/${SLI_LOG_OCID}\" | sort by datetime desc | limit 20" \
  --time-start "$TS_START" --time-end "$TS_END" \
  --profile "$OCI_INT_PROFILE" 2>/dev/null | jq '.data.results')

printf '%s\n' "$EVENTS" > "$OCI_LOG_FILE"
echo "# OCI log captured: $OCI_LOG_FILE"

TOTAL=$(echo "$EVENTS" | jq 'length')
assert_ge "OCI received at least 2 events (2 runs × 1 job)" "$TOTAL" 2

SUCCESS_CNT=$(echo "$EVENTS" | jq '[.[] | .data.logContent.data | if type=="string" then fromjson else . end | select(.outcome=="success")] | length')
FAILURE_CNT=$(echo "$EVENTS" | jq '[.[] | .data.logContent.data | if type=="string" then fromjson else . end | select(.outcome=="failure")] | length')
assert_ge "OCI: at least 1 success event" "$SUCCESS_CNT" 1
assert_ge "OCI: at least 1 failure event" "$FAILURE_CNT" 1

# ════════════════════════════════════════════════════════════════
# T7: Events carry correct workflow.name (IT-JS-7)
# ════════════════════════════════════════════════════════════════
echo ""
echo "=== T7: Events carry correct workflow.name ==="

# TODO: implement — verify workflow.name contains 'emit_js' or 'emit-js'
JS_WF_EVENTS=$(echo "$EVENTS" | jq '[.[] | .data.logContent.data | if type=="string" then fromjson else . end | select(.workflow.name != null) | select(.workflow.name | test("emit.js";"i"))] | length')
assert_ge "OCI: events carry workflow.name matching 'emit*js'" "$JS_WF_EVENTS" 2

# ════════════════════════════════════════════════════════════════
# Summary
# ════════════════════════════════════════════════════════════════
echo ""
echo "=== Summary ==="
echo "passed: $PASS  failed: $FAIL"

echo ""
echo "=== Artifacts ==="
echo "  execution log : $LOG_FILE"
echo "  OCI log       : $OCI_LOG_FILE"

PROGRESS_RUN_DIR="${REPO_ROOT}/progress/integration_runs/js_${TS}"
mkdir -p "$PROGRESS_RUN_DIR"
cp -f "$LOG_FILE" "${PROGRESS_RUN_DIR}/integration_test_run.log"
[[ -f "$OCI_LOG_FILE" ]] && cp -f "$OCI_LOG_FILE" "${PROGRESS_RUN_DIR}/oci_logs.json" || true
echo "  progress copy : $PROGRESS_RUN_DIR"

[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
