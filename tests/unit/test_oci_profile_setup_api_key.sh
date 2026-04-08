#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

pass() { echo "[PASS] $*"; }
fail() { echo "[FAIL] $*" >&2; exit 1; }

TMP_HOME="$(mktemp -d)"
trap 'rm -rf "$TMP_HOME"' EXIT

mkdir -p "${TMP_HOME}/.oci/keys"

cat > "${TMP_HOME}/.oci/config" <<'CFG'
[SLI_TEST]
user=ocid1.user.oc1..dummy
tenancy=ocid1.tenancy.oc1..dummy
fingerprint=aa:bb:cc:dd:ee
region=eu-zurich-1
key_file=${{HOME}}/.oci/keys/sli_api_key.pem
CFG

echo "dummy-private-key" > "${TMP_HOME}/.oci/keys/sli_api_key.pem"

payload="$(tar -czf - -C "$TMP_HOME" .oci/config .oci/keys/sli_api_key.pem | base64 | tr -d '\n')"

# UT-1: api-key payload should restore without sessions when OCI_AUTH_MODE=none.
(
  export HOME="$(mktemp -d)"
  trap 'rm -rf "$HOME"' EXIT
  export OCI_CONFIG_PAYLOAD="$payload"
  export OCI_PROFILE_VERIFY="SLI_TEST"
  export OCI_AUTH_MODE="none"
  bash "${REPO_ROOT}/.github/actions/oci-profile-setup/oci_profile_setup.sh"
  [[ -r "${HOME}/.oci/config" ]] || fail "config not restored"
  [[ -r "${HOME}/.oci/keys/sli_api_key.pem" ]] || fail "key not restored"
  [[ ! -d "${HOME}/.oci/sessions/SLI_TEST" ]] || fail "sessions dir should not be required for api-key payload"
)
pass "api-key payload restore works without sessions"

# UT-2: token_based should still require sessions dir.
(
  export HOME="$(mktemp -d)"
  trap 'rm -rf "$HOME"' EXIT
  export OCI_CONFIG_PAYLOAD="$payload"
  export OCI_PROFILE_VERIFY="SLI_TEST"
  export OCI_AUTH_MODE="token_based"
  if bash "${REPO_ROOT}/.github/actions/oci-profile-setup/oci_profile_setup.sh" 2>/dev/null; then
    fail "expected token_based restore to fail without sessions"
  fi
)
pass "token_based still requires sessions"

