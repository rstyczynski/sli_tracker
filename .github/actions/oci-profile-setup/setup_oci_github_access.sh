#!/usr/bin/env bash
# Operator script: OCI session auth, pack ~/.oci/config + one session dir, upload to GitHub as a repository secret.
# Requires: oci, gh, jq, tar, base64. Interactive: oci session authenticate (browser).
#
# The packed tarball contains only the session profile section copied verbatim from
# ~/.oci/config (no merging from [DEFAULT]). Ensure that section has every field you
# need (e.g. for API-key signing: tenancy, user, fingerprint; for session token:
# key_file, region, security_token_file — see emit_curl.sh).
#
# Usage: .../setup_oci_github_access.sh [--profile PROFILE] [--repo OWNER/REPO]
#          [--session-profile-name NAME] [--secret-name NAME] [--dry-run]
#          [--account-type session|api_key|config_profile] [--private-key-secret-ocid OCID]
#          [--skip-session-auth] [--help]
#
# config_profile: --profile = source stanza in ~/.oci/config; --session-profile-name = name written
# in the packed tarball (default SLI_TEST), so CI can keep profile: SLI_TEST while sourcing [DEFAULT] locally.

set -euo pipefail

PROFILE="DEFAULT"
SESSION_PROFILE_NAME="SLI_TEST"
ACCOUNT_TYPE="session"
PRIVATE_KEY_SECRET_OCID=""
REPO=""
SECRET_NAME="OCI_CONFIG_PAYLOAD"
DRY_RUN=0
SKIP_SESSION_AUTH=0

sli_base64_encode_nowrap() {
  if base64 --help 2>&1 | grep -q -- '-w'; then
    base64 -w 0
  else
    base64 | tr -d '\n'
  fi
}

# Expand literal ${{HOME}} to the real $HOME in ~/.oci files before any `oci` call.
# Older versions of this script replaced every $HOME prefix, breaking key_file paths like
# ~/.ssh/*.pem (OCI then looked for a file literally named ${{HOME}}/.ssh/...).
sli_extract_key_file_value() {
  awk '
    /^[[:space:]]*key_file[[:space:]]*=/ {
      val = $0
      sub(/^[[:space:]]*key_file[[:space:]]*=[[:space:]]*/, "", val)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
      if (val ~ /^".*"$/) {
        gsub(/^"|"$/, "", val)
      }
      print val
      exit
    }
  ' "$1"
}

sli_resolve_user_path() {
  local p="$1"
  p="${p/#\~/$HOME}"
  if [[ "$p" != /* ]]; then
    p="${HOME}/${p}"
  fi
  printf '%s' "$p"
}

sli_config_profile_copy_key_into_tree() {
  local tmp_root="$1"
  local key_raw key_abs bn

  key_raw="$(sli_extract_key_file_value "${tmp_root}/.oci/config")"
  if [[ -z "$key_raw" ]]; then
    echo "ERROR: key_file is required in the packed profile section for config_profile mode." >&2
    return 1
  fi
  key_abs="$(sli_resolve_user_path "$key_raw")"
  if [[ ! -f "$key_abs" ]]; then
    echo "ERROR: key_file not found or not a regular file: ${key_abs}" >&2
    return 1
  fi

  # For config_profile we always make the key file part of the payload.
  # The tarball includes only `.oci/`, so copy the key into `.oci/keys/` and rewrite key_file.
  bn="$(basename "$key_abs")"
  mkdir -p "${tmp_root}/.oci/keys"
  cp "$key_abs" "${tmp_root}/.oci/keys/${bn}"
  if command -v perl >/dev/null 2>&1; then
    # Do NOT interpolate $bn inside the perl replacement string directly: filenames can contain '@'
    # which perl would treat as an array sigil (e.g. "@gmail") and drop. Pass via env instead.
    NEW='key_file=${{HOME}}/.oci/keys/'"${bn}" perl -pi -e 's#^[[:space:]]*key_file[[:space:]]*=.*#$ENV{NEW}#' "${tmp_root}/.oci/config" || true
  else
    sed -i.bak -E "s#^[[:space:]]*key_file[[:space:]]*=.*#key_file=\${{HOME}}/.oci/keys/${bn}#" "${tmp_root}/.oci/config" || true
    rm -f "${tmp_root}/.oci/config.bak" 2>/dev/null || true
  fi
}

sli_expand_placeholder_home_in_oci_tree() {
  if command -v perl >/dev/null 2>&1; then
    perl -pi -e "s#\\$\\{\\{HOME\\}\\}#${HOME}#g" "${HOME}/.oci/config" || true
    if [[ -d "${HOME}/.oci/sessions" ]]; then
      find "${HOME}/.oci/sessions" -type f -print0 2>/dev/null \
        | while IFS= read -r -d '' f; do
            perl -pi -e "s#\\$\\{\\{HOME\\}\\}#${HOME}#g" "$f" || true
          done
    fi
  else
    sed -i.bak "s#\${{HOME}}#${HOME}#g" "${HOME}/.oci/config" || true
    if [[ -d "${HOME}/.oci/sessions" ]]; then
      find "${HOME}/.oci/sessions" -type f -print0 2>/dev/null \
        | while IFS= read -r -d '' f; do
            sed -i.bak "s#\${{HOME}}#${HOME}#g" "$f" || true
          done
    fi
  fi
}

usage() {
  cat <<'EOF'
Pack OCI session config and upload to a GitHub repository secret.

Usage:
  .github/actions/oci-profile-setup/setup_oci_github_access.sh [--profile PROFILE] [--repo OWNER/REPO]
                                                              [--session-profile-name NAME]
                                                              [--secret-name NAME] [--dry-run]

Options:
  --profile NAME      OCI config profile (default: DEFAULT)
  --session-profile-name NAME
                      Session mode: name for `oci session authenticate --profile-name` and packed section.
                      config_profile mode: destination profile name in the tarball (default: SLI_TEST);
                      the stanza copied from --profile (source) is rewritten to [NAME] if different.
  --account-type TYPE session | api_key | config_profile (default: session).
                      config_profile: pack [--profile] stanza and existing key_file on disk (no session auth, no Vault OCID).
  --private-key-secret-ocid OCID
                      Required for api_key mode. OCID of an OCI Vault Secret that stores the private key PEM.
                      Not used for config_profile.
  --repo OWNER/REPO   GitHub repository (default: gh repo view)
  --secret-name NAME  Secret name in GitHub (default: OCI_CONFIG_PAYLOAD)
  --dry-run           Pack and print payload size; do not call gh secret set
  --skip-session-auth Do not run oci session authenticate (browser); use existing
                      ~/.oci/sessions/<session-profile-name> (re-pack / upload only).
                      Ignored for config_profile.
  --help              Show this help

Session tokens expire; re-run this script before workflows need a fresh token.
config_profile: pack [--profile] stanza as [--session-profile-name] in the secret (default: copy [DEFAULT] to [SLI_TEST]). Match oci-profile-setup profile to --session-profile-name.
EOF
}

require_cmd() {
  local c="$1"
  if ! command -v "$c" >/dev/null 2>&1; then
    echo "ERROR: Required command not found: $c" >&2
    exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      PROFILE="${2:?}"
      shift 2
      ;;
    --session-profile-name)
      SESSION_PROFILE_NAME="${2:?}"
      shift 2
      ;;
    --account-type)
      ACCOUNT_TYPE="${2:?}"
      shift 2
      ;;
    --private-key-secret-ocid)
      PRIVATE_KEY_SECRET_OCID="${2:?}"
      shift 2
      ;;
    --repo)
      REPO="${2:?}"
      shift 2
      ;;
    --secret-name)
      SECRET_NAME="${2:?}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --skip-session-auth)
      SKIP_SESSION_AUTH=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

case "$ACCOUNT_TYPE" in
  session|api_key|config_profile) ;;
  *)
    echo "ERROR: Unknown --account-type: ${ACCOUNT_TYPE} (expected session, api_key, or config_profile)." >&2
    exit 1
    ;;
esac

require_cmd oci
require_cmd jq
require_cmd tar
require_cmd base64
require_cmd gh

if [[ -z "$REPO" ]]; then
  REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
fi
if [[ -z "$REPO" ]]; then
  echo "ERROR: Could not detect GitHub repo; pass --repo OWNER/REPO" >&2
  exit 1
fi

if [[ ! -f "${HOME}/.oci/config" ]]; then
  echo "ERROR: ~/.oci/config not found. Create an OCI profile before running this script." >&2
  exit 1
fi

sli_expand_placeholder_home_in_oci_tree

if [[ "$DRY_RUN" -eq 0 ]]; then
  if ! gh auth status >/dev/null 2>&1; then
    echo "ERROR: gh is not authenticated. Run: gh auth login" >&2
    exit 1
  fi
fi

SESSION_REL=".oci/sessions/${SESSION_PROFILE_NAME}"

if [[ "$ACCOUNT_TYPE" == "session" && "$SKIP_SESSION_AUTH" -eq 0 ]]; then
  HOME_REGION="$(
    oci iam region-subscription list --profile "$PROFILE" --output json \
      | jq -r '(.data // [])[] | select(."is-home-region" == true) | ."region-name"' \
      | head -n1
  )"
  if [[ -z "$HOME_REGION" ]]; then
    echo "ERROR: Could not resolve home region (is-home-region) for profile $PROFILE." >&2
    exit 1
  fi
fi

echo "Using OCI profile: $PROFILE"
echo "Session profile name: $SESSION_PROFILE_NAME"
echo "Account type: $ACCOUNT_TYPE"
if [[ "$ACCOUNT_TYPE" == "session" ]]; then
  if [[ "$SKIP_SESSION_AUTH" -eq 0 ]]; then
    echo "Home region: $HOME_REGION"
  else
    echo "Home region: (skipped; --skip-session-auth)"
  fi
else
  echo "Home region: (n/a for account type ${ACCOUNT_TYPE})"
fi
echo "GitHub repository: $REPO"
echo "Secret name: $SECRET_NAME"

if [[ "$ACCOUNT_TYPE" == "session" ]]; then
  if [[ "$SKIP_SESSION_AUTH" -eq 1 ]]; then
    echo "Skipping oci session authenticate (--skip-session-auth); using existing ~/${SESSION_REL}"
  else
    echo "Running oci session authenticate (browser)..."
    oci session authenticate \
      --region "$HOME_REGION" \
      --profile "$PROFILE" \
      --profile-name "$SESSION_PROFILE_NAME"
  fi
fi

if [[ "$ACCOUNT_TYPE" == "session" ]]; then
  if [[ ! -d "${HOME}/${SESSION_REL}" ]]; then
    echo "ERROR: Expected session directory missing: ~/${SESSION_REL}" >&2
    exit 1
  fi
elif [[ "$ACCOUNT_TYPE" == "api_key" ]]; then
  if [[ -z "$PRIVATE_KEY_SECRET_OCID" ]]; then
    echo "ERROR: --private-key-secret-ocid is required when --account-type api_key" >&2
    exit 1
  fi
elif [[ "$ACCOUNT_TYPE" == "config_profile" ]]; then
  if [[ -n "$PRIVATE_KEY_SECRET_OCID" ]]; then
    echo "ERROR: --private-key-secret-ocid is not used with --account-type config_profile" >&2
    exit 1
  fi
fi

# ── Single-profile config: copy one stanza from ~/.oci/config ──

FULL_CFG="${HOME}/.oci/config"
PACKED_CFG="$(mktemp)"

# Stanza to copy from ~/.oci/config: session/api_key use [SESSION_PROFILE_NAME]; config_profile uses [PROFILE] (source).
if [[ "$ACCOUNT_TYPE" == "config_profile" ]]; then
  _prof_line="[${PROFILE}]"
else
  _prof_line="[${SESSION_PROFILE_NAME}]"
fi
awk -v want="${_prof_line}" '
  function strip(s) { sub(/\r$/, "", s); return s }
  {
    line = strip($0)
    if (line == want) { inblk = 1; print $0; next }
    if (line ~ /^\[/ && inblk) exit
    if (inblk) print $0
  }
' "$FULL_CFG" > "$PACKED_CFG"

if [[ ! -s "$PACKED_CFG" ]]; then
  echo "ERROR: Profile section ${_prof_line} not found (or empty) in ${FULL_CFG}" >&2
  rm -f "$PACKED_CFG"
  exit 1
fi

# config_profile: rename [SOURCE] -> [DEST] so workflows can use profile SLI_TEST while sourcing e.g. [DEFAULT].
if [[ "$ACCOUNT_TYPE" == "config_profile" && "$PROFILE" != "$SESSION_PROFILE_NAME" ]]; then
  if command -v perl >/dev/null 2>&1; then
    perl -pi -e "s#^\[\Q${PROFILE}\E\]#[${SESSION_PROFILE_NAME}]#" "$PACKED_CFG"
  else
    sed -i.bak "s#^\[${PROFILE}\]#[${SESSION_PROFILE_NAME}]#" "$PACKED_CFG"
    rm -f "${PACKED_CFG}.bak" 2>/dev/null || true
  fi
  echo "config_profile: packed [${PROFILE}] as [${SESSION_PROFILE_NAME}] (destination profile for CI)."
fi

PACK_PROFILE_NAME="$SESSION_PROFILE_NAME"

echo ""
echo "Packed config (single profile only, no [DEFAULT] merge):"
cat "$PACKED_CFG"
echo ""

TMP_TAR="$(mktemp)"
TMP_OCI_DIR="$(mktemp -d)"
trap 'rm -f "$TMP_TAR" "$PACKED_CFG"; rm -rf "$TMP_OCI_DIR"' EXIT

# Assemble the tarball tree from copies (never modify the operator's real ~/.oci).
mkdir -p "${TMP_OCI_DIR}/.oci"
cp "$PACKED_CFG" "${TMP_OCI_DIR}/.oci/config"
if [[ "$ACCOUNT_TYPE" == "session" ]]; then
  mkdir -p "$(dirname "${TMP_OCI_DIR}/${SESSION_REL}")"
  cp -a "${HOME}/${SESSION_REL}" "${TMP_OCI_DIR}/${SESSION_REL}"
  rm -f "${TMP_OCI_DIR}/${SESSION_REL}"/*.bak 2>/dev/null || true
elif [[ "$ACCOUNT_TYPE" == "api_key" ]]; then
  mkdir -p "${TMP_OCI_DIR}/.oci/meta"
  printf '%s' "$PRIVATE_KEY_SECRET_OCID" > "${TMP_OCI_DIR}/.oci/meta/sli_api_key_secret_ocid"
elif [[ "$ACCOUNT_TYPE" == "config_profile" ]]; then
  sli_config_profile_copy_key_into_tree "$TMP_OCI_DIR" || exit 1
fi

# Normalize ~/.oci/ paths to portable ${{HOME}} placeholder (on the copies only).
if command -v perl >/dev/null 2>&1; then
  perl -pi -e "s#\\Q$HOME/.oci/#\\$\\{\\{HOME\\}\\}/.oci/#g" "${TMP_OCI_DIR}/.oci/config" || true
  if [[ "$ACCOUNT_TYPE" == "session" ]] && compgen -G "${TMP_OCI_DIR}/${SESSION_REL}/*" >/dev/null 2>&1; then
    perl -pi -e "s#\\Q$HOME/.oci/#\\$\\{\\{HOME\\}\\}/.oci/#g" "${TMP_OCI_DIR}"/${SESSION_REL}/* || true
  fi
else
  sed -i.bak "s#$HOME/.oci/#\${{HOME}}/.oci/#g" "${TMP_OCI_DIR}/.oci/config" || true
  if [[ "$ACCOUNT_TYPE" == "session" ]] && compgen -G "${TMP_OCI_DIR}/${SESSION_REL}/*" >/dev/null 2>&1; then
    sed -i.bak "s#$HOME/.oci/#\${{HOME}}/.oci/#g" "${TMP_OCI_DIR}"/${SESSION_REL}/* || true
  fi
  rm -f "${TMP_OCI_DIR}/${SESSION_REL}"/*.bak 2>/dev/null || true
fi

echo "Packing into secret (paths relative to HOME):"
echo "  .oci/config  (single-profile: ${PACK_PROFILE_NAME})"
if [[ "$ACCOUNT_TYPE" == "session" ]]; then
  echo "  ${SESSION_REL}/"
elif [[ "$ACCOUNT_TYPE" == "api_key" ]]; then
  echo "  .oci/meta/sli_api_key_secret_ocid"
else
  echo "  .oci/... (including key_file material)"
fi
if command -v du >/dev/null 2>&1; then
  echo "  (approx sizes on disk)"
  du -sh "${TMP_OCI_DIR}/.oci" 2>/dev/null || true
fi

if [[ "$ACCOUNT_TYPE" == "session" ]]; then
  tar -czf "$TMP_TAR" -C "$TMP_OCI_DIR" .oci/config "${SESSION_REL}"
elif [[ "$ACCOUNT_TYPE" == "api_key" ]]; then
  tar -czf "$TMP_TAR" -C "$TMP_OCI_DIR" .oci/config .oci/meta/sli_api_key_secret_ocid
else
  tar -czf "$TMP_TAR" -C "$TMP_OCI_DIR" .oci
fi
rm -rf "$TMP_OCI_DIR"
PAYLOAD="$(sli_base64_encode_nowrap <"$TMP_TAR")"

MAX_BYTES=$((64 * 1024))
PAYLOAD_BYTES=${#PAYLOAD}
if [[ "$PAYLOAD_BYTES" -gt "$MAX_BYTES" ]]; then
  echo "ERROR: Packed secret exceeds GitHub limit (${MAX_BYTES} bytes): ${PAYLOAD_BYTES} bytes." >&2
  exit 1
fi

echo "Packed payload size (base64 chars): $PAYLOAD_BYTES"

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "Dry run: not calling gh secret set."
  exit 0
fi

echo "Uploading secret ${SECRET_NAME} to ${REPO}..."
printf '%s' "$PAYLOAD" | gh secret set "$SECRET_NAME" --repo "$REPO"
echo "Done. Workflows can pass this secret to oci-profile-setup as oci_config_payload."

