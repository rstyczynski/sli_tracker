#!/usr/bin/env bash
# ensure_dashboard.sh — OCI Console Dashboard for SLI Tracker
#
# Creates an OCI Console dashboard group and dashboard from the template in etc/.
# On first run (template is empty) the config is fetched from the project source
# dashboard, generalized (source compartment replaced with __COMPARTMENT_OCID__),
# and saved to etc/dashboard_sli_tracker.json for version control.
#
# Run from the project root with NAME_PREFIX set and state-${NAME_PREFIX}.json present.
#
# Reads from state:
#   .inputs.oci_compartment   (required)
#   .inputs.name_prefix       (required)
#
# Writes to state:
#   .dashboard.group.ocid
#   .dashboard.group.name
#   .dashboard.ocid
#   .dashboard.name

set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../oci_scaffold/do/oci_scaffold.sh
source "$REPO_ROOT/oci_scaffold/do/oci_scaffold.sh"

COMPARTMENT_OCID=$(_state_get '.inputs.oci_compartment')
NAME_PREFIX=$(_state_get '.inputs.name_prefix')
_require_env COMPARTMENT_OCID NAME_PREFIX

SOURCE_DASHBOARD_ID="ocid1.consoledashboard.oc1..aaaaaaaaikoqfpryjfhxp2rulyn3t7kgtq3re3ft33kxp52yqymc3ptzqhya"
TEMPLATE_FILE="$REPO_ROOT/etc/dashboard_sli_tracker.json"
DG_NAME="${NAME_PREFIX}-sli-tracker"
DASH_NAME="${NAME_PREFIX}-sli-tracker"

# ── Step 1: Ensure template ────────────────────────────────────────────────────
# Template is empty ({}) on first clone; fetch config from source dashboard,
# replace source compartment with __COMPARTMENT_OCID__ placeholder, then save.
TEMPLATE_CONTENT=$(cat "$TEMPLATE_FILE" 2>/dev/null || echo '{}')
if [ "$TEMPLATE_CONTENT" = '{}' ] || [ -z "$TEMPLATE_CONTENT" ]; then
  _info "Template is empty — fetching config from source dashboard $SOURCE_DASHBOARD_ID"

  SOURCE_DATA=$(oci dashboard-service dashboard get \
    --dashboard-id "$SOURCE_DASHBOARD_ID" \
    --query 'data' --output json)

  SOURCE_COMPARTMENT=$(echo "$SOURCE_DATA" | jq -r '."compartment-id"')

  echo "$SOURCE_DATA" | jq \
    --arg src "$SOURCE_COMPARTMENT" \
    '."config-details" | walk(if type == "string" then gsub($src; "__COMPARTMENT_OCID__") else . end)' \
    > "$TEMPLATE_FILE"

  _done "Template saved: $TEMPLATE_FILE — commit this file to keep it in version control"
fi

# ── Step 2: Ensure dashboard group ────────────────────────────────────────────
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

# ── Step 3: Ensure dashboard ──────────────────────────────────────────────────
DASH_OCID=$(oci dashboard-service dashboard list \
  --dashboard-group-id "$DG_OCID" \
  --all \
  --query "data.items[?\"display-name\"==\`$DASH_NAME\`].id | [0]" \
  --raw-output 2>/dev/null) || true

if [ -z "$DASH_OCID" ] || [ "$DASH_OCID" = "null" ]; then
  TEMP_CONFIG=$(mktemp /tmp/dashboard-config.XXXXXX.json)
  trap 'rm -f "$TEMP_CONFIG"' EXIT
  sed "s|__COMPARTMENT_OCID__|${COMPARTMENT_OCID}|g" "$TEMPLATE_FILE" > "$TEMP_CONFIG"

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

# ── Step 4: Record in state ───────────────────────────────────────────────────
_state_set '.dashboard.group.ocid' "$DG_OCID"
_state_set '.dashboard.group.name' "$DG_NAME"
_state_set '.dashboard.ocid' "$DASH_OCID"
_state_set '.dashboard.name' "$DASH_NAME"
