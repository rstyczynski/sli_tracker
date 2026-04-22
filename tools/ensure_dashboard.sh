#!/usr/bin/env bash
# ensure_dashboard.sh — OCI Console Dashboard for SLI Tracker
#
# Usage: bash tools/ensure_dashboard.sh [TEMPLATE_FILE]
#
#   TEMPLATE_FILE  Path to dashboard JSON template.
#                  Default: $REPO_ROOT/etc/dashboard_sli_tracker.json
#                  Override: positional arg $1, or env var DASHBOARD_TEMPLATE
#
# Substitutes four placeholders before creating:
#   __COMPARTMENT_OCID__  → .inputs.oci_compartment
#   __LOG_GROUP_OCID__    → .log_group.ocid
#   __LOG_OCID__          → .log.ocid
#   __REGION_ID__         → home region from OCI
#
# Run from the project root with NAME_PREFIX set and state-${NAME_PREFIX}.json present.
#
# Writes to state:
#   .dashboard.group.ocid / .dashboard.group.name
#   .dashboard.ocid       / .dashboard.name

set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../oci_scaffold/do/oci_scaffold.sh
source "$REPO_ROOT/oci_scaffold/do/oci_scaffold.sh"

COMPARTMENT_OCID=$(_state_get '.inputs.oci_compartment')
NAME_PREFIX=$(_state_get '.inputs.name_prefix')
LOG_GROUP_OCID=$(_state_get '.log_group.ocid')
LOG_OCID=$(_state_get '.log.ocid')
_require_env COMPARTMENT_OCID NAME_PREFIX LOG_GROUP_OCID LOG_OCID

REGION_ID=$(oci iam region-subscription list \
  --query "data[?\"is-home-region\"==\`true\`].\"region-name\" | [0]" \
  --raw-output 2>/dev/null)
_require_env REGION_ID

TEMPLATE_FILE="${1:-${DASHBOARD_TEMPLATE:-$REPO_ROOT/etc/dashboard_sli_tracker.json}}"
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

  sed \
    -e "s|__COMPARTMENT_OCID__|${COMPARTMENT_OCID}|g" \
    -e "s|__LOG_GROUP_OCID__|${LOG_GROUP_OCID}|g" \
    -e "s|__LOG_OCID__|${LOG_OCID}|g" \
    -e "s|__REGION_ID__|${REGION_ID}|g" \
    "$TEMPLATE_FILE" > "$TEMP_CONFIG"

  DASH_OCID=$(oci dashboard-service dashboard create \
    --dashboard-group-id "$DG_OCID" \
    --display-name "$DASH_NAME" \
    --description "SLI Tracker — outcome events and computed SLI ratio" \
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
