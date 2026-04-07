#!/usr/bin/env bash
# Integration test — OCI Monitoring metric emission (Sprint 12, SLI-17)
#
# Tests emit_curl.sh with EMIT_TARGET=metric and EMIT_TARGET=log,metric.
# Runs scripts locally (no workflow dispatch) with a real OCI profile.
#
# Prerequisites: curl, openssl, jq, oci (OCI CLI for auth gate + monitoring query);
#   ~/.oci configured; oci_scaffold submodule (for log-id lookup in IT-2).
#
# Usage (from repo root):
#   bash tests/integration/test_sli_emit_metric.sh
#
# Environment overrides:
#   SLI_INTEGRATION_OCI_PROFILE   OCI profile name (default: SLI_TEST)
#   SLI_INTEGRATION_AUTH_NO_LOOP  Set to 1 to exit on first auth failure (CI)
#   SLI_METRIC_NAMESPACE          OCI Monitoring namespace (default: sli_tracker)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACTION_DIR="${REPO_ROOT}/.github/actions/sli-event"
OCI_INT_PROFILE="${SLI_INTEGRATION_OCI_PROFILE:-SLI_TEST}"
export OCI_INT_PROFILE
export OCI_CLI_PROFILE="$OCI_INT_PROFILE"
SLI_METRIC_NS="${SLI_METRIC_NAMESPACE:-sli_tracker}"

TS="$(date -u '+%Y%m%d_%H%M%S')"
LOG_FILE="${SCRIPT_DIR}/test_run_emit_metric_${TS}.log"
OCI_METRIC_FILE="${SCRIPT_DIR}/oci_metric_${TS}.json"

exec > >(tee -a "$LOG_FILE") 2>&1

echo "# emit_metric integration test — $(date -u)"
echo "# Log: $LOG_FILE"
echo ""

# ── Home placeholder expansion (same as other integration tests) ──
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
  fi
}
[[ -f "${HOME}/.oci/config" ]] && _sli_expand_placeholder_home_in_oci_tree

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

# ── Resolve tenancy OCID for compartmentId ──
_SLI_TENANCY_OCID="$(oci iam user list --profile "$OCI_INT_PROFILE" 2>/dev/null \
  | jq -r '.data[0]."compartment-id"' 2>/dev/null || true)"
if [[ -z "$_SLI_TENANCY_OCID" ]]; then
  _SLI_TENANCY_OCID="$(awk -v prof="[$OCI_INT_PROFILE]" -v key="tenancy" '
    /^\[/ { in_prof = ($0 == prof) }
    in_prof && $0 ~ "^" key "[ \t]*=" { sub(/^[^=]*=[ \t]*/, ""); print; exit }
  ' "${HOME}/.oci/config" 2>/dev/null || true)"
fi
echo "# Tenancy (compartmentId): ${_SLI_TENANCY_OCID:-<not resolved>}"
echo ""

# ── Setup fake GitHub env vars (no real workflow) ──
_RUN_MARKER="metric-test-$(date -u +%s)"
export GITHUB_RUN_ID="${_RUN_MARKER}"
export GITHUB_RUN_NUMBER="1"
export GITHUB_RUN_ATTEMPT="1"
export GITHUB_REPOSITORY="rstyczynski/sli_tracker"
export GITHUB_REPOSITORY_ID="1200217885"
export GITHUB_REF_NAME="main"
export GITHUB_REF="refs/heads/main"
export GITHUB_SHA="$(cd "$REPO_ROOT" && git rev-parse HEAD 2>/dev/null || echo "local")"
export GITHUB_WORKFLOW="LOCAL — metric test"
export GITHUB_WORKFLOW_REF="local/test_sli_emit_metric"
export GITHUB_JOB="emit-metric-local"
export GITHUB_EVENT_NAME="workflow_dispatch"
export GITHUB_ACTOR="${USER:-local}"
export SLI_OUTCOME="success"
export STEPS_JSON='{"step-main":{"outputs":{},"outcome":"success","conclusion":"success"}}'
export INPUTS_JSON="{}"
export SLI_METRIC_NAMESPACE="$SLI_METRIC_NS"

PASS=0; FAIL=0
pass() { echo "PASS: $*"; PASS=$((PASS+1)); }
fail() { echo "FAIL: $*"; FAIL=$((FAIL+1)); }

# ── IT-1: EMIT_TARGET=metric — metric-only push, no log push ──
echo "=== IT-1: EMIT_TARGET=metric — metric-only push ==="
_OUT1="$(EMIT_TARGET=metric \
  SLI_CONTEXT_JSON='{"oci":{"config-file":"~/.oci/config","profile":"'"$OCI_INT_PROFILE"'"}}' \
  bash "${ACTION_DIR}/emit_curl.sh" 2>&1)" || true
echo "$_OUT1"

if echo "$_OUT1" | grep -q "SLI metric pushed to OCI Monitoring"; then
  pass "IT-1: metric push reported success"
else
  fail "IT-1: no metric push success notice in output"
fi

if echo "$_OUT1" | grep -q "SLI log entry pushed"; then
  fail "IT-1: log push should NOT happen with EMIT_TARGET=metric"
else
  pass "IT-1: log push correctly skipped"
fi

echo ""
echo "=== IT-1b: OCI Monitoring — verify datapoint (waiting 90s for ingestion) ==="
sleep 90

_TS_START="$(date -u -v-5M '+%Y-%m-%dT%H:%M:%S.000Z' 2>/dev/null \
  || date -u --date='-5 min' '+%Y-%m-%dT%H:%M:%S.000Z')"
_TS_END="$(date -u '+%Y-%m-%dT%H:%M:%S.000Z')"

_METRIC_DATA="$(oci monitoring metric-data summarize-metrics-data \
  --namespace "$SLI_METRIC_NS" \
  --query-text "outcome[5m]{}.mean()" \
  --compartment-id "${_SLI_TENANCY_OCID}" \
  --start-time "$_TS_START" \
  --end-time "$_TS_END" \
  --profile "$OCI_INT_PROFILE" 2>/dev/null || echo '{"data":[]}')"

printf '%s\n' "$_METRIC_DATA" > "$OCI_METRIC_FILE"
echo "# OCI metric sample: $OCI_METRIC_FILE"

_METRIC_COUNT="$(echo "$_METRIC_DATA" | jq '[.data // [] | .[] | .aggregated-datapoints // [] | .[]] | length' 2>/dev/null || echo 0)"
if [[ "${_METRIC_COUNT:-0}" -ge 1 ]]; then
  pass "IT-1b: OCI Monitoring contains ≥1 datapoint in namespace $SLI_METRIC_NS"
else
  fail "IT-1b: OCI Monitoring has no datapoints (got=$_METRIC_COUNT, namespace=$SLI_METRIC_NS)"
fi

# ── IT-2: EMIT_TARGET=log,metric — dual push ──
echo ""
echo "=== IT-2: EMIT_TARGET=log,metric — dual push ==="

# Resolve log OCID via oci_scaffold
_SLI_LOG_OCID=""
if [[ -f "${REPO_ROOT}/oci_scaffold/do/oci_scaffold.sh" ]]; then
  export NAME_PREFIX="sli_test_sprint6"
  # shellcheck source=../../oci_scaffold/do/oci_scaffold.sh
  source "${REPO_ROOT}/oci_scaffold/do/oci_scaffold.sh"
  _state_set '.inputs.compartment_path' "/"
  _state_set '.inputs.name_prefix'      "$NAME_PREFIX"
  _state_set '.inputs.log_group_name'   "sli-events"
  _state_set '.inputs.log_name'         "github-actions"
  bash "${REPO_ROOT}/oci_scaffold/resource/ensure-compartment.sh" 2>/dev/null || true
  bash "${REPO_ROOT}/oci_scaffold/resource/ensure-log_group.sh" 2>/dev/null || true
  bash "${REPO_ROOT}/oci_scaffold/resource/ensure-log.sh" 2>/dev/null || true
  _SLI_LOG_OCID="$(_state_get '.log.ocid' 2>/dev/null || true)"
fi

if [[ -z "$_SLI_LOG_OCID" ]]; then
  echo "# WARN: could not resolve log OCID via oci_scaffold — IT-2 log verification skipped"
  _SKIP_LOG_VERIFY=1
else
  _SKIP_LOG_VERIFY=0
  echo "# Log OCID: $_SLI_LOG_OCID"
fi

_OUT2="$(EMIT_TARGET=log,metric \
  SLI_CONTEXT_JSON="$(jq -nc \
    --arg lid "${_SLI_LOG_OCID:-}" \
    '{"oci":{"log-id":$lid,"config-file":"~/.oci/config","profile":"'"$OCI_INT_PROFILE"'"}}')" \
  bash "${ACTION_DIR}/emit_curl.sh" 2>&1)" || true
echo "$_OUT2"

if echo "$_OUT2" | grep -q "SLI metric pushed to OCI Monitoring"; then
  pass "IT-2: metric push reported success"
else
  fail "IT-2: no metric push success notice in output"
fi

if [[ -n "$_SLI_LOG_OCID" ]]; then
  if echo "$_OUT2" | grep -q "SLI log entry pushed to OCI Logging (curl)"; then
    pass "IT-2: log push reported success"
  else
    fail "IT-2: no log push success notice in output"
  fi
else
  echo "SKIP IT-2 log push check — no log OCID available"
fi

echo ""
echo "=== Summary ==="
echo "passed: $PASS  failed: $FAIL"
echo ""
echo "Artifacts:"
echo "  $LOG_FILE"
echo "  $OCI_METRIC_FILE"

[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
