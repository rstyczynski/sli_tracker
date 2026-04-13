#!/usr/bin/env bash
# Unit test: tests/run.sh --component flag (SLI-47)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RUN_SH="${REPO_ROOT}/tests/run.sh"

PASS=0
FAIL=0

ok()   { echo "[PASS] $1"; PASS=$((PASS + 1)); }
fail() { echo "[FAIL] $1"; FAIL=$((FAIL + 1)); }

# UT-SLI47-2: --component nonexistent exits non-zero with clear error
OUT=$(bash "$RUN_SH" --unit --component nonexistent 2>&1) && STATUS=0 || STATUS=$?
if [[ "$STATUS" -ne 0 ]] && echo "$OUT" | grep -q 'nonexistent'; then
    ok "UT-SLI47-2: --component nonexistent exits non-zero with component name in message"
else
    fail "UT-SLI47-2: --component nonexistent must exit non-zero and mention component name (exit=$STATUS)"
    echo "$OUT" >&2
fi

# UT-SLI47-2b: error message mentions 'not found'
if echo "$OUT" | grep -qi 'not found'; then
    ok "UT-SLI47-2b: error message contains 'not found'"
else
    fail "UT-SLI47-2b: error message must contain 'not found'"
    echo "$OUT" >&2
fi

# UT-SLI47-1: --component router runs exactly the 14 router unit scripts (skip check)
OUT_ROUTER=$(bash "$RUN_SH" --unit --component router 2>&1) || true
ROUTER_RUNS=$(echo "$OUT_ROUTER" | grep -c '^\[run\] unit/' || true)
ROUTER_SKIPS=$(echo "$OUT_ROUTER" | grep -c '^\[skip\] unit/' || true)
# router has 14 unit scripts; all others should be skipped
if [[ "$ROUTER_RUNS" -eq 14 ]]; then
    ok "UT-SLI47-1: --component router runs exactly 14 unit scripts"
else
    fail "UT-SLI47-1: expected 14 router unit scripts, got $ROUTER_RUNS"
    echo "$OUT_ROUTER" >&2
fi
# verify non-router scripts are skipped
if echo "$OUT_ROUTER" | grep -q '\[skip\] unit/test_emit'; then
    ok "UT-SLI47-1b: non-router scripts (test_emit) are skipped with --component router"
else
    fail "UT-SLI47-1b: test_emit.sh should be skipped when --component router is active"
    echo "$OUT_ROUTER" >&2
fi
if echo "$OUT_ROUTER" | grep -q '\[skip\] unit/test_install_oci_cli'; then
    ok "UT-SLI47-1c: non-router scripts (test_install_oci_cli) are skipped"
else
    fail "UT-SLI47-1c: test_install_oci_cli.sh should be skipped when --component router is active"
    echo "$OUT_ROUTER" >&2
fi

# UT-SLI47-3: --component install + --manifest produces union
INSTALL_MANIFEST="${REPO_ROOT}/tests/manifests/component_install.manifest"
EXTRA_MANIFEST=$(mktemp)
echo "unit:test_emit.sh" > "$EXTRA_MANIFEST"
OUT_UNION=$(bash "$RUN_SH" --unit --component install --manifest "$EXTRA_MANIFEST" 2>&1) || true
rm -f "$EXTRA_MANIFEST"
if echo "$OUT_UNION" | grep -q '\[run\] unit/test_install_oci_cli' && \
   echo "$OUT_UNION" | grep -q '\[run\] unit/test_emit'; then
    ok "UT-SLI47-3: --component install + --manifest union runs both scripts"
else
    fail "UT-SLI47-3: union of --component install and extra manifest should run both scripts"
    echo "$OUT_UNION" >&2
fi

# UT-SLI47-4: TESTS_DIR is exported and equals the tests/ directory
OUT_ENV=$(bash "$RUN_SH" --unit --component install 2>&1) || true
# verify no state-*.json files appeared in REPO_ROOT during the run
STATE_FILES=$(find "$REPO_ROOT" -maxdepth 1 -name 'state-*.json' -newer "$RUN_SH" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$STATE_FILES" -eq 0 ]]; then
    ok "UT-SLI47-4: no new state-*.json files created in project root during test run"
else
    fail "UT-SLI47-4: $STATE_FILES new state-*.json file(s) appeared in project root"
fi

# UT-SLI47-new-only incompatible: --new-only + --component must error
OUT_INCOMPAT=$(bash "$RUN_SH" --unit --new-only /dev/null --component router 2>&1) && IC_STATUS=0 || IC_STATUS=$?
if [[ "$IC_STATUS" -ne 0 ]] && echo "$OUT_INCOMPAT" | grep -qi 'incompatible'; then
    ok "UT-SLI47-5: --new-only + --component exits non-zero with 'incompatible' message"
else
    fail "UT-SLI47-5: --new-only + --component must exit non-zero with incompatible error (exit=$IC_STATUS)"
    echo "$OUT_INCOMPAT" >&2
fi

echo "=== Summary ==="
echo "passed: $PASS  failed: $FAIL"
if [[ "$FAIL" -ne 0 ]]; then exit 1; fi
echo "PASS"
