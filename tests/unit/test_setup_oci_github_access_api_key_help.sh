#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

pass() { echo "[PASS] $*"; }
fail() { echo "[FAIL] $*" >&2; exit 1; }

out="$(bash "${REPO_ROOT}/.github/actions/oci-profile-setup/setup_oci_github_access.sh" --help)"
echo "$out" | rg -q -- '--account-type' || fail "--account-type not documented"
echo "$out" | rg -q -- 'api_key' || fail "api_key mode not documented"
pass "help documents api_key mode"

