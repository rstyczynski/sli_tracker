#!/usr/bin/env bash
# Restores ~/.oci from OCI_CONFIG_PAYLOAD (base64 gzip tarball of .oci/config + optional .oci/sessions/<profile>).

set -euo pipefail

PROFILE="${OCI_PROFILE_VERIFY:-DEFAULT}"
AUTH_MODE="${OCI_AUTH_MODE:-auto}"

sli_key_file_from_profile() {
  local cfg="$1" prof="$2"
  awk -v want="[${prof}]" '
    function strip(s) { sub(/\r$/, "", s); return s }
    BEGIN { inblk = 0 }
    {
      line = strip($0)
      if (line == want) { inblk = 1; next }
      if (line ~ /^\[/ && inblk) exit
      if (inblk && line ~ /^[[:space:]]*key_file[[:space:]]*=/) {
        sub(/^[[:space:]]*key_file[[:space:]]*=[[:space:]]*/, "", line)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
        if (line ~ /^".*"$/) { gsub(/^"|"$/, "", line) }
        print line
        exit
      }
    }
  ' "$cfg"
}

sli_resolve_key_path() {
  local raw="$1"
  [[ -z "$raw" ]] && return 0
  raw="${raw/#\~/$HOME}"
  raw="${raw//\$\{HOME\}/$HOME}"
  raw="${raw//\$\{\{HOME\}\}/$HOME}"
  if [[ "$raw" != /* ]]; then
    raw="${HOME}/${raw}"
  fi
  printf '%s' "$raw"
}

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

# Backward-compatibility: some OCI session configs embed operator absolute paths
# (e.g. /Users/<name>/.oci/... on macOS, /home/<name>/.oci/... on Linux).
# Rewrite those to the runner's HOME so the restored session is usable.
if command -v perl >/dev/null 2>&1; then
  perl -pi -e "s#/(Users|home)/[^/]+/\\.oci/#${HOME}/.oci/#g" "${HOME}/.oci/config" 2>/dev/null || true
else
  sed -i.bak -E "s#/(Users|home)/[^/]+/\\.oci/#${HOME}/.oci/#g" "${HOME}/.oci/config" 2>/dev/null || true
fi

if [[ ! -r "${HOME}/.oci/config" ]]; then
  echo "::error::~/.oci/config missing or not readable after extract." >&2
  exit 1
fi

SESSION_DIR="${HOME}/.oci/sessions/${PROFILE}"

if [[ "$AUTH_MODE" == "auto" ]]; then
  if [[ -d "$SESSION_DIR" ]]; then
    AUTH_MODE="token_based"
    echo "::notice::oci-auth-mode auto: using token_based (found ${SESSION_DIR})."
  else
    _key_raw="$(sli_key_file_from_profile "${HOME}/.oci/config" "$PROFILE")"
    _key_abs="$(sli_resolve_key_path "$_key_raw")"
    if [[ -n "$_key_raw" && -f "$_key_abs" ]]; then
      AUTH_MODE="none"
      echo "::notice::oci-auth-mode auto: using none (API key / config_profile pack; no session directory)."
    else
      echo "::error::oci-auth-mode auto: no session directory at ${SESSION_DIR} and no usable key_file for profile [${PROFILE}] (check profile name matches the packed config; for config_profile use setup_oci_github_access.sh --session-profile-name to match CI)." >&2
      exit 1
    fi
  fi
fi

if [[ "$AUTH_MODE" == "token_based" ]]; then
  if [[ ! -d "$SESSION_DIR" ]]; then
    echo "::error::Expected session directory missing after extract: ${SESSION_DIR}" >&2
    exit 1
  fi

  if command -v perl >/dev/null 2>&1; then
    perl -pi -e "s#\\$\\{\\{HOME\\}\\}#${HOME}#g" "${SESSION_DIR}"/* 2>/dev/null || true
    perl -pi -e "s#/(Users|home)/[^/]+/\\.oci/#${HOME}/.oci/#g" "${SESSION_DIR}"/* 2>/dev/null || true
  else
    sed -i.bak "s#\${{HOME}}#${HOME}#g" "${SESSION_DIR}"/* 2>/dev/null || true
    sed -i.bak -E "s#/(Users|home)/[^/]+/\\.oci/#${HOME}/.oci/#g" "${SESSION_DIR}"/* 2>/dev/null || true
  fi
fi

if [[ "$AUTH_MODE" == "token_based" ]]; then
  REAL_OCI="$(command -v oci || true)"
  if [[ -z "$REAL_OCI" ]]; then
    echo "::error::oci not found in PATH. Ensure install-oci-cli ran before oci-profile-setup." >&2
    exit 1
  fi

  WRAP_DIR="${HOME}/.local/oci-wrapper/bin"
  mkdir -p "$WRAP_DIR"
  # Use /bin/bash to avoid /usr/bin/env edge cases (e.g. CRLF in shebang).
  {
    printf '%s\n' '#!/bin/bash'
    printf '%s\n' 'set -euo pipefail'
    printf '%s\n' "exec \"${REAL_OCI}\" --auth security_token \"\$@\""
  } > "${WRAP_DIR}/oci"
  chmod +x "${WRAP_DIR}/oci"

  # Ensure the wrapper is used by subsequent steps in the job.
  # Use GITHUB_PATH only — writing PATH=... to GITHUB_ENV would set the literal
  # string "$PATH" rather than expanding it, breaking the runtime PATH entirely.
  if [[ -n "${GITHUB_PATH:-}" ]]; then
    echo "${WRAP_DIR}" >> "${GITHUB_PATH}"
  fi

  echo "::notice::OCI wrapper enabled (token_based): ${WRAP_DIR}/oci injects --auth security_token."
fi

echo "::notice::OCI profile restored under ${HOME}/.oci (profile ${PROFILE})."

# Expose paths for downstream steps (e.g. sli-event context-json).
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "config-file=${HOME}/.oci/config"
    echo "profile=${PROFILE}"
  } >> "$GITHUB_OUTPUT"
fi
