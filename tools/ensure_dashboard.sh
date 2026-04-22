#!/usr/bin/env bash
# ensure_dashboard.sh — OCI Console Dashboard (project-agnostic)
#
# Reads from state:
#   .inputs.name_prefix           (required)
#   .inputs.oci_compartment       (required)
#   .inputs.dashboard_template    (required — path to template JSON)
#   .inputs.dashboard_var_*       (any number — substituted as __KEY__ → value)
#
# Writes to state:
#   .dashboard.group.ocid / .dashboard.group.name
#   .dashboard.ocid       / .dashboard.name

set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../oci_scaffold/do/oci_scaffold.sh
source "$REPO_ROOT/oci_scaffold/do/oci_scaffold.sh"

NAME_PREFIX=$(_state_get '.inputs.name_prefix')
COMPARTMENT_OCID=$(_state_get '.inputs.oci_compartment')
TEMPLATE_FILE=$(_state_get '.inputs.dashboard_template')
_require_env NAME_PREFIX COMPARTMENT_OCID TEMPLATE_FILE
[ -f "$TEMPLATE_FILE" ] || { echo "  [ERROR] Template not found: $TEMPLATE_FILE" >&2; exit 1; }

DG_NAME="${NAME_PREFIX}-sli-tracker"
DASH_NAME="${NAME_PREFIX}-sli-tracker"

# ── Step 1: Ensure dashboard group ────────────────────────────────────────────
DG_OCID=$(oci dashboard-service dashboard-group list \
  --compartment-id "$COMPARTMENT_OCID" \
  --all \
  --query "data.items[?\"display-name\"==\`$DG_NAME\`].id | [0]" \
  --raw-output 2>/dev/null) || true

if [ -z "$DG_OCID" ] || [ "$DG_OCID" = "null" ]; then
  DG_OCID=$(oci dashboard-service dashboard-group create \
    --compartment-id "$COMPARTMENT_OCID" \
    --display-name "$DG_NAME" \
    --description "SLI Tracker dashboard group" \
    --query 'data.id' --raw-output)
  _done "Dashboard group created: $DG_OCID ($DG_NAME)"
else
  _existing "Dashboard group '$DG_NAME': $DG_OCID"
fi

# ── Step 2: Ensure dashboard ──────────────────────────────────────────────────
DASH_OCID=$(oci dashboard-service dashboard list \
  --dashboard-group-id "$DG_OCID" \
  --all \
  --query "data.items[?\"display-name\"==\`$DASH_NAME\`].id | [0]" \
  --raw-output 2>/dev/null) || true

if [ -z "$DASH_OCID" ] || [ "$DASH_OCID" = "null" ]; then
  TEMP_CONFIG=$(mktemp /tmp/dashboard-config.XXXXXX.json)
  trap 'rm -f "$TEMP_CONFIG"' EXIT

  # Build sed args from all .inputs.dashboard_var_* state keys
  SED_ARGS=()
  while IFS=$'\t' read -r var_name value; do
    [ -n "$var_name" ] && SED_ARGS+=(-e "s|__${var_name}__|${value}|g")
  done < <(jq -r '
    .inputs // {} |
    to_entries[] |
    select(.key | startswith("dashboard_var_")) |
    [(.key | ltrimstr("dashboard_var_")), .value] |
    @tsv' "$STATE_FILE")

  if [ ${#SED_ARGS[@]} -gt 0 ]; then
    sed "${SED_ARGS[@]}" "$TEMPLATE_FILE" > "$TEMP_CONFIG"
  else
    cp "$TEMPLATE_FILE" "$TEMP_CONFIG"
  fi

  DASH_OCID=$(oci dashboard-service dashboard create \
    --dashboard-group-id "$DG_OCID" \
    --display-name "$DASH_NAME" \
    --description "OCI Console Dashboard" \
    --config-details "file://$TEMP_CONFIG" \
    --query 'data.id' --raw-output)
  _done "Dashboard created: $DASH_OCID ($DASH_NAME)"
else
  _existing "Dashboard '$DASH_NAME': $DASH_OCID"
fi

# ── Step 3: Record in state ───────────────────────────────────────────────────
_state_set '.dashboard.group.ocid' "$DG_OCID"
_state_set '.dashboard.group.name' "$DG_NAME"
_state_set '.dashboard.ocid' "$DASH_OCID"
_state_set '.dashboard.name' "$DASH_NAME"
