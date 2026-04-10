#!/usr/bin/env bash
# 3) source: bucket, target: local filesystem, map: bucket

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

export NAME_PREFIX="sli-flow3-map-${TS}"
ensure_sli_bucket "$REPO_ROOT" "$OCI_PROFILE" "$NAME_PREFIX" "/SLI_tracker"
MAP_BUCKET="$BUCKET_NAME"
# shellcheck disable=SC2034
MAP_NS="$BUCKET_NAMESPACE"

export NAME_PREFIX="sli-flow3-src-${TS}"
ensure_sli_bucket "$REPO_ROOT" "$OCI_PROFILE" "$NAME_PREFIX" "/SLI_tracker"
SRC_BUCKET="$BUCKET_NAME"
# shellcheck disable=SC2034
SRC_NS="$BUCKET_NAMESPACE"

tmp_dir="$(mktemp -d /tmp/sli_flow3.XXXXXX)"
out_dir="$(mktemp -d /tmp/sli_flow3_out.XXXXXX)"
fx="${REPO_ROOT}/tests/fixtures/router_destinations/ut111_mixed_destinations"

# Upload mapping into mapping bucket (configuration refers to it)
oci os object put --profile "$OCI_PROFILE" \
  --namespace-name "$MAP_NS" \
  --bucket-name "$MAP_BUCKET" \
  --name "jsonata/mapping_log.jsonata" \
  --file "${fx}/mapping_log.jsonata" >/dev/null

# Upload source envelope into source bucket (configuration refers to it)
oci os object put --profile "$OCI_PROFILE" \
  --namespace-name "$SRC_NS" \
  --bucket-name "$SRC_BUCKET" \
  --name "source/001_workflow_run.json" \
  --file "${fx}/source/001_workflow_run.json" >/dev/null

cat > "${tmp_dir}/routing.json" <<EOF
{
  "adapters": {
    "oci_object_storage:mappings": { "bucket": "${MAP_BUCKET}", "prefix": "jsonata/" },
    "oci_object_storage:source": { "bucket": "${SRC_BUCKET}", "prefix": "source/" },
    "file_system:out": { "directory": "out" }
  },
  "source": { "type": "oci_object_storage", "name": "source" },
  "mapping": { "type": "oci_object_storage", "name": "mappings" },
  "routes": [
    {
      "id": "workflow_to_file",
      "match": { "headers": { "X-GitHub-Event": "workflow_run" } },
      "transform": { "mapping": "./mapping_log.jsonata" },
      "destination": { "type": "file_system", "name": "out" }
    }
  ]
}
EOF

OUT_DIR="$out_dir" ROUTING_JSON="${tmp_dir}/routing.json" node "${REPO_ROOT}/tests/integration/run_config_driven_flow.js" >/dev/null

test -f "${out_dir}/out/001_workflow_run.json" || { echo "FAIL: expected output file missing" >&2; exit 1; }

rm -rf "$tmp_dir"
rm -rf "$out_dir"
echo "PASS"

