#!/usr/bin/env bash
# ensure_dashboard.sh — idempotent OCI Dashboard Service dashboard creation
#
# Based on oci_scaffold/resource/ensure-dashboard.sh, extended with:
#   - dashboard_var_* generic substitution (__KEY__ → value) applied to the tiles file
#   - OCI Console export format support: {"widgets":[...]} unwrapped to plain array
#
# This local version is a staging ground for upstream promotion to oci_scaffold.
#
# Discovery order (same as oci_scaffold):
#   A. .inputs.dashboard_ocid       — adopt by OCID
#   B. .inputs.dashboard_uri        — /compartment/path/group-name/dashboard-name
#   C. .inputs.dashboard_name + .dashboard_group.ocid from state
#   D. name_prefix fallback: {name_prefix}-dashboard
#
# Widget definitions:
#   .inputs.dashboard_tiles_b64   — base64-encoded JSON (OCI export or plain array)
#   .inputs.dashboard_tiles_file  — path to JSON file  (OCI export or plain array)
#
# Variable substitution (applied before deploying widgets):
#   .inputs.dashboard_var_KEY → replaces __KEY__ in the tiles file
#   Any number of dashboard_var_* keys are supported.
#
# Outputs written to state (same as oci_scaffold):
#   .dashboard.name      display name
#   .dashboard.ocid      OCI dashboard OCID
#   .dashboard.created   true (created) | false (adopted)
#   .dashboard.deployed  true (widgets applied) | false (no tiles file provided)

set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../oci_scaffold/do/oci_scaffold.sh
source "$REPO_ROOT/oci_scaffold/do/oci_scaffold.sh"

EXISTS=""
DASHBOARD_NAME=""
DASHBOARD_OCID=""
GROUP_OCID=""

# ── lookup helpers ────────────────────────────────────────────────────────────
_dashboard_lookup() {
  local name="$1" group="$2"
  oci dashboard-service dashboard list-dashboards \
    --dashboard-group-id "$group" \
    --display-name "$name" \
    --lifecycle-state ACTIVE \
    --query 'data.items[0].id' --raw-output 2>/dev/null || true
}

_group_lookup() {
  local name="$1" compartment="$2"
  oci dashboard-service dashboard-group list-dashboard-groups \
    --compartment-id "$compartment" \
    --display-name "$name" \
    --lifecycle-state ACTIVE \
    --query 'data.items[0].id' --raw-output 2>/dev/null || true
}

#
# Path A: adopt by OCID
#
OCID_INPUT=$(_state_get '.inputs.dashboard_ocid')
if [ -n "$OCID_INPUT" ] && [ "$OCID_INPUT" != "null" ]; then
  RESULT=$(oci dashboard-service dashboard get \
    --dashboard-id "$OCID_INPUT" \
    --query 'data."display-name"' --raw-output 2>/dev/null) || true
  if [ -z "$RESULT" ] || [ "$RESULT" = "null" ]; then
    _fail "Dashboard not found: $OCID_INPUT"
    exit 1
  fi
  DASHBOARD_NAME="$RESULT"
  DASHBOARD_OCID="$OCID_INPUT"
  EXISTS="$DASHBOARD_NAME"
fi

#
# Path B: resolve from URI (/compartment/path/group-name/dashboard-name)
#
DASHBOARD_URI=$(_state_get '.inputs.dashboard_uri')
if [ -z "$EXISTS" ] && [ -n "$DASHBOARD_URI" ] && [ "$DASHBOARD_URI" != "null" ]; then
  _uri="${DASHBOARD_URI%/}"
  DASHBOARD_NAME="${_uri##*/}"
  _remainder="${_uri%/*}"
  URI_GROUP_NAME="${_remainder##*/}"
  URI_COMPARTMENT_PATH="${_remainder%/*}"

  if [ -z "$DASHBOARD_NAME" ] || [ -z "$URI_GROUP_NAME" ]; then
    _fail "Invalid dashboard_uri (expected /compartment/path/group-name/dashboard-name): $DASHBOARD_URI"
    exit 1
  fi

  if [ -n "$URI_COMPARTMENT_PATH" ] && [ "$URI_COMPARTMENT_PATH" != "/" ]; then
    URI_COMPARTMENT_OCID=$(_oci_compartment_ocid_by_path "$URI_COMPARTMENT_PATH")
  else
    URI_COMPARTMENT_OCID=$(_oci_tenancy_ocid)
  fi
  if [ -z "$URI_COMPARTMENT_OCID" ] || [ "$URI_COMPARTMENT_OCID" = "null" ]; then
    _fail "Compartment not found: $URI_COMPARTMENT_PATH"
    exit 1
  fi

  URI_GROUP_OCID=$(_group_lookup "$URI_GROUP_NAME" "$URI_COMPARTMENT_OCID")
  if [ -z "$URI_GROUP_OCID" ] || [ "$URI_GROUP_OCID" = "null" ]; then
    _fail "Dashboard group not found: $URI_GROUP_NAME in $URI_COMPARTMENT_PATH"
    exit 1
  fi
  GROUP_OCID="$URI_GROUP_OCID"

  FOUND=$(_dashboard_lookup "$DASHBOARD_NAME" "$GROUP_OCID")
  if [ -n "$FOUND" ] && [ "$FOUND" != "null" ]; then
    DASHBOARD_OCID="$FOUND"
    EXISTS="$DASHBOARD_NAME"
  fi
fi

# ── resolve GROUP_OCID for Paths C and D ─────────────────────────────────────
if [ -z "$GROUP_OCID" ]; then
  GROUP_OCID=$(_state_get '.dashboard_group.ocid')
fi
if [ -z "$GROUP_OCID" ] || [ "$GROUP_OCID" = "null" ]; then
  GROUP_OCID=$(_state_get '.inputs.dashboard_group_ocid')
fi

#
# Path C: lookup by name in group
#
if [ -z "$EXISTS" ]; then
  _input=$(_state_get '.inputs.dashboard_name')
  [ -n "$_input" ] && [ "$_input" != "null" ] && DASHBOARD_NAME="$_input"

  if [ -n "$DASHBOARD_NAME" ] && [ -n "$GROUP_OCID" ] && [ "$GROUP_OCID" != "null" ]; then
    FOUND=$(_dashboard_lookup "$DASHBOARD_NAME" "$GROUP_OCID")
    if [ -n "$FOUND" ] && [ "$FOUND" != "null" ]; then
      DASHBOARD_OCID="$FOUND"
      EXISTS="$DASHBOARD_NAME"
    fi
  fi
fi

#
# Path D: name_prefix fallback
#
if [ -z "$DASHBOARD_NAME" ]; then
  NAME_PREFIX=$(_state_get '.inputs.name_prefix')
  _require_env NAME_PREFIX
  DASHBOARD_NAME="${NAME_PREFIX}-dashboard"
fi

# ── load tiles with dashboard_var_* substitution ─────────────────────────────
WIDGETS_JSON=""
TILES_FILE=$(_state_get_file dashboard_tiles)
if [ -n "$TILES_FILE" ] && [ -f "$TILES_FILE" ]; then
  _SUBST_TMP=$(mktemp /tmp/dashboard-tiles.XXXXXX.json)
  trap 'rm -f "$_SUBST_TMP"' EXIT

  # Build sed args from all .inputs.dashboard_var_* state keys
  # Fails immediately on empty or null values — a missing value means broken widgets.
  SED_ARGS=()
  while IFS=$'\t' read -r var_name value; do
    [ -z "$var_name" ] && continue
    if [ -z "$value" ] || [ "$value" = "null" ]; then
      _fail "dashboard_var_${var_name} is empty or null — set it in state before deploying"
      exit 1
    fi
    SED_ARGS+=(-e "s|__${var_name}__|${value}|g")
  done < <(jq -r '
    .inputs // {} |
    to_entries[] |
    select(.key | startswith("dashboard_var_")) |
    [(.key | ltrimstr("dashboard_var_")), (.value // "")] |
    @tsv' "$STATE_FILE")

  if [ ${#SED_ARGS[@]} -gt 0 ]; then
    sed "${SED_ARGS[@]}" "$TILES_FILE" > "$_SUBST_TMP"
  else
    cp "$TILES_FILE" "$_SUBST_TMP"
  fi

  # Fail if any __KEY__ placeholders remain unsubstituted after sed pass
  remaining=$(grep -oP '__[A-Z0-9_]+__' "$_SUBST_TMP" | sort -u | tr '\n' ' ') || true
  if [ -n "$remaining" ]; then
    _fail "Unsubstituted placeholders remain in tiles file: ${remaining}— add matching .inputs.dashboard_var_* keys to state"
    exit 1
  fi

  # Support OCI Console export format {"widgets":[...]} and plain array [...]
  WIDGETS_JSON=$(jq -c 'if type == "object" and has("widgets") then .widgets else . end' "$_SUBST_TMP")
fi

#
# Creation — requires GROUP_OCID
#
if [ -z "$EXISTS" ]; then
  if [ -z "$GROUP_OCID" ] || [ "$GROUP_OCID" = "null" ]; then
    _fail "Dashboard group OCID not resolved. Run oci_scaffold/resource/ensure-dashboard_group.sh first."
    exit 1
  fi

  DASHBOARD_OCID=$(oci dashboard-service dashboard create-dashboard-v1 \
    --dashboard-group-id "$GROUP_OCID" \
    --display-name "$DASHBOARD_NAME" \
    --description "SLI Tracker dashboard: $DASHBOARD_NAME" \
    --widgets "${WIDGETS_JSON:-[]}" \
    --query 'data.id' --raw-output)

  _done "Dashboard created: $DASHBOARD_NAME"
  _state_set '.dashboard.created' true
  _state_set '.dashboard.deleted' false
  _state_set '.dashboard.deployed' "$([ -n "$WIDGETS_JSON" ] && echo true || echo false)"
else
  _existing "Dashboard: $DASHBOARD_NAME"
  _state_set '.dashboard.created' false
  _state_set '.dashboard.deleted' false

  if [ -n "$WIDGETS_JSON" ]; then
    oci dashboard-service dashboard update-dashboard-v1 \
      --dashboard-id "$DASHBOARD_OCID" \
      --widgets "$WIDGETS_JSON" \
      --force >/dev/null
    _done "Dashboard widgets deployed: $DASHBOARD_NAME"
    _state_set '.dashboard.deployed' true
  else
    _state_set '.dashboard.deployed' false
  fi
fi

_state_set '.dashboard.name' "$DASHBOARD_NAME"
_state_set '.dashboard.ocid' "$DASHBOARD_OCID"
_state_append_once '.meta.creation_order' '"dashboard"'
