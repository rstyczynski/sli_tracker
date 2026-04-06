#!/usr/bin/env bash
# Integration test — emit_curl via GitHub workflow (SLI-12)
# Dispatches model-emit-curl.yml (no OCI CLI, curl backend) and verifies
# that SLI events land in OCI Logging.
#
# Not used as Sprint 8 reopen gate — for workflow-based validation use this script;
# for local-only signing validation use test_sli_emit_curl_local.sh.
#
# Sections:
#   T1  Dispatch success + failure runs
#   T2  Wait for completion
#   T3  Assert expected conclusions
#   T4  Verify no OCI CLI install (IT-2)
#   T5  Verify curl-specific log notice (IT-3)
#   T6  OCI Logging events with correct content (IT-4)
#   T7  Failure run carries failure_reasons (IT-5)
#
# Prerequisites:  gh (authenticated), oci (with valid session), jq
# Usage:          bash tests/integration/test_sli_emit_curl_workflow.sh

set -euo pipefail

REPO="rstyczynski/sli_tracker"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OCI_INT_PROFILE="${SLI_INTEGRATION_OCI_PROFILE:-SLI_TEST}"
export OCI_INT_PROFILE
export OCI_CLI_PROFILE="$OCI_INT_PROFILE"

TS="$(date -u '+%Y%m%d_%H%M%S')"
LOG_FILE="${SCRIPT_DIR}/test_run_curl_${TS}.log"
OCI_LOG_FILE="${SCRIPT_DIR}/oci_logs_curl_${TS}.json"

exec > >(tee -a "$LOG_FILE") 2>&1

echo "# emit_curl workflow integration test — $(date -u)"
echo "# Log: $LOG_FILE"
echo ""

# ── Home-expansion helper (same as test_sli_integration.sh) ──
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

# ── OCI scaffold — resolve log group and log OCIDs for T6 query ──
export NAME_PREFIX="sli_test_sprint6"
# shellcheck source=../../oci_scaffold/do/oci_scaffold.sh
source "${REPO_ROOT}/oci_scaffold/do/oci_scaffold.sh"

SLI_OCI_LOG_URI="//sli-events/github-actions"
LOG_NAME="${SLI_OCI_LOG_URI##*/}"
_REST="${SLI_OCI_LOG_URI%/*}"
LOG_GROUP_NAME="${_REST##*/}"
COMPARTMENT_PATH="${_REST%/*}"
COMPARTMENT_PATH="${COMPARTMENT_PATH:-/}"

_state_set '.inputs.compartment_path' "$COMPARTMENT_PATH"
_state_set '.inputs.name_prefix'      "$NAME_PREFIX"
_state_set '.inputs.log_group_name'   "$LOG_GROUP_NAME"
_state_set '.inputs.log_name'         "$LOG_NAME"

bash "${REPO_ROOT}/oci_scaffold/resource/ensure-compartment.sh"
COMPARTMENT_OCID=$(_state_get '.compartment.ocid')
_state_set '.inputs.oci_compartment' "$COMPARTMENT_OCID"

bash "${REPO_ROOT}/oci_scaffold/resource/ensure-log_group.sh"
bash "${REPO_ROOT}/oci_scaffold/resource/ensure-log.sh"

LOG_GROUP_OCID=$(_state_get '.log_group.ocid')
SLI_LOG_OCID=$(_state_get '.log.ocid')
TENANCY=$(_oci_tenancy_ocid)

echo ""

PASS=0; FAIL=0
pass() { echo "PASS: $*"; PASS=$((PASS+1)); }
fail() { echo "FAIL: $*"; FAIL=$((FAIL+1)); }
assert_eq() { local d="$1" g="$2" w="$3"; [[ "$g" == "$w" ]] && pass "$d" || fail "$d  (got=$g want=$w)"; }
assert_ge() { local d="$1" g="$2" w="$3"; (( g >= w )) && pass "$d" || fail "$d  (got=$g want>=$w)"; }

# ════════════════════════════════════════════════════════════════
# T1: Dispatch model-emit-curl workflow (IT-1)
# ════════════════════════════════════════════════════════════════
echo "=== T1: Dispatch model-emit-curl — success + failure ==="
R_OK=$(gh workflow run model-emit-curl.yml -R "$REPO" \
  -f simulate-failure=false 2>&1 | grep -o 'runs/[0-9]*' | cut -d/ -f2)
sleep 2
R_FAIL=$(gh workflow run model-emit-curl.yml -R "$REPO" \
  -f simulate-failure=true 2>&1 | grep -o 'runs/[0-9]*' | cut -d/ -f2)
[[ -n "$R_OK"   ]] && pass "emit-curl success triggered: $R_OK"   || fail "emit-curl success trigger failed"
[[ -n "$R_FAIL" ]] && pass "emit-curl failure triggered: $R_FAIL" || fail "emit-curl failure trigger failed"

ALL_RUNS="$R_OK $R_FAIL"

# ════════════════════════════════════════════════════════════════
# T2: Wait for runs to complete (IT-1)
# ════════════════════════════════════════════════════════════════
echo ""
echo "=== T2: Wait for runs to complete ==="
echo "    Runs: $ALL_RUNS"
for i in $(seq 1 20); do
  sleep 15
  all_done=true
  for r in $ALL_RUNS; do
    s=$(gh run view "$r" -R "$REPO" --json status,conclusion -q '"\(.status)/\(.conclusion)"' 2>/dev/null)
    [[ "$s" == completed/* ]] || { all_done=false; break; }
  done
  $all_done && break
done

for r in $ALL_RUNS; do
  s=$(gh run view "$r" -R "$REPO" --json status,conclusion -q '"\(.status)/\(.conclusion)"' 2>/dev/null)
  [[ "${s%%/*}" == "completed" ]] && pass "run $r completed" || fail "run $r did not complete: $s"
done

# ════════════════════════════════════════════════════════════════
# T3: Expected workflow conclusions (IT-1)
# ════════════════════════════════════════════════════════════════
echo ""
echo "=== T3: Expected workflow conclusions ==="
assert_eq "emit-curl success → conclusion success" \
  "$(gh run view "$R_OK"   -R "$REPO" --json conclusion -q .conclusion 2>/dev/null)" "success"
assert_eq "emit-curl failure → conclusion failure" \
  "$(gh run view "$R_FAIL" -R "$REPO" --json conclusion -q .conclusion 2>/dev/null)" "failure"

# Collect job logs once — reused by T4 and T5
declare -A JOB_LOGS
for RUN_ID in $ALL_RUNS; do
  for JOB_ID in $(gh run view "$RUN_ID" -R "$REPO" --json jobs -q '.jobs[].databaseId' 2>/dev/null); do
    JOB_LOGS["${RUN_ID}_${JOB_ID}"]=$(gh api "/repos/$REPO/actions/jobs/$JOB_ID/logs" 2>/dev/null || true)
  done
done

# ════════════════════════════════════════════════════════════════
# T4: No OCI CLI install (IT-2)
# ════════════════════════════════════════════════════════════════
echo ""
echo "=== T4: Verify no OCI CLI install step ran ==="
for key in "${!JOB_LOGS[@]}"; do
  LOG="${JOB_LOGS[$key]}"
  RUN_ID="${key%%_*}"
  if echo "$LOG" | grep -qi "install-oci-cli\|Installing OCI CLI\|pip.*oci-cli"; then
    fail "run $RUN_ID — OCI CLI install detected in job logs (should not be present)"
  else
    pass "run $RUN_ID — no OCI CLI install in job logs"
  fi
  if echo "$LOG" | grep -q "OCI profile restored"; then
    pass "run $RUN_ID — OCI profile restore confirmed"
  else
    fail "run $RUN_ID — OCI profile restore not found in logs"
  fi
done

# ════════════════════════════════════════════════════════════════
# T5: Curl-specific push notice (IT-3)
# ════════════════════════════════════════════════════════════════
echo ""
echo "=== T5: Verify curl-specific SLI push notice ==="
for RUN_ID in $ALL_RUNS; do
  _found_curl_notice=false
  for key in "${!JOB_LOGS[@]}"; do
    [[ "$key" == "${RUN_ID}_"* ]] || continue
    if echo "${JOB_LOGS[$key]}" | grep -q "SLI log entry pushed to OCI Logging (curl)"; then
      _found_curl_notice=true
      break
    fi
  done
  if $_found_curl_notice; then
    pass "run $RUN_ID — curl push notice present"
  else
    fail "run $RUN_ID — curl push notice not found"
  fi
done

# ════════════════════════════════════════════════════════════════
# T6: OCI Logging events — content verification (IT-4)
# ════════════════════════════════════════════════════════════════
echo ""
echo "=== T6: OCI Logging — verify curl events (content) ==="
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

CURL_WF_EVENTS=$(echo "$EVENTS" | jq '[.[] | .data.logContent.data | if type=="string" then fromjson else . end | select(.workflow.name != null) | select(.workflow.name | test("emit_curl"))] | length')
assert_ge "OCI: events carry correct workflow.name (contains 'emit_curl')" "$CURL_WF_EVENTS" 2

# ════════════════════════════════════════════════════════════════
# T7: Failure event carries failure_reasons (IT-5)
# ════════════════════════════════════════════════════════════════
echo ""
echo "=== T7: Failure event carries failure_reasons ==="
FAIL_REASON_CNT=$(echo "$EVENTS" | jq '[.[] | .data.logContent.data | if type=="string" then fromjson else . end | select(.outcome=="failure") | select((.failure_reasons // {}) | type == "object" and length > 0)] | length')
assert_ge "OCI: at least 1 failure event with non-empty failure_reasons" "$FAIL_REASON_CNT" 1

HAS_STEP_MAIN_KEY=$(echo "$EVENTS" | jq '[.[] | .data.logContent.data | if type=="string" then fromjson else . end | select(.outcome=="failure") | .failure_reasons // {} | keys[] | select(test("STEP_MAIN";"i"))] | length')
assert_ge "OCI: failure_reasons contains a STEP_MAIN key" "$HAS_STEP_MAIN_KEY" 1

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

PROGRESS_RUN_DIR="${REPO_ROOT}/progress/integration_runs/curl_${TS}"
mkdir -p "$PROGRESS_RUN_DIR"
cp -f "$LOG_FILE" "${PROGRESS_RUN_DIR}/integration_test_run.log"
[[ -f "$OCI_LOG_FILE" ]] && cp -f "$OCI_LOG_FILE" "${PROGRESS_RUN_DIR}/oci_logs.json" || true
echo "  progress copy : $PROGRESS_RUN_DIR"

[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
