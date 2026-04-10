#!/usr/bin/env bash
# Complex config-driven flow:
# - source: file_system
# - map: file_system
# - targets: multiple OCI Object Storage prefixes + local file outputs
# - fanout + exclusive priority behavior

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

export NAME_PREFIX="sli-complex-${TS}"
ensure_sli_bucket "$REPO_ROOT" "$OCI_PROFILE" "$NAME_PREFIX" "/SLI_tracker"
DATA_BUCKET="$BUCKET_NAME"
DATA_NS="$BUCKET_NAMESPACE"

tmp_dir="$(mktemp -d /tmp/sli_complex.XXXXXX)"
out_dir="$(mktemp -d /tmp/sli_complex_out.XXXXXX)"
mkdir -p "${tmp_dir}/source"

fx="${REPO_ROOT}/tests/fixtures/router_destinations/ut111_mixed_destinations"
cp "${fx}/mapping_log.jsonata" "${tmp_dir}/mapping_log.jsonata"
cp "${fx}/mapping_metric.jsonata" "${tmp_dir}/mapping_metric.jsonata"
cp "${fx}/mapping_file.jsonata" "${tmp_dir}/mapping_file.jsonata"

# Envelopes: each one exercises a different route/mode.
cat > "${tmp_dir}/source/001_log.json" <<'EOF'
{
  "endpoint": "github",
  "headers": { "X-GitHub-Event": "workflow_run" },
  "body": {
    "kind": "log",
    "repo": "acme/repo",
    "outcome": "success"
  }
}
EOF

cat > "${tmp_dir}/source/002_metric.json" <<'EOF'
{
  "endpoint": "metrics",
  "headers": { "X-Source": "ci" },
  "body": {
    "kind": "metric",
    "name": "build_duration_ms",
    "value": 1234,
    "labels": { "repo": "acme/repo" }
  }
}
EOF

cat > "${tmp_dir}/source/003_message.json" <<'EOF'
{
  "endpoint": "messages",
  "headers": { "X-Channel": "slack" },
  "body": {
    "kind": "message",
    "text": "hello",
    "severity": "info"
  }
}
EOF

cat > "${tmp_dir}/source/004_fanout.json" <<'EOF'
{
  "endpoint": "fanout",
  "headers": { "X-Mode": "fanout" },
  "body": {
    "kind": "log",
    "repo": "acme/repo",
    "outcome": "success"
  }
}
EOF

cat > "${tmp_dir}/source/005_exclusive.json" <<'EOF'
{
  "endpoint": "exclusive",
  "headers": { "X-Mode": "exclusive" },
  "body": {
    "kind": "log",
    "repo": "acme/repo",
    "outcome": "success"
  }
}
EOF

cat > "${tmp_dir}/routing.json" <<EOF
{
  "adapters": {
    "file_system:source": { "directory": "./source" },
    "oci_object_storage:logs": { "bucket": "${DATA_BUCKET}", "prefix": "logs/" },
    "oci_object_storage:metrics": { "bucket": "${DATA_BUCKET}", "prefix": "metrics/" },
    "oci_object_storage:messages": { "bucket": "${DATA_BUCKET}", "prefix": "messages/" },
    "oci_object_storage:fanout": { "bucket": "${DATA_BUCKET}", "prefix": "fanout/" },
    "oci_object_storage:exclusive": { "bucket": "${DATA_BUCKET}", "prefix": "exclusive/" },
    "file_system:fanout": { "directory": "fanout" },
    "file_system:exclusive": { "directory": "exclusive" }
  },
  "source": { "type": "file_system", "name": "source" },
  "routes": [
    {
      "id": "to_logs_bucket",
      "priority": 10,
      "match": { "schema": { "path": "kind", "equals": "log" }, "endpoint": "github" },
      "transform": { "mapping": "./mapping_log.jsonata" },
      "destination": { "type": "oci_object_storage", "name": "logs" }
    },
    {
      "id": "to_metrics_bucket",
      "priority": 10,
      "match": { "schema": { "path": "kind", "equals": "metric" }, "endpoint": "metrics" },
      "transform": { "mapping": "./mapping_metric.jsonata" },
      "destination": { "type": "oci_object_storage", "name": "metrics" }
    },
    {
      "id": "to_messages_bucket",
      "priority": 10,
      "match": { "schema": { "path": "kind", "equals": "message" }, "endpoint": "messages" },
      "transform": { "mapping": "./mapping_file.jsonata" },
      "destination": { "type": "oci_object_storage", "name": "messages" }
    },
    {
      "id": "fanout_bucket",
      "mode": "fanout",
      "priority": 1,
      "match": { "endpoint": "fanout", "headers": { "X-Mode": "fanout" } },
      "transform": { "mapping": "./mapping_log.jsonata" },
      "destination": { "type": "oci_object_storage", "name": "fanout" }
    },
    {
      "id": "fanout_file",
      "mode": "fanout",
      "priority": 1,
      "match": { "endpoint": "fanout", "headers": { "X-Mode": "fanout" } },
      "transform": { "mapping": "./mapping_log.jsonata" },
      "destination": { "type": "file_system", "name": "fanout" }
    },
    {
      "id": "exclusive_to_file_higher_priority",
      "mode": "exclusive",
      "priority": 50,
      "match": { "endpoint": "exclusive", "headers": { "X-Mode": "exclusive" } },
      "transform": { "mapping": "./mapping_log.jsonata" },
      "destination": { "type": "file_system", "name": "exclusive" }
    },
    {
      "id": "exclusive_to_bucket_lower_priority",
      "mode": "exclusive",
      "priority": 5,
      "match": { "endpoint": "exclusive", "headers": { "X-Mode": "exclusive" } },
      "transform": { "mapping": "./mapping_log.jsonata" },
      "destination": { "type": "oci_object_storage", "name": "exclusive" }
    }
  ]
}
EOF

# Run via CLI using routing.json end-to-end runtime
(cd "$tmp_dir" && node "${REPO_ROOT}/tools/json_router_cli.js" --routing "${tmp_dir}/routing.json" >/dev/null)

# Verify bucket outputs exist (prefix + source file name is the contract)
for obj in \
  "logs/001_log.json" \
  "metrics/002_metric.json" \
  "messages/003_message.json" \
  "fanout/004_fanout.json"
do
  oci os object get --profile "$OCI_PROFILE" \
    --namespace-name "$DATA_NS" \
    --bucket-name "$DATA_BUCKET" \
    --name "$obj" \
    --file /dev/stdout >/dev/null 2>&1 || {
      echo "FAIL: expected object not found: $obj" >&2
      exit 1
    }
done

# Exclusive lower-priority bucket delivery must NOT happen
oci os object get --profile "$OCI_PROFILE" \
  --namespace-name "$DATA_NS" \
  --bucket-name "$DATA_BUCKET" \
  --name "exclusive/005_exclusive.json" \
  --file /dev/stdout >/dev/null 2>&1 && {
    echo "FAIL: exclusive bucket object should not exist (lower priority route must be suppressed)" >&2
    exit 1
  }

# Fanout must also write to filesystem
test -f "${tmp_dir}/fanout/004_fanout.json" || { echo "FAIL: expected fanout file missing" >&2; exit 1; }

# Exclusive must land only in filesystem (higher priority)
test -f "${tmp_dir}/exclusive/005_exclusive.json" || { echo "FAIL: expected exclusive file missing" >&2; exit 1; }

rm -rf "$tmp_dir"
rm -rf "$out_dir"
echo "PASS"

