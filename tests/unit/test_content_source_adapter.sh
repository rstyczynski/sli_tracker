#!/usr/bin/env bash
# tests/unit/test_content_source_adapter.sh
# Unit tests for ContentSourceAdapter (filesystem + OCI Object Storage) and
# the refactored loadRoutingDefinitionAsync / oci_object_storage_mapping_source.
# Sprint 30 / SLI-60

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CONTENT_SOURCE="${REPO_ROOT}/tools/adapters/content_source_adapter.js"
OCI_CONTENT_SOURCE="${REPO_ROOT}/tools/adapters/oci_object_storage_content_source.js"
ROUTER="${REPO_ROOT}/tools/json_router.js"
MAPPING_SOURCE="${REPO_ROOT}/tools/adapters/oci_object_storage_mapping_source.js"

PASS=0
FAIL=0
TMPDIR_LOCAL="$(mktemp -d)"
trap 'rm -rf "${TMPDIR_LOCAL}"' EXIT

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

assert_contains() {
    local label="$1" needle="$2" haystack="$3"
    if echo "$haystack" | grep -qF "$needle"; then ok "$label"; else
        fail "$label"
        echo "       expected to contain: $needle"
        echo "       actual: $haystack"
    fi
}

# ---------------------------------------------------------------------------
# T1: FileSystemContentSourceAdapter — read existing file
# ---------------------------------------------------------------------------
echo '{"hello":"world"}' > "${TMPDIR_LOCAL}/test.json"

result=$(node - <<NODE
const { createFileSystemContentSourceAdapter } = require('${CONTENT_SOURCE}');
(async () => {
    const adapter = createFileSystemContentSourceAdapter({ basePath: '${TMPDIR_LOCAL}' });
    const content = await adapter.readContent('test.json');
    process.stdout.write(content.trim());
})().catch(e => { process.stderr.write(e.message); process.exit(1); });
NODE
2>&1 || true)

assert_eq "T1: FileSystemContentSourceAdapter reads existing file" '{"hello":"world"}' "$result"

# ---------------------------------------------------------------------------
# T2: FileSystemContentSourceAdapter — missing file throws
# ---------------------------------------------------------------------------
result=$(node - <<NODE
const { createFileSystemContentSourceAdapter } = require('${CONTENT_SOURCE}');
(async () => {
    const adapter = createFileSystemContentSourceAdapter({ basePath: '${TMPDIR_LOCAL}' });
    await adapter.readContent('nonexistent.json');
})().catch(e => { process.stdout.write(e.message); });
NODE
2>&1 || true)

assert_contains "T2: FileSystemContentSourceAdapter throws on missing file" "Cannot read content" "$result"

# ---------------------------------------------------------------------------
# T3: OciObjectStorageContentSourceAdapter — success via mock getObject
# ---------------------------------------------------------------------------
result=$(node - <<NODE
const { createOciObjectStorageContentSourceAdapter } = require('${OCI_CONTENT_SOURCE}');
(async () => {
    const mockGetObject = async ({ bucket, objectName }) => '{"key":"val"}';
    const adapter = createOciObjectStorageContentSourceAdapter({
        bucket: 'test-bucket',
        getObject: mockGetObject,
    });
    const content = await adapter.readContent('config/routing.json');
    process.stdout.write(content);
})().catch(e => { process.stderr.write(e.message); process.exit(1); });
NODE
2>&1 || true)

assert_eq "T3: OciObjectStorageContentSourceAdapter reads object from bucket" '{"key":"val"}' "$result"

# ---------------------------------------------------------------------------
# T4: OciObjectStorageContentSourceAdapter — propagates OCI error
# ---------------------------------------------------------------------------
result=$(node - <<NODE
const { createOciObjectStorageContentSourceAdapter } = require('${OCI_CONTENT_SOURCE}');
(async () => {
    const mockGetObject = async ({ bucket, objectName }) => { throw new Error('Object not found'); };
    const adapter = createOciObjectStorageContentSourceAdapter({
        bucket: 'test-bucket',
        getObject: mockGetObject,
    });
    await adapter.readContent('missing.json');
})().catch(e => { process.stdout.write(e.message); });
NODE
2>&1 || true)

assert_contains "T4: OciObjectStorageContentSourceAdapter propagates bucket error" "Object not found" "$result"

# ---------------------------------------------------------------------------
# T5: loadRoutingDefinitionAsync — uses injected adapter
# ---------------------------------------------------------------------------
ROUTING_JSON="${TMPDIR_LOCAL}/routing_async.json"
cat > "${ROUTING_JSON}" <<'JSON'
{"routes":[{"id":"test","transform":{"mapping":"./test.jsonata"},"destination":{"type":"file_system"}}]}
JSON

result=$(node - <<NODE
const { loadRoutingDefinitionAsync } = require('${ROUTER}');
const { createFileSystemContentSourceAdapter } = require('${CONTENT_SOURCE}');
(async () => {
    const adapter = createFileSystemContentSourceAdapter({ basePath: '${TMPDIR_LOCAL}' });
    const def = await loadRoutingDefinitionAsync('routing_async.json', adapter);
    process.stdout.write(def.routes[0].id);
})().catch(e => { process.stderr.write(e.message); process.exit(1); });
NODE
2>&1 || true)

assert_eq "T5: loadRoutingDefinitionAsync loads via injected adapter" "test" "$result"

# ---------------------------------------------------------------------------
# T6: loadRoutingDefinition(filePath) — backward-compatible one-arg form still works
# ---------------------------------------------------------------------------
result=$(node - <<NODE
const { loadRoutingDefinition } = require('${ROUTER}');
const def = loadRoutingDefinition('${ROUTING_JSON}');
process.stdout.write(def.routes[0].id);
NODE
2>&1 || true)

assert_eq "T6: loadRoutingDefinition one-arg backward compatibility" "test" "$result"

# ---------------------------------------------------------------------------
# T7: oci_object_storage_mapping_source — accepts ContentSourceAdapter
# ---------------------------------------------------------------------------
result=$(node - <<NODE
const { createOciObjectStorageMappingSource } = require('${MAPPING_SOURCE}');
(async () => {
    const mockAdapter = {
        async readContent(key) { return '\$'; }  // simple jsonata expression
    };
    const source = createOciObjectStorageMappingSource({ contentSourceAdapter: mockAdapter });
    const mapping = await source.load({ mappingKey: 'passthrough.jsonata' });
    process.stdout.write(mapping);
})().catch(e => { process.stderr.write(e.message); process.exit(1); });
NODE
2>&1 || true)

assert_eq "T7: Mapping source loads from bucket via adapter" '$' "$result"

# ---------------------------------------------------------------------------
# T8: URI parsing — oci:// scheme extracts bucket and key
# ---------------------------------------------------------------------------
result=$(node - <<NODE
const { parseOciUri, isOciUri } = require('${CONTENT_SOURCE}');
const parsed = parseOciUri('oci://my-bucket/config/routing.json');
if (parsed && parsed.bucket === 'my-bucket' && parsed.objectKey === 'config/routing.json') {
    process.stdout.write('OK');
} else {
    process.stdout.write('FAIL: ' + JSON.stringify(parsed));
}
NODE
2>&1 || true)

assert_eq "T8: URI parsing extracts bucket and key from oci:// URI" "OK" "$result"

# ---------------------------------------------------------------------------
# T9: URI parsing — mapping prefix
# ---------------------------------------------------------------------------
result=$(node - <<NODE
const { parseOciUri } = require('${CONTENT_SOURCE}');
const parsed = parseOciUri('oci://sli-mappings/jsonata/');
if (parsed && parsed.bucket === 'sli-mappings' && parsed.objectKey === 'jsonata/') {
    process.stdout.write('OK');
} else {
    process.stdout.write('FAIL: ' + JSON.stringify(parsed));
}
NODE
2>&1 || true)

assert_eq "T9: URI parsing for mapping prefix" "OK" "$result"

# ---------------------------------------------------------------------------
# T10: isOciUri detects oci:// scheme
# ---------------------------------------------------------------------------
result=$(node - <<NODE
const { isOciUri } = require('${CONTENT_SOURCE}');
const r1 = isOciUri('oci://bucket/key');
const r2 = isOciUri('./local/path');
const r3 = isOciUri('/absolute/path');
if (r1 === true && r2 === false && r3 === false) {
    process.stdout.write('OK');
} else {
    process.stdout.write('FAIL: ' + r1 + ',' + r2 + ',' + r3);
}
NODE
2>&1 || true)

assert_eq "T10: isOciUri detects oci:// scheme" "OK" "$result"

# ---------------------------------------------------------------------------
# T11: FileSystemContentSourceAdapter with basePath resolves relative keys
# ---------------------------------------------------------------------------
mkdir -p "${TMPDIR_LOCAL}/subdir"
echo '{"nested":"value"}' > "${TMPDIR_LOCAL}/subdir/nested.json"

result=$(node - <<NODE
const { createFileSystemContentSourceAdapter } = require('${CONTENT_SOURCE}');
(async () => {
    const adapter = createFileSystemContentSourceAdapter({ basePath: '${TMPDIR_LOCAL}/subdir' });
    const content = await adapter.readContent('nested.json');
    process.stdout.write(content.trim());
})().catch(e => { process.stderr.write(e.message); process.exit(1); });
NODE
2>&1 || true)

assert_eq "T11: FileSystem with basePath resolves relative keys" '{"nested":"value"}' "$result"

# ---------------------------------------------------------------------------
echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
[[ "${FAIL}" -eq 0 ]]
