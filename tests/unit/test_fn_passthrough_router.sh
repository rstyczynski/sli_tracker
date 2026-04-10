#!/usr/bin/env bash
# Unit test: router_passthrough core (JSONata $ + stub Object Storage emit).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
FN_DIR="${REPO_ROOT}/fn/router_passthrough"

PASS=0
FAIL=0

ok()   { echo "[PASS] $1"; PASS=$((PASS + 1)); }
fail() { echo "[FAIL] $1"; FAIL=$((FAIL + 1)); }

export OCI_INGEST_BUCKET="ut-fn-router-bucket"

cd "$FN_DIR"
if [[ ! -d node_modules ]]; then
  npm install >/dev/null
fi

if ! OUT=$(node <<'NODE'
const assert = require('assert');
const { runRouter } = require('./router_core');
(async () => {
  const calls = [];
  const r = await runRouter({ hello: 'world', n: 42 }, {
    putObject: async (x) => { calls.push(x); },
  });
  assert.strictEqual(r.status, 'routed');
  assert.strictEqual(calls.length, 1);
  const body = JSON.parse(calls[0].content);
  assert.strictEqual(body.hello, 'world');
  assert.strictEqual(body.n, 42);
  assert.ok(calls[0].objectName.includes('fn-'));
  assert.ok(calls[0].objectName.startsWith('ingest/'));
  const calls2 = [];
  await runRouter(
    { body: { x: 1 }, source_meta: { file_name: 'fixed-name.json' } },
    { putObject: async (x) => { calls2.push(x); } }
  );
  assert.strictEqual(calls2[0].objectName, 'ingest/fixed-name.json');
  console.log('ok');
})();
NODE
); then
  fail "router_core runRouter assertions failed"
  echo "$OUT" >&2
else
  ok "runRouter pass-through + stub putObject (random and source_meta object names)"
fi

echo "=== Summary ==="
echo "passed: $PASS  failed: $FAIL"

if [[ "$FAIL" -ne 0 ]]; then exit 1; fi
echo "PASS"
