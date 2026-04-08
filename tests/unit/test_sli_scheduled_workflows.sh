#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

pass() { echo "[PASS] $*"; }
fail() { echo "[FAIL] $*" >&2; exit 1; }

require() { command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"; }
require rg

W1="${REPO_ROOT}/.github/workflows/sli_compute_sli_metrics.yml"
W2="${REPO_ROOT}/.github/workflows/sli_ratio_simulator.yml"

[[ -f "$W1" ]] || fail "missing workflow: $W1"
[[ -f "$W2" ]] || fail "missing workflow: $W2"
pass "workflow files exist"

# UT-1 schedules + workflow_dispatch
rg -q 'schedule:' "$W1" || fail "SLI-22 missing schedule trigger"
rg -q 'workflow_dispatch:' "$W1" || fail "SLI-22 missing workflow_dispatch"
rg -q 'cron:.*\\*/30' "$W1" || fail "SLI-22 missing */30 minute cron"
pass "SLI-22 schedule + dispatch ok"

rg -q 'schedule:' "$W2" || fail "SLI-23 missing schedule trigger"
rg -q 'workflow_dispatch:' "$W2" || fail "SLI-23 missing workflow_dispatch"
rg -q "cron:\\s*[\"']0 \\* \\* \\* \\*[\"']" "$W2" || fail "SLI-23 missing hourly cron (0 * * * *)"
pass "SLI-23 schedule + dispatch ok"

# UT-2 SLI_TEST + OCI_CONFIG_PAYLOAD (oci-auth-mode defaults to auto: session vs API-key packs)
for f in "$W1" "$W2"; do
  rg -qF 'secrets.OCI_CONFIG_PAYLOAD' "$f" || fail "$(basename "$f") missing secrets.OCI_CONFIG_PAYLOAD"
  rg -qF 'profile: SLI_TEST' "$f" || fail "$(basename "$f") missing profile SLI_TEST"
  rg -qF 'uses: ./.github/actions/oci-profile-setup' "$f" || fail "$(basename "$f") missing oci-profile-setup"
  rg -qF 'uses: ./.github/actions/install-oci-cli' "$f" || fail "$(basename "$f") missing install-oci-cli step"
done
pass "OCI profile restore wiring ok"

# UT-3 repo variables for OCIDs
for f in "$W1" "$W2"; do
  rg -q 'vars\.SLI_OCI_COMPARTMENT_ID' "$f" || fail "$(basename "$f") missing vars.SLI_OCI_COMPARTMENT_ID"
  rg -q 'vars\.SLI_OCI_LOG_ID' "$f" || fail "$(basename "$f") missing vars.SLI_OCI_LOG_ID"
done
pass "repo vars wiring ok"

