#!/usr/bin/env bash
# 2) source: local filesystem, target: bucket, map: bucket

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
OCI_PROFILE="${SLI_INTEGRATION_OCI_PROFILE:-DEFAULT}"
export OCI_CLI_PROFILE="$OCI_PROFILE"

echo "=== Gate: OCI auth (profile=$OCI_PROFILE) ==="
oci iam region list --profile "$OCI_PROFILE" >/dev/null 2>&1

cd "$REPO_ROOT"
TS="$(date -u '+%Y%m%d%H%M%S')"

source "${REPO_ROOT}/tools/ensure_oci_resources.sh"

export NAME_PREFIX="sli-flow2-map-${TS}"
ensure_sli_bucket "$REPO_ROOT" "$OCI_PROFILE" "$NAME_PREFIX" "/SLI_tracker"
MAP_BUCKET="$BUCKET_NAME"
# shellcheck disable=SC2034
MAP_NS="$BUCKET_NAMESPACE"

export NAME_PREFIX="sli-flow2-data-${TS}"
ensure_sli_bucket "$REPO_ROOT" "$OCI_PROFILE" "$NAME_PREFIX" "/SLI_tracker"
DATA_BUCKET="$BUCKET_NAME"
# shellcheck disable=SC2034
DATA_NS="$BUCKET_NAMESPACE"

tmp_dir="$(mktemp -d /tmp/sli_flow2.XXXXXX)"
fx="${REPO_ROOT}/tests/fixtures/router_destinations/ut111_mixed_destinations"
mkdir -p "${tmp_dir}/source"
cp "${fx}/source/001_workflow_run.json" "${tmp_dir}/source/001_workflow_run.json"

# Upload mapping into mapping bucket (configuration refers to it)
oci os object put --profile "$OCI_PROFILE" \
  --namespace-name "$MAP_NS" \
  --bucket-name "$MAP_BUCKET" \
  --name "jsonata/mapping_log.jsonata" \
  --file "${fx}/mapping_log.jsonata" >/dev/null

cat > "${tmp_dir}/routing.json" <<EOF
{
  "adapters": {
    "file_system:source": { "directory": "./source" },
    "oci_object_storage:mappings": { "bucket": "${MAP_BUCKET}", "prefix": "jsonata/" },
    "oci_object_storage:raw_events": { "bucket": "${DATA_BUCKET}", "prefix": "out/" }
  },
  "source": { "type": "file_system", "name": "source" },
  "mapping": { "type": "oci_object_storage", "name": "mappings" },
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

OUT_DIR="$(mktemp -d /tmp/sli_flow2_out.XXXXXX)"
ROUTING_JSON="${tmp_dir}/routing.json" OUT_DIR="$OUT_DIR" node "${REPO_ROOT}/tests/integration/run_config_driven_flow.js" >/dev/null

# Verify object landed in the data bucket
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

