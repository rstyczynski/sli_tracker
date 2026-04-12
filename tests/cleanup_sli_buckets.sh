#!/usr/bin/env bash
# Deletes all OCI Object Storage buckets in compartment /SLI_tracker
# whose name starts with "sli-". Also deletes all objects within each bucket.
#
# Safety: hardcoded compartment path and prefix per project convention.
#
# Related (sprint-end / manual only): remove router + API GW + Fn stack with
#   ./tests/cleanup_router_apigw_stack.sh
#   (or NAME_PREFIX=... ./tools/teardown_router_apigw_stack.sh)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

COMPARTMENT_PATH="/SLI_tracker"
BUCKET_PREFIX="sli-"
OCI_PROFILE="${OCI_CLI_PROFILE:-${SLI_INTEGRATION_OCI_PROFILE:-DEFAULT}}"

command -v oci >/dev/null 2>&1 || { echo "ERROR: oci CLI not found" >&2; exit 1; }
command -v jq  >/dev/null 2>&1 || { echo "ERROR: jq not found" >&2; exit 1; }

echo "=== cleanup_sli_buckets.sh ==="
echo "Profile          : $OCI_PROFILE"
echo "Compartment path : $COMPARTMENT_PATH"
echo "Bucket prefix    : $BUCKET_PREFIX"
echo ""

# Resolve compartment OCID using oci_scaffold helper (path -> OCID).
# shellcheck source=../oci_scaffold/do/oci_scaffold.sh
export OCI_CLI_PROFILE="$OCI_PROFILE"
export NAME_PREFIX="sli_cleanup_buckets"
cd "$SCRIPT_DIR"
source "${REPO_ROOT}/oci_scaffold/do/oci_scaffold.sh"

COMPARTMENT_OCID="$(_oci_compartment_ocid_by_path "$COMPARTMENT_PATH")"
[[ -z "${COMPARTMENT_OCID:-}" || "${COMPARTMENT_OCID:-}" == "null" ]] && {
  echo "ERROR: compartment not found: $COMPARTMENT_PATH" >&2
  exit 1
}

NAMESPACE="$(oci os ns get --profile "$OCI_PROFILE" --query 'data' --raw-output)"
[[ -z "${NAMESPACE:-}" || "${NAMESPACE:-}" == "null" ]] && {
  echo "ERROR: cannot resolve Object Storage namespace" >&2
  exit 1
}

echo "Compartment OCID: $COMPARTMENT_OCID"
echo "Namespace       : $NAMESPACE"
echo ""

mapfile -t buckets < <(
  oci os bucket list \
    --profile "$OCI_PROFILE" \
    --namespace-name "$NAMESPACE" \
    --compartment-id "$COMPARTMENT_OCID" \
    --all | jq -r --arg p "$BUCKET_PREFIX" '.data[].name | select(startswith($p))'
)

if [[ "${#buckets[@]}" -eq 0 ]]; then
  echo "No buckets found with prefix '${BUCKET_PREFIX}' in ${COMPARTMENT_PATH}."
  exit 0
fi

echo "Buckets to delete (${#buckets[@]}):"
for b in "${buckets[@]}"; do
  echo "  - $b"
done
echo ""

for bucket in "${buckets[@]}"; do
  echo "=== Bucket: $bucket ==="

  # Bulk-delete all objects in the bucket (no prefix == everything).
  # This is idempotent: if the bucket is already empty, it becomes a no-op.
  oci os object bulk-delete \
    --profile "$OCI_PROFILE" \
    --namespace-name "$NAMESPACE" \
    --bucket-name "$bucket" \
    --force >/dev/null
  echo "Deleted objects."

  oci os bucket delete \
    --profile "$OCI_PROFILE" \
    --namespace-name "$NAMESPACE" \
    --bucket-name "$bucket" \
    --force >/dev/null

  echo "Deleted bucket."
  echo ""
done

echo "DONE"

