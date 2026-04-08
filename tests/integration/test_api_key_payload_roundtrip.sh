#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

pass() { echo "[PASS] $*"; }
fail() { echo "[FAIL] $*" >&2; exit 1; }

RESTORE="${REPO_ROOT}/.github/actions/oci-profile-setup/oci_profile_setup.sh"

OP_HOME="$(mktemp -d)"
RUN_HOME="$(mktemp -d)"
trap 'rm -rf "$OP_HOME" "$RUN_HOME"' EXIT

mkdir -p "${OP_HOME}/.oci/meta"
cat > "${OP_HOME}/.oci/config" <<'CFG'
[SLI_TEST]
user=ocid1.user.oc1..dummy
tenancy=ocid1.tenancy.oc1..dummy
fingerprint=aa:bb:cc:dd:ee
region=eu-zurich-1
key_file=${{HOME}}/.oci/keys/sli_api_key.pem
CFG
echo "ocid1.vaultsecret.oc1..dummy" > "${OP_HOME}/.oci/meta/sli_api_key_secret_ocid"

export HOME="$OP_HOME"

# Pack: for integration we validate restore behavior for a config + key-secret-ocid payload.
payload="$(tar -czf - -C "$OP_HOME" .oci/config .oci/meta/sli_api_key_secret_ocid | base64 | tr -d '\n')"

export HOME="$RUN_HOME"
export OCI_CONFIG_PAYLOAD="$payload"
export OCI_PROFILE_VERIFY="SLI_TEST"
export OCI_AUTH_MODE="none"

bash "$RESTORE"

[[ -r "${RUN_HOME}/.oci/config" ]] || fail "config not restored"
[[ -r "${RUN_HOME}/.oci/meta/sli_api_key_secret_ocid" ]] || fail "key secret ocid not restored"
pass "api-key payload restore round-trip"

