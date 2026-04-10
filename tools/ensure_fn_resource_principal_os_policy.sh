#!/usr/bin/env bash
# ensure_fn_resource_principal_os_policy.sh — IAM: OCI Functions resource principals → Object Storage
#
# Creates a dynamic group matching fnfunc resources in the scaffold compartment and a tenancy
# policy allowing that group to manage objects in the same compartment.
#
# Intended to be run while cwd and STATE_FILE match oci_scaffold (e.g. from
# tools/cycle_apigw_router_passthrough.sh). Sources oci_scaffold helpers only.
#
# Reads from state.json:
#   .inputs.oci_compartment   (required)
#   .inputs.name_prefix       (required)
#
# Optional environment:
#   FN_OS_POLICY_SKIP=true    — skip (tenant already grants access)
#
# Writes to state.json:
#   .fn_rp_os.dynamic_group.ocid
#   .fn_rp_os.policy.ocid
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT/oci_scaffold"
# shellcheck source=../oci_scaffold/do/oci_scaffold.sh
source "$REPO_ROOT/oci_scaffold/do/oci_scaffold.sh"

if [ "${FN_OS_POLICY_SKIP:-}" = "true" ]; then
  _info "FN_OS_POLICY_SKIP=true — skipping Fn resource-principal Object Storage policy"
  exit 0
fi

COMPARTMENT_OCID=$(_state_get '.inputs.oci_compartment')
NAME_PREFIX=$(_state_get '.inputs.name_prefix')
_require_env COMPARTMENT_OCID NAME_PREFIX

TENANCY_OCID=$(_oci_tenancy_ocid)
_require_env TENANCY_OCID

DG_NAME="${NAME_PREFIX}-fn-rp-os-dg"
POLICY_NAME="${NAME_PREFIX}-fn-rp-os-policy"
RULE="ALL {resource.type = 'fnfunc', resource.compartment.id = '${COMPARTMENT_OCID}'}"

DG_OCID=$(oci iam dynamic-group list \
  --compartment-id "$TENANCY_OCID" \
  --all \
  --query "data[?name==\`$DG_NAME\`].id | [0]" \
  --raw-output 2>/dev/null) || true

if [ -z "$DG_OCID" ] || [ "$DG_OCID" = "null" ]; then
  DG_OCID=$(oci iam dynamic-group create \
    --compartment-id "$TENANCY_OCID" \
    --name "$DG_NAME" \
    --description "SLI_tracker: Fn functions in compartment may use resource principal for OS" \
    --matching-rule "$RULE" \
    --query 'data.id' --raw-output)
  _done "Dynamic group created: $DG_OCID ($DG_NAME)"
else
  _existing "Dynamic group '$DG_NAME': $DG_OCID"
fi

STATEMENT="ALLOW dynamic-group id ${DG_OCID} to manage objects in compartment id ${COMPARTMENT_OCID}"

POLICY_OCID=$(oci iam policy list \
  --compartment-id "$TENANCY_OCID" \
  --all \
  --query "data[?name==\`$POLICY_NAME\` && \"lifecycle-state\"==\`ACTIVE\`].id | [0]" \
  --raw-output 2>/dev/null) || true

if [ -z "$POLICY_OCID" ] || [ "$POLICY_OCID" = "null" ]; then
  POLICY_OCID=$(oci iam policy create \
    --compartment-id "$TENANCY_OCID" \
    --name "$POLICY_NAME" \
    --description "SLI_tracker: Fn resource principal → Object Storage in compartment" \
    --statements "$(printf '%s\n' "$STATEMENT" | jq -R . | jq -s .)" \
    --query 'data.id' --raw-output)
  _done "IAM policy created: $POLICY_OCID ($POLICY_NAME)"
else
  _existing "IAM policy '$POLICY_NAME': $POLICY_OCID"
fi

# Record OCIDs only under .fn_rp_os; never modify .meta.creation_order (oci_scaffold-managed).
_state_set '.fn_rp_os.dynamic_group.ocid' "$DG_OCID"
_state_set '.fn_rp_os.dynamic_group.name' "$DG_NAME"
_state_set '.fn_rp_os.policy.ocid' "$POLICY_OCID"
_state_set '.fn_rp_os.policy.name' "$POLICY_NAME"
