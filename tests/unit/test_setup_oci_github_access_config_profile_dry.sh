#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${REPO_ROOT}/.github/actions/oci-profile-setup/setup_oci_github_access.sh"

pass() { echo "[PASS] $*"; }
fail() { echo "[FAIL] $*" >&2; exit 1; }

OP_HOME="$(mktemp -d)"
trap 'rm -rf "$OP_HOME"' EXIT

mkdir -p "${OP_HOME}/.oci/keys"
printf '%s\n' 'dummy-pem-for-pack-test' > "${OP_HOME}/.oci/keys/pack_test.pem"
cat > "${OP_HOME}/.oci/config" <<EOF
[DEFAULT]
user=ocid1.user.oc1..dummy
tenancy=ocid1.tenancy.oc1..dummy
fingerprint=aa:bb:cc:dd:ee
region=us-phoenix-1
key_file=${OP_HOME}/.oci/keys/pack_test.pem
EOF

export HOME="$OP_HOME"

# Dry-run: no gh secret set; requires oci/jq/tar/base64/gh on PATH.
# Defaults: --profile DEFAULT → stanza copied as --session-profile-name SLI_TEST (destination for CI).
if ! bash "$SCRIPT" \
  --account-type config_profile \
  --profile DEFAULT \
  --session-profile-name SLI_TEST \
  --repo "${SLI_TEST_GITHUB_REPO:-octocat/Hello-World}" \
  --dry-run \
  >/tmp/sli_config_profile_dry.log 2>&1; then
  cat /tmp/sli_config_profile_dry.log >&2 || true
  fail "config_profile dry-run failed (see log above)"
fi

grep -qE '^\[SLI_TEST\]' /tmp/sli_config_profile_dry.log || fail "packed config should list [SLI_TEST] as destination section"
grep -q 'packed \[DEFAULT\] as \[SLI_TEST\]' /tmp/sli_config_profile_dry.log || fail "expected rename notice (DEFAULT→SLI_TEST)"

if grep -q '^\[SLI_TEST\]' "${OP_HOME}/.oci/config"; then
  fail "dry-run must not append [SLI_TEST] to local ~/.oci/config"
fi

pass "config_profile dry-run completed (DEFAULT→SLI_TEST)"

