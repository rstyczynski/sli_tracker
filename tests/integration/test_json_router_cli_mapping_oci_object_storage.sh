#!/usr/bin/env bash
# Integration test: json_router_cli loads mappings from OCI Object Storage when routing.json defines mapping.
# Uses oci_scaffold to ensure /SLI_tracker compartment and a bucket.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

OCI_INT_PROFILE="${SLI_INTEGRATION_OCI_PROFILE:-DEFAULT}"
export OCI_CLI_PROFILE="$OCI_INT_PROFILE"

PASS=0
FAIL=0

ok()   { echo "[PASS] $1"; PASS=$((PASS+1)); }
fail() { echo "[FAIL] $1"; FAIL=$((FAIL+1)); }

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then ok "$label"; else
    fail "$label"
    echo "       expected: $expected"
    echo "       actual:   $actual"
  fi
}

echo "=== Gate: OCI CLI auth (profile=$OCI_INT_PROFILE) ==="
oci iam region list --profile "$OCI_INT_PROFILE" >/dev/null 2>&1 && ok "oci cli profile works" || {
  echo "OCI auth failed for profile '$OCI_INT_PROFILE'." >&2
  exit 1
}

echo ""
echo "=== Ensure resources: /SLI_tracker compartment + bucket ==="
cd "$REPO_ROOT"
TS="$(date -u '+%Y%m%d%H%M%S')"
NAME_PREFIX="sli-cli-map-${TS}"
export NAME_PREFIX
source "${REPO_ROOT}/tools/ensure_oci_resources.sh"
ensure_sli_mapping_bucket "$REPO_ROOT" "$OCI_INT_PROFILE" "$NAME_PREFIX" "/SLI_tracker"
[[ -n "${MAPPING_BUCKET_NAME:-}" ]] && ok "bucket ready: $MAPPING_BUCKET_NAME" || fail "bucket missing"

echo ""
echo "=== Upload mapping into bucket ==="
node - <<'NODE'
const fs = require('fs');
const path = require('path');
const common = require('oci-common');
const objectstorage = require('oci-objectstorage');

(async () => {
  const profile = process.env.OCI_CLI_PROFILE || 'DEFAULT';
  const bucketName = process.env.MAPPING_BUCKET_NAME;
  const mappingKey = 'mapping_log.jsonata';
  const objectName = `jsonata/${mappingKey}`;

  const provider = new common.ConfigFileAuthenticationDetailsProvider(undefined, profile);
  const client = new objectstorage.ObjectStorageClient({ authenticationDetailsProvider: provider });
  const namespaceName = (await client.getNamespace({})).value;

  const fx = path.join(process.cwd(), 'tests/fixtures/router_destinations/ut111_mixed_destinations');
  const body = fs.readFileSync(path.join(fx, mappingKey), 'utf8');
  await client.putObject({
    namespaceName,
    bucketName,
    objectName,
    putObjectBody: body,
    contentType: 'application/json'
  });
})().catch((err) => { process.stderr.write(String(err.message) + '\n'); process.exit(1); });
NODE
ok "mapping uploaded"

echo ""
echo "=== Run CLI with routing.json that has mapping but no local mapping file ==="
tmp_dir="$(mktemp -d /tmp/sli_cli_map.XXXXXX)"
fx="${REPO_ROOT}/tests/fixtures/router_destinations/ut111_mixed_destinations"
cp "${fx}/source/001_workflow_run.json" "${tmp_dir}/envelope.json"

# routing.json in a temp dir WITHOUT mapping files (so local fallback would fail).
cat > "${tmp_dir}/routing.json" <<EOF
{
  "adapters": {
    "oci_object_storage:mappings": { "bucket": "${MAPPING_BUCKET_NAME}", "prefix": "jsonata/" }
  },
  "mapping": { "type": "oci_object_storage", "name": "mappings" },
  "routes": [
    {
      "id": "workflow_to_logging",
      "match": { "headers": { "X-GitHub-Event": "workflow_run" } },
      "transform": { "mapping": "./mapping_log.jsonata" },
      "destination": { "type": "oci_logging", "name": "github_events" }
    }
  ]
}
EOF

out="$(node "${REPO_ROOT}/tools/json_router_cli.js" --routing "${tmp_dir}/routing.json" --input "${tmp_dir}/envelope.json")"
assert_eq "IT-2 CLI fetched mapping from OCI and transformed envelope" \
  '{"routes":[{"id":"workflow_to_logging","mode":"exclusive","destination":{"type":"oci_logging","name":"github_events"},"output":{"kind":"log","repo":"acme/repo","outcome":"success"}}]}' "$out"

rm -rf "$tmp_dir"

echo ""
echo "=== Summary ==="
echo "passed: $PASS  failed: $FAIL"
[[ "$FAIL" -eq 0 ]]

