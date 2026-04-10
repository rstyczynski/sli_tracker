#!/usr/bin/env bash
# 1) source: local filesystem, target: bucket, map: local filesystem

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
OCI_PROFILE="${SLI_INTEGRATION_OCI_PROFILE:-DEFAULT}"
export OCI_CLI_PROFILE="$OCI_PROFILE"

echo "=== Gate: OCI auth (profile=$OCI_PROFILE) ==="
oci iam region list --profile "$OCI_PROFILE" >/dev/null 2>&1

cd "$REPO_ROOT"
TS="$(date -u '+%Y%m%d%H%M%S')"
NAME_PREFIX="sli-flow1-${TS}"
export NAME_PREFIX
source "${REPO_ROOT}/tools/ensure_oci_resources.sh"
ensure_sli_bucket "$REPO_ROOT" "$OCI_PROFILE" "$NAME_PREFIX" "/SLI_tracker"
DATA_BUCKET="$BUCKET_NAME"
DATA_NS="$BUCKET_NAMESPACE"

tmp_dir="$(mktemp -d /tmp/sli_flow1.XXXXXX)"
fx="${REPO_ROOT}/tests/fixtures/router_destinations/ut111_mixed_destinations"
mkdir -p "${tmp_dir}/source"
cp "${fx}/source/001_workflow_run.json" "${tmp_dir}/source/001_workflow_run.json"
cp "${fx}/mapping_log.jsonata" "${tmp_dir}/mapping_log.jsonata"

cat > "${tmp_dir}/routing.json" <<EOF
{
  "adapters": {
    "file_system:source": { "directory": "./source" },
    "oci_object_storage:raw_events": { "bucket": "${DATA_BUCKET}", "prefix": "out/" }
  },
  "source": { "type": "file_system", "name": "source" },
  "routes": [
    {
      "id": "workflow_to_bucket",
      "match": { "headers": { "X-GitHub-Event": "workflow_run" } },
      "transform": { "mapping": "./mapping_log.jsonata" },
      "destination": { "type": "oci_object_storage", "name": "raw_events" }
    }
  ]
}
EOF

OUT_DIR="$(mktemp -d /tmp/sli_flow1_out.XXXXXX)"
ROUTING_JSON="${tmp_dir}/routing.json" OUT_DIR="$OUT_DIR" node "${REPO_ROOT}/tests/integration/run_config_driven_flow.js" >/dev/null

# Verify object landed in the bucket
oci os object get --profile "$OCI_PROFILE" \
  --namespace-name "$DATA_NS" \
  --bucket-name "$DATA_BUCKET" \
  --name "out/001_workflow_run.json" \
  --file /dev/stdout >/dev/null 2>&1 || {
    echo "FAIL: expected object out/001_workflow_run.json not found" >&2
    exit 1
  }

rm -rf "$tmp_dir"
rm -rf "$OUT_DIR"
echo "PASS"

