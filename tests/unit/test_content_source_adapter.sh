#!/usr/bin/env bash
# tests/unit/test_content_source_adapter.sh
# Unit tests for ContentSourceAdapter (filesystem + OCI Object Storage) and
# the refactored loadRoutingDefinitionAsync / oci_object_storage_mapping_source.

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
# TODO: implement — read ${TMPDIR_LOCAL}/test.json and print its content
process.stdout.write('TODO\n');
NODE
2>&1 || true)

assert_eq "T1: FileSystemContentSourceAdapter reads existing file" '{"hello":"world"}' "$result"

# ---------------------------------------------------------------------------
# T2: FileSystemContentSourceAdapter — missing file throws
# ---------------------------------------------------------------------------
result=$(node - <<NODE
const { createFileSystemContentSourceAdapter } = require('${CONTENT_SOURCE}');
# TODO: implement — attempt to read a non-existent file, expect error message
process.stdout.write('TODO\n');
NODE
2>&1 || true)

assert_contains "T2: FileSystemContentSourceAdapter throws on missing file" "TODO" "$result"

# ---------------------------------------------------------------------------
# T3: OciObjectStorageContentSourceAdapter — success via mock getObject
# ---------------------------------------------------------------------------
result=$(node - <<NODE
const { createOciObjectStorageContentSourceAdapter } = require('${OCI_CONTENT_SOURCE}');
# TODO: implement — inject mock getObject returning '{"key":"val"}', readContent("obj"), assert output
process.stdout.write('TODO\n');
NODE
2>&1 || true)

assert_eq "T3: OciObjectStorageContentSourceAdapter reads via mock getObject" '{"key":"val"}' "$result"

# ---------------------------------------------------------------------------
# T4: OciObjectStorageContentSourceAdapter — propagates OCI error
# ---------------------------------------------------------------------------
result=$(node - <<NODE
const { createOciObjectStorageContentSourceAdapter } = require('${OCI_CONTENT_SOURCE}');
# TODO: implement — inject mock getObject that throws, assert error is propagated
process.stdout.write('TODO\n');
NODE
2>&1 || true)

assert_contains "T4: OciObjectStorageContentSourceAdapter propagates OCI error" "TODO" "$result"

# ---------------------------------------------------------------------------
# T5: loadRoutingDefinitionAsync — uses injected adapter
# ---------------------------------------------------------------------------
ROUTING_JSON="${TMPDIR_LOCAL}/routing_async.json"
cat > "${ROUTING_JSON}" <<'JSON'
{"version":1,"routes":[]}
JSON

result=$(node - <<NODE
const { loadRoutingDefinitionAsync } = require('${ROUTER}');
# TODO: implement — construct FileSystemContentSourceAdapter, call loadRoutingDefinitionAsync, print version
process.stdout.write('TODO\n');
NODE
2>&1 || true)

assert_eq "T5: loadRoutingDefinitionAsync loads via injected adapter" "TODO" "$result"

# ---------------------------------------------------------------------------
# T6: loadRoutingDefinition(filePath) — backward-compatible one-arg form still works
# ---------------------------------------------------------------------------
result=$(node - <<NODE
const { loadRoutingDefinition } = require('${ROUTER}');
const def = loadRoutingDefinition('${ROUTING_JSON}');
process.stdout.write(String(def.version) + '\n');
NODE
2>&1 || true)

assert_eq "T6: loadRoutingDefinition one-arg backward compatibility" "1" "$result"

# ---------------------------------------------------------------------------
# T7: oci_object_storage_mapping_source — accepts ContentSourceAdapter
# ---------------------------------------------------------------------------
result=$(node - <<NODE
const { createOciObjectStorageMappingSource } = require('${MAPPING_SOURCE}');
# TODO: implement — inject mock ContentSourceAdapter returning '.jsonata' content, verify load() returns it
process.stdout.write('TODO\n');
NODE
2>&1 || true)

assert_eq "T7: oci_object_storage_mapping_source accepts ContentSourceAdapter" "TODO" "$result"

# ---------------------------------------------------------------------------
# T8: CLI URI parsing — oci:// scheme selects OCI adapter
# ---------------------------------------------------------------------------
result=$(node - <<NODE
# TODO: implement — import URI parsing helper from json_router_cli, parse oci://bucket/config/routing.json
# assert type === 'oci' && bucket === 'bucket' && key === 'config/routing.json'
process.stdout.write('TODO\n');
NODE
2>&1 || true)

assert_eq "T8: CLI URI parsing extracts bucket and key from oci:// URI" "TODO" "$result"

# ---------------------------------------------------------------------------
echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
[[ "${FAIL}" -eq 0 ]]
