#!/usr/bin/env bash
# Integration test: router mapping source fetched from OCI Object Storage.
# Uses oci_scaffold to ensure /SLI_tracker compartment and a bucket.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Profile convention matches other integration tests.
# User requirement: do not use --auth security_token for tests.
# Default to API-key profile DEFAULT.
OCI_INT_PROFILE="${SLI_INTEGRATION_OCI_PROFILE:-DEFAULT}"
export OCI_INT_PROFILE OCI_CLI_PROFILE="$OCI_INT_PROFILE"

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

echo "=== Gate: OCI CLI auth ==="
_sli_profile_ok() {
  local p="$1"
  oci iam region list --profile "$p" >/dev/null 2>&1
}

if ! _sli_profile_ok "$OCI_INT_PROFILE"; then
  echo "OCI auth failed for profile '$OCI_INT_PROFILE'."
  echo "Fix ~/.oci/config for that profile or export SLI_INTEGRATION_OCI_PROFILE to a working API-key profile."
  exit 1
else
  ok "oci cli profile works: $OCI_INT_PROFILE"
fi

echo ""
echo "=== Ensure resources: /SLI_tracker compartment + bucket ==="
cd "$REPO_ROOT"
TS="$(date -u '+%Y%m%d%H%M%S')"
NAME_PREFIX="sli-map-src-${TS}"
export NAME_PREFIX
source "${REPO_ROOT}/tools/ensure_oci_resources.sh"
ensure_sli_mapping_bucket "$REPO_ROOT" "$OCI_INT_PROFILE" "$NAME_PREFIX" "/SLI_tracker"

[[ "$COMPARTMENT_OCID" == ocid1.compartment.* ]] && ok "compartment resolved: $COMPARTMENT_OCID" || fail "compartment ocid invalid"
[[ -n "${MAPPING_BUCKET_NAME:-}" ]] && ok "bucket resolved: $MAPPING_BUCKET_NAME" || fail "bucket name missing"
[[ -n "${MAPPING_BUCKET_NAMESPACE:-}" ]] && ok "namespace resolved" || fail "bucket namespace missing"

echo ""
echo "=== Upload mapping + route using SDK getObject ==="
result=$(OCI_INT_PROFILE="$OCI_INT_PROFILE" \
  MAPPING_BUCKET_NAME="$MAPPING_BUCKET_NAME" \
  MAPPING_BUCKET_NAMESPACE="$MAPPING_BUCKET_NAMESPACE" \
  OCI_REGION="${OCI_REGION:-}" \
  node - <<'NODE'
const fs = require('fs');
const path = require('path');

const common = require('oci-common');
const objectstorage = require('oci-objectstorage');

const { loadRoutingDefinition, processEnvelope } = require(path.join(process.cwd(), 'tools/json_router.js'));
const { createMappingLoader } = require(path.join(process.cwd(), 'tools/adapters/mapping_loader.js'));
const { createOciObjectStorageMappingSource } = require(path.join(process.cwd(), 'tools/adapters/oci_object_storage_mapping_source.js'));

function isObject(v) { return typeof v === 'object' && v !== null && !Array.isArray(v); }

(async () => {
  const profile = process.env.OCI_INT_PROFILE;
  const bucketName = process.env.MAPPING_BUCKET_NAME;
  const namespaceName = process.env.MAPPING_BUCKET_NAMESPACE;
  const mappingKey = 'mapping_log.jsonata';
  const objectName = `jsonata/${mappingKey}`;

  const provider = new common.ConfigFileAuthenticationDetailsProvider(undefined, profile);
  const client = new objectstorage.ObjectStorageClient({ authenticationDetailsProvider: provider });

  // Ensure region/endpoint are set consistently (SDK resolution can be finicky).
  let regionId = null;
  if (process.env.OCI_REGION) {
    regionId = process.env.OCI_REGION;
  }
  if (typeof provider.getRegion === 'function' && provider.getRegion()) {
    const r = provider.getRegion();
    regionId = typeof r === 'string' ? r : (r.regionId || r.regionIdentifier || null);
  }
  if (regionId) {
    try {
      client.region = common.Region.fromRegionId(regionId);
    } catch (_) {
      // Fall back to raw region id string if Region helper rejects it.
      client.region = regionId;
    }
    client.endpoint = `https://objectstorage.${regionId}.oraclecloud.com`;
  }

  // Upload mapping content.
  const fx = path.join(process.cwd(), 'tests/fixtures/router_destinations/ut111_mixed_destinations');
  const mappingBody = fs.readFileSync(path.join(fx, mappingKey), 'utf8');
  // Bucket creation can be eventually consistent; retry putObject a few times.
  let lastErr = null;
  for (let attempt = 1; attempt <= 8; attempt++) {
    try {
      await client.putObject({
        namespaceName,
        bucketName,
        objectName,
        putObjectBody: mappingBody,
        contentType: 'application/json'
      });
      lastErr = null;
      break;
    } catch (e) {
      lastErr = e;
      await new Promise((r) => setTimeout(r, 5000));
    }
  }
  if (lastErr) throw lastErr;

  // Build routing definition dynamically to point mapping destination at this bucket/prefix.
  const definition = loadRoutingDefinition(path.join(fx, 'routing.json'));
  definition.adapters = {
    ...(definition.adapters || {}),
    'oci_object_storage:mappings': { bucket: bucketName, prefix: 'jsonata/' },
  };
  definition.mapping = { type: 'oci_object_storage', name: 'mappings' };

  const source = createOciObjectStorageMappingSource({
    getObject: async ({ bucket, objectName: obj }) => {
      let resp = null;
      let lastErr = null;
      for (let attempt = 1; attempt <= 8; attempt++) {
        try {
          resp = await client.getObject({ namespaceName, bucketName: bucket, objectName: obj });
          lastErr = null;
          break;
        } catch (e) {
          lastErr = e;
          await new Promise((r) => setTimeout(r, 3000));
        }
      }
      if (lastErr) throw lastErr;
      const v = resp.value;
      // Depending on SDK/runtime, value can be a stream, Buffer, or string.
      if (v && typeof v.on === 'function') {
        const chunks = [];
        await new Promise((resolve, reject) => {
          v.on('data', (c) => chunks.push(Buffer.isBuffer(c) ? c : Buffer.from(c)));
          v.on('end', resolve);
          v.on('error', reject);
        });
        return Buffer.concat(chunks).toString('utf8');
      }
      // Web ReadableStream (undici/fetch style)
      if (v && typeof v.getReader === 'function') {
        const reader = v.getReader();
        const chunks = [];
        // eslint-disable-next-line no-constant-condition
        while (true) {
          const { done, value } = await reader.read();
          if (done) break;
          chunks.push(Buffer.from(value));
        }
        return Buffer.concat(chunks).toString('utf8');
      }
      if (Buffer.isBuffer(v)) return v.toString('utf8');
      if (typeof v === 'string') return v;
      return String(v);
    }
  });

  const loadMapping = createMappingLoader({
    destinationMap: definition.adapters,
    mappingSources: [source],
  });

  const envelope = JSON.parse(fs.readFileSync(path.join(fx, 'source/001_workflow_run.json'), 'utf8'));
  let out = null;
  await processEnvelope(envelope, definition, {
    loadMapping,
    onRoute: async ({ output }) => { out = output; }
  });

  // Minimal sanity checks.
  if (!isObject(out) || out.outcome !== 'success') {
    throw new Error(`Unexpected output: ${JSON.stringify(out)}`);
  }
  process.stdout.write(JSON.stringify(out));
})().catch((err) => { process.stderr.write(String(err.message) + '\n'); process.exit(1); });
NODE
)

assert_eq "IT-1 router fetched mapping from OCI Object Storage bucket" \
  '{"kind":"log","repo":"acme/repo","outcome":"success"}' "$result"

echo ""
echo "=== Summary ==="
echo "passed: $PASS  failed: $FAIL"
[[ "$FAIL" -eq 0 ]]

