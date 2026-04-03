#!/usr/bin/env bash
# Operator script: OCI session auth, pack ~/.oci, upload to GitHub as a repository secret.
# Requires: oci, gh, jq, tar, base64. Interactive: oci session authenticate (browser).
#
# Usage: .github/actions/oci-profile-setup/setup_oci_github_access.sh [--profile PROFILE] [--repo OWNER/REPO]
#          [--secret-name NAME] [--dry-run] [--help]

set -euo pipefail

PROFILE="DEFAULT"
SESSION_PROFILE_NAME="SLI_TEST"
REPO=""
SECRET_NAME="OCI_CONFIG_PAYLOAD"
DRY_RUN=0

sli_base64_encode_nowrap() {
  if base64 --help 2>&1 | grep -q -- '-w'; then
    base64 -w 0
  else
    base64 | tr -d '\n'
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
  --repo OWNER/REPO   GitHub repository (default: gh repo view)
  --secret-name NAME  Secret name in GitHub (default: OCI_CONFIG_PAYLOAD)
  --dry-run           Pack and print payload size; do not call gh secret set
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

if [[ "$DRY_RUN" -eq 0 ]]; then
  if ! gh auth status >/dev/null 2>&1; then
    echo "ERROR: gh is not authenticated. Run: gh auth login" >&2
    exit 1
  fi
fi

HOME_REGION="$(
  oci iam region-subscription list --profile "$PROFILE" --output json \
    | jq -r '(.data // [])[] | select(."is-home-region" == true) | ."region-name"' \
    | head -n1
)"
if [[ -z "$HOME_REGION" ]]; then
  echo "ERROR: Could not resolve home region (is-home-region) for profile $PROFILE." >&2
  exit 1
fi

echo "Using OCI profile: $PROFILE"
echo "Session profile name: $SESSION_PROFILE_NAME"
echo "Home region: $HOME_REGION"
echo "GitHub repository: $REPO"
echo "Secret name: $SECRET_NAME"

echo "Running oci session authenticate (browser)..."
oci session authenticate \
  --region "$HOME_REGION" \
  --profile "$PROFILE" \
  --profile-name "$SESSION_PROFILE_NAME"

SESSION_REL=".oci/sessions/${SESSION_PROFILE_NAME}"
if [[ ! -d "${HOME}/${SESSION_REL}" ]]; then
  echo "ERROR: Expected session directory missing: ~/${SESSION_REL}" >&2
  exit 1
fi

# Normalize config so session file references are portable:
# replace the absolute operator $HOME prefix with a placeholder ${{HOME}}
# in both the main config and all session files for the chosen session profile name.
# The runner action replaces this placeholder back to the runner's $HOME after untar.
if command -v perl >/dev/null 2>&1; then
  perl -pi -e "s#\\Q$HOME\\E#\\$\\{\\{HOME\\}\\}#g" "$HOME/.oci/config" || true
  if compgen -G "$HOME/${SESSION_REL}/*" >/dev/null 2>&1; then
    perl -pi -e "s#\\Q$HOME\\E#\\$\\{\\{HOME\\}\\}#g" "$HOME"/${SESSION_REL}/* || true
  fi
else
  # Fallback: best-effort sed; may not handle all edge cases but avoids hardcoding operator HOME.
  sed -i.bak "s#$HOME#\${{HOME}}#g" "$HOME/.oci/config" || true
  if compgen -G "$HOME/${SESSION_REL}/*" >/dev/null 2>&1; then
    sed -i.bak "s#$HOME#\${{HOME}}#g" "$HOME"/${SESSION_REL}/* || true
  fi
fi

TMP_TAR="$(mktemp)"
trap 'rm -f "$TMP_TAR"' EXIT

# Pack the entire .oci tree so all files referenced by the profiles are included.
tar -czf "$TMP_TAR" -C "$HOME" .oci
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

