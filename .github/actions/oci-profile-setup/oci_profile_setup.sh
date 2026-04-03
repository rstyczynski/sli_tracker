#!/usr/bin/env bash
# Restores ~/.oci from OCI_CONFIG_PAYLOAD (base64 gzip tarball of .oci/config + .oci/sessions/<profile>).

set -euo pipefail

PROFILE="${OCI_PROFILE_VERIFY:-DEFAULT}"

if [[ -z "${OCI_CONFIG_PAYLOAD:-}" ]]; then
  echo "::error::OCI_CONFIG_PAYLOAD is empty. Pass the repository secret into the action input oci_config_payload (e.g. secrets.OCI_CONFIG_PAYLOAD)." >&2
  exit 1
fi

mkdir -p "${HOME}/.oci"

if ! printf '%s' "$OCI_CONFIG_PAYLOAD" | base64 -d 2>/dev/null | tar -xzf - -C "$HOME" 2>/dev/null; then
  echo "::error::Failed to decode or extract OCI config payload (invalid base64 or tarball)." >&2
  exit 1
fi

# Replace placeholder ${{HOME}} with the runner's HOME so OCI CLI can resolve file references.
if [[ -r "${HOME}/.oci/config" ]]; then
  if command -v perl >/dev/null 2>&1; then
    perl -pi -e "s#\\$\\{\\{HOME\\}\\}#${HOME}#g" "${HOME}/.oci/config" || true
  else
    sed -i.bak "s#\${{HOME}}#${HOME}#g" "${HOME}/.oci/config" || true
  fi
fi

if [[ ! -r "${HOME}/.oci/config" ]]; then
  echo "::error::~/.oci/config missing or not readable after extract." >&2
  exit 1
fi

SESSION_DIR="${HOME}/.oci/sessions/${PROFILE}"
if [[ ! -d "$SESSION_DIR" ]]; then
  echo "::error::Expected session directory missing after extract: ${SESSION_DIR}" >&2
  exit 1
fi

if command -v perl >/dev/null 2>&1; then
  perl -pi -e "s#\\$\\{\\{HOME\\}\\}#${HOME}#g" "${SESSION_DIR}"/* 2>/dev/null || true
else
  sed -i.bak "s#\${{HOME}}#${HOME}#g" "${SESSION_DIR}"/* 2>/dev/null || true
fi

echo "::notice::OCI profile restored under ${HOME}/.oci (profile ${PROFILE})."
