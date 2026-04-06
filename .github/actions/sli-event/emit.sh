#!/usr/bin/env bash
# SLI event payload builder + OCI push dispatcher.
# Reads EMIT_BACKEND (oci-cli | curl, default oci-cli) and delegates to the appropriate backend.
# When sourced (e.g. by tests), emit_common.sh helpers are available directly.

set -euo pipefail

# shellcheck source=emit_common.sh
source "$(dirname "${BASH_SOURCE[0]}")/emit_common.sh"

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  _EMIT_BACKEND="${EMIT_BACKEND:-oci-cli}"
  _SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
  case "$_EMIT_BACKEND" in
    curl)    exec bash "$_SCRIPT_DIR/emit_curl.sh" "$@" ;;
    oci-cli) exec bash "$_SCRIPT_DIR/emit_oci.sh"  "$@" ;;
    *)       echo "::error::Unknown EMIT_BACKEND: $_EMIT_BACKEND (valid: oci-cli, curl)"; exit 1 ;;
  esac
fi
