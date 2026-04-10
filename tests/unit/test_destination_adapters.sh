#!/usr/bin/env bash
# tests/unit/test_destination_adapters.sh
# Unit tests for universal destination adapters and dispatcher.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ROUTER="${REPO_ROOT}/tools/json_router.js"
FILE_ADAPTER="${REPO_ROOT}/tools/adapters/file_adapter.js"
LOGGING_ADAPTER="${REPO_ROOT}/tools/adapters/oci_logging_adapter.js"
MONITORING_ADAPTER="${REPO_ROOT}/tools/adapters/oci_monitoring_adapter.js"
OBJECT_ADAPTER="${REPO_ROOT}/tools/adapters/oci_object_storage_adapter.js"
DISPATCHER="${REPO_ROOT}/tools/adapters/destination_dispatcher.js"
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

tmp_dir=$(mktemp -d /tmp/sli21_file_adapter.XXXXXX)
result=$(node - <<NODE
const { loadRoutingDefinition } = require('${ROUTER}');
const { createFileAdapter } = require('${FILE_ADAPTER}');
(async () => {
  const definition = loadRoutingDefinition('${FX}/routing.json');
  const adapter = createFileAdapter({
    rootDir: '${tmp_dir}',
    destinationMap: definition.adapters
  });
  await adapter.onRoute({
    route: { id: 'audit_to_file', destination: { type: 'file_system', name: 'audit_copy' } },
    output: { ok: true },
    envelope: {}
  });
  const state = adapter.getState();
  process.stdout.write(JSON.stringify(state.routeWrites.map((x) => x.path.split('/').slice(-3).join('/'))));
})().catch((err) => { process.stderr.write(String(err.message) + '\\n'); process.exit(1); });
NODE
)
assert_eq "UT-111 file adapter resolves logical destination via routing.json adapters" '["audit/events/001_audit_to_file.json"]' "$result"
rm -rf "$tmp_dir"

result=$(node - <<NODE
const { loadRoutingDefinition } = require('${ROUTER}');
const { createOciLoggingAdapter } = require('${LOGGING_ADAPTER}');
(async () => {
  const definition = loadRoutingDefinition('${FX}/routing.json');
  const adapter = createOciLoggingAdapter({ destinationMap: definition.adapters });
  await adapter.onRoute({
    route: { id: 'workflow_to_logging', destination: { type: 'oci_logging', name: 'github_events' } },
    output: { event: 'x' },
    envelope: {}
  });
  process.stdout.write(JSON.stringify(adapter.getState().deliveries));
})().catch((err) => { process.stderr.write(String(err.message) + '\\n'); process.exit(1); });
NODE
)
assert_eq "UT-112 OCI Logging adapter resolves target from routing.json" '[{"route":"workflow_to_logging","target":{"logId":"log-1"}}]' "$result"

result=$(node - <<NODE
const { loadRoutingDefinition } = require('${ROUTER}');
const { createOciMonitoringAdapter } = require('${MONITORING_ADAPTER}');
(async () => {
  const definition = loadRoutingDefinition('${FX}/routing.json');
  const adapter = createOciMonitoringAdapter({ destinationMap: definition.adapters });
  await adapter.onRoute({
    route: { id: 'health_to_monitoring', destination: { type: 'oci_monitoring', name: 'health_signal' } },
    output: { value: 1 },
    envelope: {}
  });
  process.stdout.write(JSON.stringify(adapter.getState().deliveries));
})().catch((err) => { process.stderr.write(String(err.message) + '\\n'); process.exit(1); });
NODE
)
assert_eq "UT-113 OCI Monitoring adapter resolves target from routing.json" '[{"route":"health_to_monitoring","target":{"compartmentId":"compartment-1"}}]' "$result"

result=$(node - <<NODE
const { loadRoutingDefinition } = require('${ROUTER}');
const { createOciObjectStorageAdapter } = require('${OBJECT_ADAPTER}');
(async () => {
  const definition = loadRoutingDefinition('${FX}/routing.json');
  const adapter = createOciObjectStorageAdapter({ destinationMap: definition.adapters });
  await adapter.onRoute({
    route: { id: 'bucket_to_object_storage', destination: { type: 'oci_object_storage', name: 'raw_events' } },
    output: { object: 'a' },
    envelope: {}
  });
  process.stdout.write(JSON.stringify(adapter.getState().deliveries));
})().catch((err) => { process.stderr.write(String(err.message) + '\\n'); process.exit(1); });
NODE
)
assert_eq "UT-114 OCI Object Storage adapter resolves target from routing.json" '[{"route":"bucket_to_object_storage","target":{"bucket":"incoming","prefix":"events/"}}]' "$result"

tmp_dir=$(mktemp -d /tmp/sli21_dispatcher.XXXXXX)
result=$(node - <<NODE
const fs = require('fs');
const path = require('path');
const { loadRoutingDefinition, processEnvelopes } = require('${ROUTER}');
const { createFileSourceAdapter } = require('${REPO_ROOT}/tools/adapters/file_source_adapter.js');
const { createFileAdapter } = require('${FILE_ADAPTER}');
const { createOciLoggingAdapter } = require('${LOGGING_ADAPTER}');
const { createOciMonitoringAdapter } = require('${MONITORING_ADAPTER}');
const { createOciObjectStorageAdapter } = require('${OBJECT_ADAPTER}');
const { createDestinationDispatcher } = require('${DISPATCHER}');

(async () => {
  const definition = loadRoutingDefinition('${FX}/routing.json');
  const source = createFileSourceAdapter({ sourceDir: '${FX}/source' });
  const fileAdapter = createFileAdapter({
    rootDir: '${tmp_dir}',
    supportedTypes: ['file_system'],
    destinationMap: definition.adapters,
    preserveSourceFileName: true,
  });
  const logging = createOciLoggingAdapter({ destinationMap: definition.adapters });
  const monitoring = createOciMonitoringAdapter({ destinationMap: definition.adapters });
  const objectStorage = createOciObjectStorageAdapter({ destinationMap: definition.adapters });
  const dispatcher = createDestinationDispatcher({
    adapters: [logging, monitoring, objectStorage, fileAdapter],
    deadLetterDestination: definition.dead_letter
  });
  const summary = await processEnvelopes(source.readEnvelopes(), definition, dispatcher);
  process.stdout.write(JSON.stringify({
    processed: summary.processed,
    routed: summary.routed,
    dead_lettered: summary.dead_lettered,
    logging: logging.getState().deliveries.length,
    monitoring: monitoring.getState().deliveries.length,
    object_storage: objectStorage.getState().deliveries.length,
    file: fileAdapter.getState().routeWrites.length
  }));
})().catch((err) => { process.stderr.write(String(err.message) + '\\n'); process.exit(1); });
NODE
)
# dead letter goes to oci_logging:pipeline_errors — logging count is 2 (1 normal + 1 dead letter)
assert_eq "UT-115 destination dispatcher routes mixed logical destinations and dead letter" '{"processed":5,"routed":4,"dead_lettered":1,"logging":2,"monitoring":1,"object_storage":1,"file":1}' "$result"
rm -rf "$tmp_dir"

# UT-116: routing.json mapping section is parsed and exposed as definition.mapping
result=$(node - <<NODE
const { loadRoutingDefinition } = require('${ROUTER}');
(async () => {
  const definition = loadRoutingDefinition('${FX}/routing.json');
  process.stdout.write(JSON.stringify(definition.mapping));
})().catch((err) => { process.stderr.write(String(err.message) + '\\n'); process.exit(1); });
NODE
)
assert_eq "UT-116 routing.json mapping section parsed as definition.mapping" '{"type":"oci_object_storage","name":"mappings"}' "$result"

# UT-117: dispatcher throws when deadLetterDestination is absent and dead letter fires
result=$(node - <<NODE
const { loadRoutingDefinition, processEnvelopes } = require('${ROUTER}');
const { createOciLoggingAdapter } = require('${LOGGING_ADAPTER}');
const { createDestinationDispatcher } = require('${DISPATCHER}');
(async () => {
  const definition = loadRoutingDefinition('${FX}/routing.json');
  const logging = createOciLoggingAdapter({ destinationMap: definition.adapters });
  const dispatcher = createDestinationDispatcher({ adapters: [logging] });
  // envelope that matches no route → triggers dead letter
  try {
    await processEnvelopes([{ body: { message: 'no route' } }], definition, dispatcher);
    process.stdout.write('no-error');
  } catch (e) {
    process.stdout.write('threw');
  }
})().catch(() => process.stdout.write('threw'));
NODE
)
assert_eq "UT-117 dispatcher throws when dead letter fires with no deadLetterDestination" 'threw' "$result"

# UT-118: dispatcher throws when no adapter supports the dead letter destination type
result=$(node - <<NODE
const { loadRoutingDefinition, processEnvelopes } = require('${ROUTER}');
const { createFileAdapter } = require('${FILE_ADAPTER}');
const { createDestinationDispatcher } = require('${DISPATCHER}');
const os = require('os');
const path = require('path');
(async () => {
  const definition = loadRoutingDefinition('${FX}/routing.json');
  const tmp = path.join(os.tmpdir(), 'sli21_ut118');
  const fileAdapter = createFileAdapter({ rootDir: tmp, supportedTypes: ['file_system'], destinationMap: definition.adapters });
  // dead_letter destination is oci_logging — not supported by file adapter alone
  const dispatcher = createDestinationDispatcher({
    adapters: [fileAdapter],
    deadLetterDestination: definition.dead_letter
  });
  try {
    await processEnvelopes([{ body: { message: 'no route' } }], definition, dispatcher);
    process.stdout.write('no-error');
  } catch (e) {
    process.stdout.write('threw');
  }
})().catch(() => process.stdout.write('threw'));
NODE
)
assert_eq "UT-118 dispatcher throws when no adapter supports dead letter destination type" 'threw' "$result"

echo ""
echo "=== destination adapters: $((PASS+FAIL)) tests, $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
