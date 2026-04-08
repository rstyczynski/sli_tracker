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
#          [--account-type session|api_key] [--private-key-secret-ocid OCID]
#          [--skip-session-auth] [--help]

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
                      Name of the *session* profile to create with `oci session authenticate`
                      (default: SLI_TEST). This avoids the interactive \"Enter the name of the profile\"
                      question.
  --account-type TYPE Session token payload (session) or API key payload (api_key) (default: session).
  --private-key-secret-ocid OCID
                      Required for api_key mode. OCID of an OCI Vault Secret that stores the private key PEM.
  --repo OWNER/REPO   GitHub repository (default: gh repo view)
  --secret-name NAME  Secret name in GitHub (default: OCI_CONFIG_PAYLOAD)
  --dry-run           Pack and print payload size; do not call gh secret set
  --skip-session-auth Do not run oci session authenticate (browser); use existing
                      ~/.oci/sessions/<session-profile-name> (re-pack / upload only)
  --help              Show this help

Session tokens expire; re-run this script before workflows need a fresh token.
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
if [[ "$SKIP_SESSION_AUTH" -eq 0 ]]; then
  echo "Home region: $HOME_REGION"
else
  echo "Home region: (skipped; --skip-session-auth)"
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
else
  if [[ -z "$PRIVATE_KEY_SECRET_OCID" ]]; then
    echo "ERROR: --private-key-secret-ocid is required when --account-type api_key" >&2
    exit 1
  fi
fi

# ── Single-profile config: copy only [SESSION_PROFILE_NAME] from ~/.oci/config ──

FULL_CFG="${HOME}/.oci/config"
PACKED_CFG="$(mktemp)"

_prof_line="[${SESSION_PROFILE_NAME}]"
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

echo ""
echo "Packed config (verbatim session profile only, no [DEFAULT] merge):"
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
else
  mkdir -p "${TMP_OCI_DIR}/.oci/meta"
  printf '%s' "$PRIVATE_KEY_SECRET_OCID" > "${TMP_OCI_DIR}/.oci/meta/sli_api_key_secret_ocid"
fi

# Normalize ~/.oci/ paths to portable ${{HOME}} placeholder (on the copies only).
if command -v perl >/dev/null 2>&1; then
  perl -pi -e "s#\\Q$HOME/.oci/#\\$\\{\\{HOME\\}\\}/.oci/#g" "${TMP_OCI_DIR}/.oci/config" || true
  if compgen -G "${TMP_OCI_DIR}/${SESSION_REL}/*" >/dev/null 2>&1; then
    perl -pi -e "s#\\Q$HOME/.oci/#\\$\\{\\{HOME\\}\\}/.oci/#g" "${TMP_OCI_DIR}"/${SESSION_REL}/* || true
  fi
else
  sed -i.bak "s#$HOME/.oci/#\${{HOME}}/.oci/#g" "${TMP_OCI_DIR}/.oci/config" || true
  if compgen -G "${TMP_OCI_DIR}/${SESSION_REL}/*" >/dev/null 2>&1; then
    sed -i.bak "s#$HOME/.oci/#\${{HOME}}/.oci/#g" "${TMP_OCI_DIR}"/${SESSION_REL}/* || true
  fi
  rm -f "${TMP_OCI_DIR}/${SESSION_REL}"/*.bak 2>/dev/null || true
fi

echo "Packing into secret (paths relative to HOME):"
echo "  .oci/config  (single-profile: ${SESSION_PROFILE_NAME})"
if [[ "$ACCOUNT_TYPE" == "session" ]]; then
  echo "  ${SESSION_REL}/"
else
  echo "  .oci/meta/sli_api_key_secret_ocid"
fi
if command -v du >/dev/null 2>&1; then
  echo "  (approx sizes on disk)"
  du -sh "${TMP_OCI_DIR}/.oci/config" "${TMP_OCI_DIR}/${SESSION_REL}" 2>/dev/null || true
fi

if [[ "$ACCOUNT_TYPE" == "session" ]]; then
  tar -czf "$TMP_TAR" -C "$TMP_OCI_DIR" .oci/config "${SESSION_REL}"
else
  tar -czf "$TMP_TAR" -C "$TMP_OCI_DIR" .oci/config .oci/meta/sli_api_key_secret_ocid
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

