#!/usr/bin/env bash
# Integration test — emit_curl.sh locally (Sprint 8 reopen, no GitHub workflow)
#
# Runs .github/actions/sli-event/emit_curl.sh on this machine with a real OCI profile
# and self-crafted HTTP signing — no gh, no workflow dispatch, no runner.
#
# Prerequisites: oci (session or API key), jq, openssl, curl; ~/.oci configured;
#   oci_scaffold submodule; same log target as other tests (//sli-events/github-actions).
#
# Usage: bash tests/integration/test_sli_emit_curl_local.sh
#
# Contrast: test_sli_emit_curl_workflow.sh dispatches model-emit-curl.yml (workflow-based).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACTION_DIR="${REPO_ROOT}/.github/actions/sli-event"
OCI_INT_PROFILE="${SLI_INTEGRATION_OCI_PROFILE:-SLI_TEST}"
export OCI_INT_PROFILE
export OCI_CLI_PROFILE="$OCI_INT_PROFILE"

TS="$(date -u '+%Y%m%d_%H%M%S')"
LOG_FILE="${SCRIPT_DIR}/test_run_emit_curl_local_${TS}.log"
OCI_LOG_FILE="${SCRIPT_DIR}/oci_logs_emit_curl_local_${TS}.json"

exec > >(tee -a "$LOG_FILE") 2>&1

echo "# emit_curl local integration — $(date -u)"
echo "# Log: $LOG_FILE"
echo ""

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

[[ -f "${HOME}/.oci/config" ]] && _sli_expand_placeholder_home_in_oci_tree

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

# Real oci for token_based wrapper (same pattern as test_sli_emit_curl_workflow.sh)
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

PASS=0; FAIL=0
pass() { echo "PASS: $*"; PASS=$((PASS+1)); }
fail() { echo "FAIL: $*"; FAIL=$((FAIL+1)); }

_LOCAL_RUN="local-$(date -u +%s)"
export GITHUB_RUN_ID="${_LOCAL_RUN}"
export GITHUB_RUN_NUMBER="1"
export GITHUB_RUN_ATTEMPT="1"
export GITHUB_REPOSITORY="rstyczynski/sli_tracker"
export GITHUB_REPOSITORY_ID="1200217885"
export GITHUB_REF_NAME="main"
export GITHUB_REF="refs/heads/main"
export GITHUB_SHA="$(cd "$REPO_ROOT" && git rev-parse HEAD 2>/dev/null || echo "local")"
export GITHUB_WORKFLOW="LOCAL — emit_curl (no workflow)"
export GITHUB_WORKFLOW_REF="local/test_sli_emit_curl_local"
export GITHUB_JOB="emit-curl-local"
export GITHUB_EVENT_NAME="workflow_dispatch"
export GITHUB_ACTOR="${USER:-local}"
export SLI_OUTCOME="success"
export STEPS_JSON='{"step-main":{"outputs":{},"outcome":"success","conclusion":"success"}}'
export INPUTS_JSON="{}"
export SLI_CONTEXT_JSON
SLI_CONTEXT_JSON="$(jq -nc \
  --arg lid "$SLI_LOG_OCID" \
  '{"oci":{"log-id":$lid,"config-file":"~/.oci/config","profile":"'"$OCI_INT_PROFILE"'"}}')"

echo "=== T1: emit_curl.sh push (self-crafted signing, local process) ==="
_OUT="$(bash "${ACTION_DIR}/emit_curl.sh" 2>&1)" || true
echo "$_OUT"
if echo "$_OUT" | grep -q "SLI log entry pushed to OCI Logging (curl)"; then
  pass "emit_curl reports successful curl push to OCI Logging"
else
  fail "emit_curl did not report successful push (expected curl push notice)"
fi

echo ""
echo "=== T2: OCI Logging — event present (workflow filter) ==="
sleep 15
TS_START=$(date -u -v-10M '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u --date='-10 min' '+%Y-%m-%dT%H:%M:%SZ')
TS_END=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
EVENTS=$(oci logging-search search-logs \
  --search-query "search \"${TENANCY}/${LOG_GROUP_OCID}/${SLI_LOG_OCID}\" | sort by datetime desc | limit 30" \
  --time-start "$TS_START" --time-end "$TS_END" \
  --profile "$OCI_INT_PROFILE" 2>/dev/null | jq '.data.results')

printf '%s\n' "$EVENTS" > "$OCI_LOG_FILE"
echo "# OCI sample: $OCI_LOG_FILE"

MATCH=$(echo "$EVENTS" | jq '[.[] | .data.logContent.data | if type=="string" then fromjson else . end | select(.workflow.name != null) | select(.workflow.name | test("LOCAL — emit_curl"))] | length')
if [[ "${MATCH:-0}" -ge 1 ]]; then
  pass "OCI log contains at least one event with workflow.name LOCAL — emit_curl"
else
  fail "OCI log: no event with workflow.name LOCAL — emit_curl (got=$MATCH want>=1)"
fi

echo ""
echo "=== Summary ==="
echo "passed: $PASS  failed: $FAIL"
echo ""
echo "Artifacts: $LOG_FILE"
echo "           $OCI_LOG_FILE"

[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
