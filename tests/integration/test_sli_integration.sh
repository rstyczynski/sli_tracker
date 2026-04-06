#!/usr/bin/env bash
# Integration tests — Full SLI pipeline (dispatch workflows, verify OCI events).
# Migrated from progress/sprint_6/test_sli_integration.sh (Sprint 7, SLI-10)
#
# Prerequisites:
#   gh       — authenticated GitHub CLI
#   oci      — OCI CLI; session profile SLI_TEST (default) for T7 logging-search and oci_scaffold
#   jq       — JSON processor
#   OCI_CONFIG_PAYLOAD — GitHub repo secret (packed OCI session for workflows; refresh via setup script)
#   oci_scaffold       — git submodule at <repo_root>/oci_scaffold
#
# CI vs local: Workflows use profile SLI_TEST (token) from the secret. Local runs use the same profile
# name by default; export OCI_CLI_PROFILE so bare `oci` calls match. If the GitHub secret expires,
# emit shows "re-authenticate" in CI — refresh with setup_oci_github_access.sh + gh secret set.
#
# Usage (run from repo root):
#   bash tests/integration/test_sli_integration.sh
#
# OCI profile: SLI_INTEGRATION_OCI_PROFILE (default: SLI_TEST, same as setup_oci_github_access session).
#   Gate: oci iam region list --profile <that profile> must succeed.
# Single attempt only (e.g. CI): SLI_INTEGRATION_AUTH_NO_LOOP=1

set -euo pipefail

# Same as setup_oci_github_access.sh — expand ${{HOME}} in ~/.oci after packing for GitHub (local oci breaks otherwise).
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

# Profile for auth gate, T0a, T7 logging-search; oci_scaffold uses OCI_CLI_PROFILE (same value).
OCI_INT_PROFILE="${SLI_INTEGRATION_OCI_PROFILE:-SLI_TEST}"
export OCI_INT_PROFILE
export OCI_CLI_PROFILE="$OCI_INT_PROFILE"

REPO="rstyczynski/sli_tracker"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# Real oci Python entrypoint (not ~/.local/oci-wrapper), for building the token_based wrapper.
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

# Artifact setup — logs land in the integration test directory
TS="$(date -u '+%Y%m%d_%H%M%S')"
LOG_FILE="${SCRIPT_DIR}/test_run_${TS}.log"
OCI_LOG_FILE="${SCRIPT_DIR}/oci_logs_${TS}.json"

exec > >(tee -a "$LOG_FILE") 2>&1

echo "# Integration test run — $(date -u)"
echo "# Execution log : $LOG_FILE"

if [[ -f "${HOME}/.oci/config" ]]; then
  _sli_expand_placeholder_home_in_oci_tree
  echo "# Expanded \${{HOME}} in ~/.oci for local oci (same as setup_oci_github_access.sh startup)"
fi

echo ""
echo "=== Operator gate: OCI authentication (mandatory — verified by API) ==="
echo "Profile: $OCI_INT_PROFILE (OCI_CLI_PROFILE=$OCI_CLI_PROFILE)"
echo "This script blocks until: oci iam region list --profile \"$OCI_INT_PROFILE\" succeeds."
echo "To create/refresh the SLI_TEST session and upload to GitHub (browser + gh):"
echo "  bash \"${REPO_ROOT}/.github/actions/oci-profile-setup/setup_oci_github_access.sh\" --repo \"$REPO\""
echo "(Uses DEFAULT only to resolve home region; session profile name defaults to SLI_TEST — see script --help.)"
echo ""

# Session profiles (e.g. SLI_TEST) use --auth security_token; API-key-only profiles omit it.
_sli_oci_region_list_ok() {
  if oci iam region list --profile "$OCI_INT_PROFILE" --auth security_token >/dev/null 2>&1; then
    return 0
  fi
  oci iam region list --profile "$OCI_INT_PROFILE" >/dev/null 2>&1
}

_auth_attempt=0
while ! _sli_oci_region_list_ok; do
  _auth_attempt=$((_auth_attempt + 1))
  echo "OCI session not valid for profile '$OCI_INT_PROFILE' (failed attempt $_auth_attempt)."
  if [[ "${SLI_INTEGRATION_AUTH_NO_LOOP:-}" == "1" ]]; then
    echo "SLI_INTEGRATION_AUTH_NO_LOOP=1 — exiting. Fix auth and re-run."
    exit 1
  fi
  echo "Run setup_oci_github_access.sh (above) or fix ~/.oci, then wait. Retrying in 20 seconds (Ctrl+C to abort)..."
  sleep 20
done
echo "OK: profile '$OCI_INT_PROFILE' passed oci iam region list — continuing."
echo ""

# oci_scaffold runs bare `oci` (no --auth). Session profiles need --auth security_token — same as
# oci_profile_setup.sh token_based wrapper on GitHub Actions.
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
  echo "# token_based: PATH prepends ${_wrap_dir}/oci (real oci: ${_SLI_REAL_OCI_BIN})"
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

[[ -z "$LOG_GROUP_NAME" || -z "$LOG_NAME" ]] && { echo "ERROR: SLI_OCI_LOG_URI must be /[compartment/]log_group/log, got: $SLI_OCI_LOG_URI"; false; }

_state_set '.inputs.compartment_path' "$COMPARTMENT_PATH"
_state_set '.inputs.name_prefix'      "$NAME_PREFIX"
_state_set '.inputs.log_group_name'   "$LOG_GROUP_NAME"
_state_set '.inputs.log_name'         "$LOG_NAME"

bash "${REPO_ROOT}/oci_scaffold/resource/ensure-compartment.sh"

COMPARTMENT_OCID=$(_state_get '.compartment.ocid')
[[ -z "$COMPARTMENT_OCID" || "$COMPARTMENT_OCID" == "null" ]] && { echo "ERROR: ensure-compartment.sh did not resolve compartment '$COMPARTMENT_PATH'"; false; }

_state_set '.inputs.oci_compartment' "$COMPARTMENT_OCID"

bash "${REPO_ROOT}/oci_scaffold/resource/ensure-log_group.sh"
bash "${REPO_ROOT}/oci_scaffold/resource/ensure-log.sh"

LOG_GROUP_OCID=$(_state_get '.log_group.ocid')
SLI_LOG_OCID=$(_state_get '.log.ocid')
TENANCY=$(_oci_tenancy_ocid)

[[ -z "$LOG_GROUP_OCID" || "$LOG_GROUP_OCID" == "null" ]] && { echo "ERROR: ensure-log_group.sh did not resolve '$LOG_GROUP_NAME'"; false; }
[[ -z "$SLI_LOG_OCID"   || "$SLI_LOG_OCID"   == "null" ]] && { echo "ERROR: ensure-log.sh did not resolve '$LOG_NAME'"; false; }

gh variable set SLI_OCI_LOG_ID       --body "$SLI_LOG_OCID"   -R "$REPO"
gh variable set SLI_OCI_LOG_GROUP_ID --body "$LOG_GROUP_OCID" -R "$REPO"

PASS=0; FAIL=0

pass() { echo "PASS: $*"; PASS=$((PASS+1)); }
fail() { echo "FAIL: $*"; FAIL=$((FAIL+1)); }

assert_eq() {
  local desc="$1" got="$2" want="$3"
  [[ "$got" == "$want" ]] && pass "$desc" || fail "$desc  (got=$got want=$want)"
}

assert_ge() {
  local desc="$1" got="$2" want="$3"
  (( got >= want )) && pass "$desc" || fail "$desc  (got=$got want>=$want)"
}

echo "=== T0: repo tooling prerequisites ==="
command -v gh  >/dev/null 2>&1 && pass "gh CLI present"  || fail "gh CLI missing"
command -v oci >/dev/null 2>&1 && pass "OCI CLI present" || fail "OCI CLI missing"
command -v jq  >/dev/null 2>&1 && pass "jq present"      || fail "jq missing"

echo ""
echo "=== T0a: OCI profile (same as gate) — T7 logging-search uses this profile ==="
if _sli_oci_region_list_ok; then
  pass "local profile $OCI_INT_PROFILE: API call succeeded (already verified at gate)"
else
  fail "local profile $OCI_INT_PROFILE: API call failed (unexpected after gate)"
fi

echo ""
echo "=== T0b: OCI resource resolution (oci_scaffold URI-style) ==="
[[ "$TENANCY"       == ocid1.tenancy.*  ]] && pass "TENANCY resolved: $TENANCY"           || fail "TENANCY invalid"
[[ "$LOG_GROUP_OCID" == ocid1.loggroup.* ]] && pass "LOG_GROUP_OCID resolved: $LOG_GROUP_OCID" || fail "LOG_GROUP_OCID invalid"
[[ "$SLI_LOG_OCID"  == ocid1.log.*     ]] && pass "SLI_LOG_OCID resolved: $SLI_LOG_OCID" || fail "SLI_LOG_OCID invalid"

echo ""
echo "=== T1: unit tests — emit.sh helper functions ==="
UNIT_OUT=$(bash "${REPO_ROOT}/tests/unit/test_emit.sh" 2>&1)
UNIT_PASSED=$(echo "$UNIT_OUT" | grep -oE 'passed: [0-9]+' | grep -oE '[0-9]+')
UNIT_FAILED=$(echo "$UNIT_OUT" | grep -oE 'failed: [0-9]+'  | grep -oE '[0-9]+')
assert_eq "emit.sh unit tests: passed count" "$UNIT_PASSED" "47"
assert_eq "emit.sh unit tests: failed count" "$UNIT_FAILED" "0"

echo ""
echo "=== T2: model-call — success + failure workflow dispatch ==="
R_CALL_OK=$(gh workflow run model-call.yml -R "$REPO" \
  -f environment=model-env-1 -f run-type=apply -f instance=1 -f simulate-failure=false \
  2>&1 | grep -o 'runs/[0-9]*' | cut -d/ -f2)
sleep 2
R_CALL_FAIL=$(gh workflow run model-call.yml -R "$REPO" \
  -f environment=model-env-1 -f run-type=apply -f instance=1 -f simulate-failure=true \
  2>&1 | grep -o 'runs/[0-9]*' | cut -d/ -f2)
[[ -n "$R_CALL_OK"   ]] && pass "model-call success run triggered: $R_CALL_OK"   || fail "model-call success trigger failed"
[[ -n "$R_CALL_FAIL" ]] && pass "model-call failure run triggered: $R_CALL_FAIL" || fail "model-call failure trigger failed"

echo ""
echo "=== T3: model-push — success + failure workflow dispatch ==="
sleep 2
R_PUSH_OK=$(gh workflow run model-push.yml -R "$REPO" \
  -f simulate-failure=false 2>&1 | grep -o 'runs/[0-9]*' | cut -d/ -f2)
sleep 2
R_PUSH_FAIL=$(gh workflow run model-push.yml -R "$REPO" \
  -f simulate-failure=true  2>&1 | grep -o 'runs/[0-9]*' | cut -d/ -f2)
[[ -n "$R_PUSH_OK"   ]] && pass "model-push success run triggered: $R_PUSH_OK"   || fail "model-push success trigger failed"
[[ -n "$R_PUSH_FAIL" ]] && pass "model-push failure run triggered: $R_PUSH_FAIL" || fail "model-push failure trigger failed"

ALL_RUNS="$R_CALL_OK $R_CALL_FAIL $R_PUSH_OK $R_PUSH_FAIL"

echo ""
echo "=== T4: wait for all four runs to complete ==="
echo "    Runs: $ALL_RUNS"
for i in $(seq 1 20); do
  sleep 30
  all_done=true
  for r in $ALL_RUNS; do
    s=$(gh run view "$r" -R "$REPO" --json status,conclusion -q '"\(.status)/\(.conclusion)"' 2>/dev/null)
    [[ "$s" == completed/* ]] || { all_done=false; break; }
  done
  $all_done && break
done

for r in $ALL_RUNS; do
  s=$(gh run view "$r" -R "$REPO" --json status,conclusion -q '"\(.status)/\(.conclusion)"' 2>/dev/null)
  pass_or_fail="${s%%/*}"
  [[ "$pass_or_fail" == "completed" ]] && pass "run $r completed" || fail "run $r did not complete: $s"
done

echo ""
echo "=== T5: expected workflow conclusions ==="
assert_eq "model-call success → conclusion success" \
  "$(gh run view "$R_CALL_OK"   -R "$REPO" --json conclusion -q .conclusion 2>/dev/null)" "success"
assert_eq "model-call failure → conclusion failure" \
  "$(gh run view "$R_CALL_FAIL" -R "$REPO" --json conclusion -q .conclusion 2>/dev/null)" "failure"
assert_eq "model-push success → conclusion success" \
  "$(gh run view "$R_PUSH_OK"   -R "$REPO" --json conclusion -q .conclusion 2>/dev/null)" "success"
assert_eq "model-push failure → conclusion failure" \
  "$(gh run view "$R_PUSH_FAIL" -R "$REPO" --json conclusion -q .conclusion 2>/dev/null)" "failure"

echo ""
echo "=== T6: sli-event step emitted to OCI (per-job notice) ==="
for RUN_ID in $ALL_RUNS; do
  for JOB_ID in $(gh run view "$RUN_ID" -R "$REPO" --json jobs -q '.jobs[].databaseId' 2>/dev/null); do
    JOB_NAME=$(gh run view "$RUN_ID" -R "$REPO" --json jobs -q ".jobs[] | select(.databaseId == $JOB_ID) | .name" 2>/dev/null)
    LOG=$(gh api /repos/$REPO/actions/jobs/$JOB_ID/logs 2>/dev/null)
    if echo "$LOG" | grep -q "SLI log entry pushed to OCI Logging"; then
      pass "run $RUN_ID / $JOB_NAME → SLI pushed"
    elif echo "$LOG" | grep -q "SLI OCI push skipped"; then
      pass "run $RUN_ID / $JOB_NAME → SLI push skipped (no OCI config in this job)"
    elif echo "$LOG" | grep -qE "re-authenticate your CLI session|SLI report failed to push to OCI Logging"; then
      fail "run $RUN_ID / $JOB_NAME → OCI push failed in CI (token/session in OCI_CONFIG_PAYLOAD likely expired — refresh secret; not your local browser session)"
    elif echo "$LOG" | grep -q "Init — runner selection" && ! echo "$LOG" | grep -q "SLI"; then
      pass "run $RUN_ID / $JOB_NAME → init job (no SLI step expected)"
    else
      fail "run $RUN_ID / $JOB_NAME → unexpected SLI push outcome"
    fi
  done
done

echo ""
echo "=== T7: OCI Logging received events — query last 15 min ==="
sleep 30
TS_START=$(date -u -v-15M '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u --date='-15 min' '+%Y-%m-%dT%H:%M:%SZ')
TS_END=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
EVENTS=$(oci logging-search search-logs \
  --search-query "search \"${TENANCY}/${LOG_GROUP_OCID}/${SLI_LOG_OCID}\" | sort by datetime desc | limit 50" \
  --time-start "$TS_START" --time-end "$TS_END" \
  --profile "$OCI_INT_PROFILE" 2>/dev/null | jq '.data.results')

printf '%s\n' "$EVENTS" > "$OCI_LOG_FILE"
echo "# OCI log captured: $OCI_LOG_FILE"

TOTAL=$(echo "$EVENTS" | jq 'length')
assert_ge "OCI received at least 12 events (4 runs × 3 jobs)" "$TOTAL" 12

SUCCESS_COUNT=$(echo "$EVENTS" | jq '[.[] | .data.logContent.data | if type=="string" then fromjson else . end | select(.outcome=="success")] | length')
FAILURE_COUNT=$(echo "$EVENTS" | jq '[.[] | .data.logContent.data | if type=="string" then fromjson else . end | select(.outcome=="failure")] | length')
assert_ge "OCI: at least 4 success outcome events" "$SUCCESS_COUNT" 4
assert_ge "OCI: at least 4 failure outcome events" "$FAILURE_COUNT" 4

CALL_EVENTS=$(echo "$EVENTS" | jq '[.[] | .data.logContent.data | if type=="string" then fromjson else . end | select((.workflow.name // "") | test("API / UI call"))] | length')
PUSH_EVENTS=$(echo "$EVENTS" | jq '[.[] | .data.logContent.data | if type=="string" then fromjson else . end | select((.workflow.name // "") | test("Push trigger"))] | length')
assert_ge "OCI: model-call events present" "$CALL_EVENTS" 3
assert_ge "OCI: model-push events present" "$PUSH_EVENTS" 3

FAIL_REASON_COUNT=$(echo "$EVENTS" | jq '[.[] | .data.logContent.data | if type=="string" then fromjson else . end | select((.failure_reasons // {}) | type == "object" and length > 0)] | length')
assert_ge "OCI: at least 4 failure events carry failure_reasons" "$FAIL_REASON_COUNT" 4

INIT_EVENTS=$(echo "$EVENTS" | jq '[.[] | .data.logContent.data | if type=="string" then fromjson else . end | select((.workflow.job // "") == "sli-init")] | length')
assert_ge "OCI: sli-init job events present" "$INIT_EVENTS" 4

LEAF_EVENTS=$(echo "$EVENTS" | jq '[.[] | .data.logContent.data | if type=="string" then fromjson else . end | select((.workflow.job // "") == "leaf")] | length')
assert_ge "OCI: leaf job events present" "$LEAF_EVENTS" 8

echo ""
echo "=== T8: SLI-9 — environments field is native JSON array (not escaped string) ==="
ESCAPED_ENV_COUNT=$(echo "$EVENTS" | jq '[.[] | .data.logContent.data | if type=="string" then fromjson else . end | select(.environments != null) | select(.environments | type == "string")] | length')
NATIVE_ENV_COUNT=$(echo "$EVENTS"  | jq '[.[] | .data.logContent.data | if type=="string" then fromjson else . end | select(.environments != null) | select(.environments | type == "array")] | length')
assert_eq "OCI: environments field is not an escaped string (count=0)" "$ESCAPED_ENV_COUNT" "0"
assert_ge "OCI: environments field is native array in at least 4 events" "$NATIVE_ENV_COUNT" 4

echo ""
echo "=== Summary ==="
echo "passed: $PASS  failed: $FAIL"

echo ""
echo "=== Artifacts ==="
echo "  execution log : $LOG_FILE"
echo "  OCI log       : $OCI_LOG_FILE"

PROGRESS_RUN_DIR="${REPO_ROOT}/progress/integration_runs/${TS}"
mkdir -p "$PROGRESS_RUN_DIR"
cp -f "$LOG_FILE" "${PROGRESS_RUN_DIR}/integration_test_run.log"
[[ -f "$OCI_LOG_FILE" ]] && cp -f "$OCI_LOG_FILE" "${PROGRESS_RUN_DIR}/oci_logs.json" || true
echo "  progress copy : $PROGRESS_RUN_DIR (same files for archive under progress/)"

[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
