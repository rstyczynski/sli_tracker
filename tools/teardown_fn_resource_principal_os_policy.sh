#!/usr/bin/env bash
# teardown_fn_resource_principal_os_policy.sh — delete IAM policy + dynamic group from state
#
# Run with NAME_PREFIX set and state file present (e.g. before oci_scaffold/do/teardown.sh).
# Reads: oci_scaffold/state-${NAME_PREFIX}.json → .fn_rp_os.policy.ocid, .fn_rp_os.dynamic_group.ocid
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT/oci_scaffold"
# shellcheck source=../oci_scaffold/do/oci_scaffold.sh
source "$REPO_ROOT/oci_scaffold/do/oci_scaffold.sh"

: "${NAME_PREFIX:?NAME_PREFIX must be set}"

POLICY_OCID=$(_state_get '.fn_rp_os.policy.ocid')
DG_OCID=$(_state_get '.fn_rp_os.dynamic_group.ocid')

if [ -n "$POLICY_OCID" ] && [ "$POLICY_OCID" != "null" ]; then
  if oci iam policy delete --policy-id "$POLICY_OCID" --force >/dev/null 2>&1; then
    echo "  [INFO] Deleted IAM policy: $POLICY_OCID"
  else
    echo "  [WARN] IAM policy delete skipped or failed: $POLICY_OCID" >&2
  fi
fi

if [ -n "$DG_OCID" ] && [ "$DG_OCID" != "null" ]; then
  if oci iam dynamic-group delete --dynamic-group-id "$DG_OCID" --force >/dev/null 2>&1; then
    echo "  [INFO] Deleted dynamic group: $DG_OCID"
  else
    echo "  [WARN] Dynamic group delete skipped or failed: $DG_OCID" >&2
  fi
fi
