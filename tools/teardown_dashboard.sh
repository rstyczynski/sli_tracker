#!/usr/bin/env bash
# teardown_dashboard.sh — delete OCI Console dashboard and dashboard group from state
#
# Run from the project root with NAME_PREFIX set and state-${NAME_PREFIX}.json present.
# Reads: state-${NAME_PREFIX}.json → .dashboard.ocid, .dashboard.group.ocid

set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../oci_scaffold/do/oci_scaffold.sh
source "$REPO_ROOT/oci_scaffold/do/oci_scaffold.sh"

: "${NAME_PREFIX:?NAME_PREFIX must be set}"

DASH_OCID=$(_state_get '.dashboard.ocid')
DG_OCID=$(_state_get '.dashboard.group.ocid')

if [ -n "$DASH_OCID" ] && [ "$DASH_OCID" != "null" ]; then
  if oci dashboard-service dashboard delete --dashboard-id "$DASH_OCID" --force >/dev/null 2>&1; then
    echo "  [INFO] Deleted dashboard: $DASH_OCID"
  else
    echo "  [WARN] Dashboard delete skipped or failed: $DASH_OCID" >&2
  fi
fi

if [ -n "$DG_OCID" ] && [ "$DG_OCID" != "null" ]; then
  if oci dashboard-service dashboard-group delete --dashboard-group-id "$DG_OCID" --force >/dev/null 2>&1; then
    echo "  [INFO] Deleted dashboard group: $DG_OCID"
  else
    echo "  [WARN] Dashboard group delete skipped or failed: $DG_OCID" >&2
  fi
fi
