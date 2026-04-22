#!/usr/bin/env bash
# Integration test — OCI Console Dashboard deploy/verify/teardown.
# Sprint 32, SLI-64
#
# Prerequisites:
#   oci      — OCI CLI; profile DEFAULT (or DASHBOARD_TEST_OCI_PROFILE)
#   jq       — JSON processor
#   gh       — GitHub CLI, authenticated (to read SLI_OCI_LOG_ID, SLI_OCI_LOG_GROUP_ID)
#   oci_scaffold submodule present at <repo_root>/oci_scaffold
#
# Environment (all optional — defaults shown):
#   DASHBOARD_TEST_OCI_PROFILE   OCI CLI profile (default: DEFAULT)
#   DASHBOARD_TEST_NAME_PREFIX   Resource name prefix (default: sli-dash-test)
#   DASHBOARD_TEST_COMPARTMENT   Compartment OCID (default: read from state-${NAME_PREFIX}.json)
#   DASHBOARD_TEST_LOG_ID        Log OCID (default: gh variable SLI_OCI_LOG_ID)
#   DASHBOARD_TEST_LOG_GROUP_ID  Log group OCID (default: gh variable SLI_OCI_LOG_GROUP_ID)
#
# Usage (run from repo root):
#   bash tests/integration/test_dashboard.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

OCI_PROFILE="${DASHBOARD_TEST_OCI_PROFILE:-DEFAULT}"
export OCI_CLI_PROFILE="$OCI_PROFILE"

TEST_NAME_PREFIX="${DASHBOARD_TEST_NAME_PREFIX:-sli-dash-test}"
STATE_FILE_PATH="$REPO_ROOT/state-${TEST_NAME_PREFIX}.json"

passed=0
failed=0

_pass() { echo "PASS: $*"; ((passed += 1)) || true; }
_fail() { echo "FAIL: $*"; ((failed += 1)) || true; }

assert_eq() {
  local got="$1" want="$2" msg="$3"
  if [[ "$got" == "$want" ]]; then _pass "$msg"
  else _fail "$msg — want='$want' got='$got'"; fi
}

assert_not_empty() {
  local val="$1" msg="$2"
  if [[ -n "$val" ]] && [[ "$val" != "null" ]]; then _pass "$msg"
  else _fail "$msg — value is empty or null"; fi
}

# ── Precondition: OCI CLI auth ────────────────────────────────────────────────
echo "=== Precondition: OCI CLI auth ==="
if ! oci iam region list --output json >/dev/null 2>&1; then
  echo "SKIP: OCI CLI not authenticated (profile: $OCI_PROFILE)"
  exit 0
fi
_pass "OCI CLI authenticated (profile: $OCI_PROFILE)"

# ── Precondition: resolve log OCIDs ──────────────────────────────────────────
echo "=== Precondition: resolve log OCIDs ==="
if [[ -n "${DASHBOARD_TEST_LOG_ID:-}" ]]; then
  LOG_ID="$DASHBOARD_TEST_LOG_ID"
  LOG_GROUP_ID="$DASHBOARD_TEST_LOG_GROUP_ID"
  _pass "Log OCIDs from environment"
elif command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  repo="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)" || repo=""
  if [[ -n "$repo" ]]; then
    LOG_ID="$(gh variable get SLI_OCI_LOG_ID -R "$repo" 2>/dev/null)" || LOG_ID=""
    LOG_GROUP_ID="$(gh variable get SLI_OCI_LOG_GROUP_ID -R "$repo" 2>/dev/null)" || LOG_GROUP_ID=""
    _pass "Log OCIDs from gh variables ($repo)"
  else
    echo "SKIP: gh repo not found; set DASHBOARD_TEST_LOG_ID and DASHBOARD_TEST_LOG_GROUP_ID"
    exit 0
  fi
else
  echo "SKIP: gh CLI not available; set DASHBOARD_TEST_LOG_ID and DASHBOARD_TEST_LOG_GROUP_ID"
  exit 0
fi

if [[ -z "$LOG_ID" ]] || [[ -z "$LOG_GROUP_ID" ]]; then
  echo "SKIP: log OCIDs empty; set DASHBOARD_TEST_LOG_ID and DASHBOARD_TEST_LOG_GROUP_ID"
  exit 0
fi

OCI_REGION="$(echo "$LOG_ID" | cut -d. -f4)"

# ── Precondition: resolve compartment ────────────────────────────────────────
echo "=== Precondition: resolve compartment ==="
if [[ -n "${DASHBOARD_TEST_COMPARTMENT:-}" ]]; then
  COMPARTMENT_OCID="$DASHBOARD_TEST_COMPARTMENT"
  _pass "Compartment from environment"
elif [[ -f "$REPO_ROOT/state-sli-step6.json" ]]; then
  COMPARTMENT_OCID="$(jq -r '.compartment.ocid' "$REPO_ROOT/state-sli-step6.json")"
  _pass "Compartment from state-sli-step6.json"
else
  echo "SKIP: no compartment OCID; set DASHBOARD_TEST_COMPARTMENT"
  exit 0
fi

# ── Setup: source oci_scaffold and build test state ───────────────────────────
echo "=== Setup: initialise test state ==="
export NAME_PREFIX="$TEST_NAME_PREFIX"
# shellcheck source=../../oci_scaffold/do/oci_scaffold.sh
source "$REPO_ROOT/oci_scaffold/do/oci_scaffold.sh"

# Remove any leftover state from previous run
rm -f "$STATE_FILE_PATH"

_state_set '.inputs.name_prefix'                    "$TEST_NAME_PREFIX"
_state_set '.inputs.oci_compartment'                "$COMPARTMENT_OCID"
_state_set '.inputs.dashboard_tiles_file'           "$REPO_ROOT/etc/dashboard_sli_tracker.json"
_state_set '.inputs.dashboard_var_COMPARTMENT_OCID' "$COMPARTMENT_OCID"
_state_set '.inputs.dashboard_var_LOG_GROUP_OCID'   "$LOG_GROUP_ID"
_state_set '.inputs.dashboard_var_LOG_OCID'         "$LOG_ID"
_state_set '.inputs.dashboard_var_REGION_ID'        "$OCI_REGION"
_pass "Test state initialised"

# ── IT-1a: ensure dashboard group ────────────────────────────────────────────
echo "=== IT-1a: ensure_dashboard_group ==="
if bash "$REPO_ROOT/tools/ensure_dashboard_group.sh"; then
  _pass "IT-1a: ensure_dashboard_group exited 0"
else
  _fail "IT-1a: ensure_dashboard_group failed"
fi

DG_OCID="$(_state_get '.dashboard_group.ocid')"
assert_not_empty "$DG_OCID" "IT-1a: .dashboard_group.ocid written to state"

# Verify against OCI API
DG_NAME_OCI="$(oci dashboard-service dashboard-group get \
  --dashboard-group-id "$DG_OCID" \
  --query 'data."display-name"' --raw-output 2>/dev/null)" || DG_NAME_OCI=""
assert_eq "$DG_NAME_OCI" "${TEST_NAME_PREFIX}-group" "IT-1a: OCI group display-name matches state"

# ── IT-1b: ensure dashboard ───────────────────────────────────────────────────
echo "=== IT-1b: ensure_dashboard ==="
if bash "$REPO_ROOT/tools/ensure_dashboard.sh"; then
  _pass "IT-1b: ensure_dashboard exited 0"
else
  _fail "IT-1b: ensure_dashboard failed"
fi

DASH_OCID="$(_state_get '.dashboard.ocid')"
assert_not_empty "$DASH_OCID" "IT-1b: .dashboard.ocid written to state"

DEPLOYED="$(_state_get '.dashboard.deployed')"
assert_eq "$DEPLOYED" "true" "IT-1b: .dashboard.deployed is true"

# Verify name against OCI API
DASH_NAME_OCI="$(oci dashboard-service dashboard get-dashboard-v1 \
  --dashboard-id "$DASH_OCID" \
  --query 'data."display-name"' --raw-output 2>/dev/null)" || DASH_NAME_OCI=""
assert_eq "$DASH_NAME_OCI" "${TEST_NAME_PREFIX}-dashboard" "IT-1b: OCI dashboard display-name matches state"

# Verify widgets are non-empty
WIDGET_COUNT="$(oci dashboard-service dashboard get-dashboard-v1 \
  --dashboard-id "$DASH_OCID" \
  --query 'length(data.widgets)' --raw-output 2>/dev/null)" || WIDGET_COUNT="0"
if [[ "$WIDGET_COUNT" -gt 0 ]]; then _pass "IT-1b: dashboard has $WIDGET_COUNT widget(s)"
else _fail "IT-1b: dashboard has no widgets"; fi

# ── IT-1c: idempotency — re-run must not error ────────────────────────────────
echo "=== IT-1c: idempotency ==="
if bash "$REPO_ROOT/tools/ensure_dashboard_group.sh" && bash "$REPO_ROOT/tools/ensure_dashboard.sh"; then
  _pass "IT-1c: second run exits 0 (idempotent)"
else
  _fail "IT-1c: second run failed"
fi

DASH_OCID2="$(_state_get '.dashboard.ocid')"
assert_eq "$DASH_OCID2" "$DASH_OCID" "IT-1c: dashboard OCID unchanged on second run"

# ── IT-1d: teardown ───────────────────────────────────────────────────────────
echo "=== IT-1d: teardown ==="
if bash "$REPO_ROOT/tools/teardown_dashboard.sh"; then
  _pass "IT-1d: teardown_dashboard exited 0"
else
  _fail "IT-1d: teardown_dashboard failed"
fi

if bash "$REPO_ROOT/tools/teardown_dashboard_group.sh"; then
  _pass "IT-1d: teardown_dashboard_group exited 0"
else
  _fail "IT-1d: teardown_dashboard_group failed"
fi

# Verify resources are gone (expect OCI CLI to return error or null)
DASH_GONE="$(oci dashboard-service dashboard get-dashboard-v1 \
  --dashboard-id "$DASH_OCID" \
  --query 'data.id' --raw-output 2>/dev/null)" || DASH_GONE=""
if [[ -z "$DASH_GONE" ]] || [[ "$DASH_GONE" == "null" ]]; then
  _pass "IT-1d: dashboard no longer exists in OCI"
else
  _fail "IT-1d: dashboard still exists after teardown: $DASH_GONE"
fi

DG_GONE="$(oci dashboard-service dashboard-group get \
  --dashboard-group-id "$DG_OCID" \
  --query 'data.id' --raw-output 2>/dev/null)" || DG_GONE=""
if [[ -z "$DG_GONE" ]] || [[ "$DG_GONE" == "null" ]]; then
  _pass "IT-1d: dashboard group no longer exists in OCI"
else
  _fail "IT-1d: dashboard group still exists after teardown: $DG_GONE"
fi

# ── Cleanup ───────────────────────────────────────────────────────────────────
rm -f "$STATE_FILE_PATH"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "Results: $passed passed, $failed failed"
[[ $failed -eq 0 ]]
