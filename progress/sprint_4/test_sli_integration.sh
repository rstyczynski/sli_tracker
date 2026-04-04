#!/usr/bin/env bash
# Sprint 4 — Integration tests (SLI-5: improve workflow tests).
# Extends Sprint 3 tests by replacing hardcoded OCI resource OCIDs with
# URI-style dynamic resolution via oci_scaffold submodule.
#
# oci_scaffold: https://github.com/rstyczynski/oci_scaffold
#   - _oci_tenancy_ocid()  →  tenancy via oci os ns get-metadata
#   - ensure-log_group.sh pattern  →  log group by compartment + display-name
#   - ensure-log.sh pattern        →  log by log-group + display-name
#
# Prerequisites:
#   gh       — authenticated GitHub CLI
#   oci      — OCI CLI with DEFAULT profile
#   jq       — JSON processor
#   SLI_OCI_LOG_URI    — GitHub repo variable:  log_group_name/log_name
#                        e.g. "sli-events/github-actions"
#   OCI_CONFIG_PAYLOAD — GitHub repo secret (packed OCI session token)
#   oci_scaffold       — git submodule at <repo_root>/oci_scaffold
#
# Usage (run from repo root):
#   bash progress/sprint_4/test_sli_integration.sh
#
# All tests print  PASS: <description>  or  FAIL: <description>  per assertion.
# Exit code is 0 if all assertions pass, 1 otherwise.

set -euo pipefail

REPO="rstyczynski/sli_tracker"
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

# ── Resolve OCI resource identifiers via oci_scaffold (URI-style) ─────────────
#
# SLI_OCI_LOG_URI format:  log_group_display_name/log_display_name
#
# NAME_PREFIX controls the oci_scaffold state file name; state-*.json is
# excluded from git via .gitignore.

export NAME_PREFIX="sli_test_sprint4"
# shellcheck source=oci_scaffold/do/oci_scaffold.sh
source "${REPO_ROOT}/oci_scaffold/do/oci_scaffold.sh"

SLI_OCI_LOG_URI=$(gh variable get SLI_OCI_LOG_URI -R "$REPO" --json value -q .value 2>/dev/null)
[[ -z "$SLI_OCI_LOG_URI" ]] && { echo "ERROR: SLI_OCI_LOG_URI repo variable not set (format: log_group_name/log_name)"; false; }

LOG_GROUP_NAME="${SLI_OCI_LOG_URI%%/*}"
LOG_NAME="${SLI_OCI_LOG_URI#*/}"

# _oci_tenancy_ocid() from oci_scaffold: uses oci os ns get-metadata
TENANCY=$(_oci_tenancy_ocid)
[[ -z "$TENANCY" || "$TENANCY" == "null" ]] && { echo "ERROR: tenancy OCID not resolved — check OCI CLI DEFAULT profile"; false; }

# ensure-log_group.sh pattern: lookup by compartment + display-name
LOG_GROUP_OCID=$(oci logging log-group list \
  --compartment-id "$TENANCY" \
  --display-name "$LOG_GROUP_NAME" \
  --query 'data[0].id' --raw-output --profile DEFAULT 2>/dev/null)
[[ -z "$LOG_GROUP_OCID" || "$LOG_GROUP_OCID" == "null" ]] && { echo "ERROR: log group '$LOG_GROUP_NAME' not found"; false; }

# ensure-log.sh pattern: lookup by log-group + display-name
SLI_LOG_OCID=$(oci logging log list \
  --log-group-id "$LOG_GROUP_OCID" \
  --display-name "$LOG_NAME" \
  --query 'data[0].id' --raw-output --profile DEFAULT 2>/dev/null)
[[ -z "$SLI_LOG_OCID" || "$SLI_LOG_OCID" == "null" ]] && { echo "ERROR: log '$LOG_NAME' not found in group '$LOG_GROUP_NAME'"; false; }
# ──────────────────────────────────────────────────────────────────────────────

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
echo "=== T0b: OCI resource resolution (oci_scaffold URI-style) ==="
[[ "$TENANCY"       == ocid1.tenancy.*  ]] && pass "TENANCY resolved: $TENANCY"           || fail "TENANCY invalid"
[[ "$LOG_GROUP_OCID" == ocid1.loggroup.* ]] && pass "LOG_GROUP_OCID resolved: $LOG_GROUP_OCID" || fail "LOG_GROUP_OCID invalid"
[[ "$SLI_LOG_OCID"  == ocid1.log.*     ]] && pass "SLI_LOG_OCID resolved: $SLI_LOG_OCID" || fail "SLI_LOG_OCID invalid"

echo ""
echo "=== T1: unit tests — emit.sh helper functions ==="
UNIT_OUT=$(bash "${REPO_ROOT}/.github/actions/sli-event/tests/test_emit.sh" 2>&1)
UNIT_PASSED=$(echo "$UNIT_OUT" | grep -oE 'passed: [0-9]+' | grep -oE '[0-9]+')
UNIT_FAILED=$(echo "$UNIT_OUT" | grep -oE 'failed: [0-9]+'  | grep -oE '[0-9]+')
assert_eq "emit.sh unit tests: passed count" "$UNIT_PASSED" "19"
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
    elif echo "$LOG" | grep -q "Init — runner selection" && ! echo "$LOG" | grep -q "SLI"; then
      pass "run $RUN_ID / $JOB_NAME → init job (no SLI step expected)"
    else
      fail "run $RUN_ID / $JOB_NAME → unexpected SLI push outcome"
    fi
  done
done

echo ""
echo "=== T7: OCI Logging received events — query last 15 min ==="
sleep 30   # allow OCI ingestion latency
TS_START=$(date -u -v-15M '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u --date='-15 min' '+%Y-%m-%dT%H:%M:%SZ')
TS_END=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
EVENTS=$(oci logging-search search-logs \
  --search-query "search \"${TENANCY}/${LOG_GROUP_OCID}/${SLI_LOG_OCID}\" | sort by datetime desc | limit 50" \
  --time-start "$TS_START" --time-end "$TS_END" \
  --profile DEFAULT 2>/dev/null | jq '.data.results')

TOTAL=$(echo "$EVENTS" | jq 'length')
assert_ge "OCI received at least 12 events (4 runs × 3 jobs)" "$TOTAL" 12

SUCCESS_COUNT=$(echo "$EVENTS" | jq '[.[] | .data.logContent.data | if type=="string" then fromjson else . end | select(.outcome=="success")] | length')
FAILURE_COUNT=$(echo "$EVENTS" | jq '[.[] | .data.logContent.data | if type=="string" then fromjson else . end | select(.outcome=="failure")] | length')
assert_ge "OCI: at least 4 success outcome events" "$SUCCESS_COUNT" 4
assert_ge "OCI: at least 4 failure outcome events" "$FAILURE_COUNT" 4

CALL_EVENTS=$(echo "$EVENTS" | jq '[.[] | .data.logContent.data | if type=="string" then fromjson else . end | select(.workflow | test("API / UI call"))] | length')
PUSH_EVENTS=$(echo "$EVENTS" | jq '[.[] | .data.logContent.data | if type=="string" then fromjson else . end | select(.workflow | test("Push trigger"))] | length')
assert_ge "OCI: model-call events present" "$CALL_EVENTS" 3
assert_ge "OCI: model-push events present" "$PUSH_EVENTS" 3

FAIL_REASON_COUNT=$(echo "$EVENTS" | jq '[.[] | .data.logContent.data | if type=="string" then fromjson else . end | select(.failure_reasons | length > 0)] | length')
assert_ge "OCI: at least 4 failure events carry failure_reasons" "$FAIL_REASON_COUNT" 4

INIT_EVENTS=$(echo "$EVENTS" | jq '[.[] | .data.logContent.data | if type=="string" then fromjson else . end | select(.job=="sli-init")] | length')
assert_ge "OCI: sli-init job events present" "$INIT_EVENTS" 4

LEAF_EVENTS=$(echo "$EVENTS" | jq '[.[] | .data.logContent.data | if type=="string" then fromjson else . end | select(.job=="leaf")] | length')
assert_ge "OCI: leaf job events present" "$LEAF_EVENTS" 8

echo ""
echo "=== Summary ==="
echo "passed: $PASS  failed: $FAIL"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
