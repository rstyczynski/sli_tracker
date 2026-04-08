#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

pass() { echo "[PASS] $*"; }
fail() { echo "[FAIL] $*" >&2; exit 1; }

RESTORE="${REPO_ROOT}/.github/actions/oci-profile-setup/oci_profile_setup.sh"

OP_HOME="$(mktemp -d)"
RUN_HOME="$(mktemp -d)"
trap 'rm -rf "$OP_HOME" "$RUN_HOME"' EXIT

mkdir -p "${OP_HOME}/.oci/keys"
printf '%s\n' 'dummy-pem' > "${OP_HOME}/.oci/keys/ci.pem"
cat > "${OP_HOME}/.oci/config" <<'CFG'
[SLI_TEST]
user=ocid1.user.oc1..dummy
tenancy=ocid1.tenancy.oc1..dummy
fingerprint=aa:bb:cc:dd:ee
region=us-phoenix-1
key_file=${{HOME}}/.oci/keys/ci.pem
CFG

payload="$(tar -czf - -C "$OP_HOME" .oci | base64 | tr -d '\n')"

export HOME="$RUN_HOME"
export OCI_CONFIG_PAYLOAD="$payload"
export OCI_PROFILE_VERIFY="SLI_TEST"
export OCI_AUTH_MODE="none"

bash "$RESTORE"

[[ -r "${RUN_HOME}/.oci/config" ]] || fail "config not restored"
[[ -r "${RUN_HOME}/.oci/keys/ci.pem" ]] || fail "key file not restored"
grep -q 'key_file=' "${RUN_HOME}/.oci/config" || fail "key_file missing in restored config"
grep -q '^\[DEFAULT\]' "${RUN_HOME}/.oci/config" \
  || fail "expected [DEFAULT] stanza (oci-common SDK noise fix; mirrors SLI_TEST when missing)"
pass "config_profile-style payload restore round-trip"
