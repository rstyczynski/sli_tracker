#!/usr/bin/env bash
# tests/unit/test_mapping_loader.sh
# Unit tests for adapter-backed mapping loader (OCI Object Storage mapping source).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ROUTER="${REPO_ROOT}/tools/json_router.js"
MAPPING_LOADER="${REPO_ROOT}/tools/adapters/mapping_loader.js"
OCI_MAPPING_SOURCE="${REPO_ROOT}/tools/adapters/oci_object_storage_mapping_source.js"
FX="${REPO_ROOT}/tests/fixtures/router_destinations/ut111_mixed_destinations"

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

result=$(ROUTER="$ROUTER" MAPPING_LOADER="$MAPPING_LOADER" OCI_MAPPING_SOURCE="$OCI_MAPPING_SOURCE" FX="$FX" node - <<'NODE'
const fs = require('fs');
const path = require('path');

const { loadRoutingDefinition, processEnvelope } = require(process.env.ROUTER);
const { createMappingLoader } = require(process.env.MAPPING_LOADER);
const { createOciObjectStorageMappingSource } = require(process.env.OCI_MAPPING_SOURCE);

(async () => {
  const fx = process.env.FX;
  const definition = loadRoutingDefinition(path.join(fx, 'routing.json'));
  const envelope = JSON.parse(fs.readFileSync(path.join(fx, 'source/001_workflow_run.json'), 'utf8'));

  const source = createOciObjectStorageMappingSource({
    getObject: async ({ bucket, objectName }) => {
      // In real OCI: fetch object contents. In unit tests: read from fixtures.
      // routing.json config uses prefix "jsonata/" for mappings bucket.
      if (bucket !== 'sli-mappings') throw new Error('unexpected bucket');
      const fileName = objectName.replace(/^jsonata\//, '');
      return fs.readFileSync(path.join(fx, fileName), 'utf8');
    }
  });

  const loadMapping = createMappingLoader({
    destinationMap: definition.adapters,
    mappingSources: [source],
  });

  let out = null;
  await processEnvelope(envelope, definition, {
    loadMapping,
    onRoute: async ({ output }) => { out = output; }
  });

  process.stdout.write(JSON.stringify(out));
})().catch((err) => { process.stderr.write(String(err.message) + '\n'); process.exit(1); });
NODE
)

assert_eq "UT-120 mapping loader fetches mapping via oci_object_storage mapping source" \
  '{"kind":"log","repo":"acme/repo","outcome":"success"}' "$result"

echo ""
echo "=== mapping loader: $((PASS+FAIL)) tests, $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]

