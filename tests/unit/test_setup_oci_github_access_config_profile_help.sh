#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

pass() { echo "[PASS] $*"; }
fail() { echo "[FAIL] $*" >&2; exit 1; }

out="$(bash "${REPO_ROOT}/.github/actions/oci-profile-setup/setup_oci_github_access.sh" --help)"
echo "$out" | rg -q -- 'config_profile' || fail "config_profile mode not documented"
echo "$out" | rg -q -- '--account-type' || fail "--account-type not documented"
echo "$out" | rg -q -- 'session-profile-name' || fail "session-profile-name not documented"
echo "$out" | rg -q -- 'destination' || fail "destination profile wording not documented"
pass "help documents config_profile mode"
