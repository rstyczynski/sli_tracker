#!/usr/bin/env bash
# Download one object from the router ingest bucket (object body only).
#
# Usage:
#   SLI_OS_NAMESPACE=myns SLI_INGEST_BUCKET=mybucket \
#     ./tools/get_ingest_object.sh [--file OUT] OBJECT_NAME
#
# OBJECT_NAME is the full object key, e.g.:
#   ingest/github/workflow_run/fn-1775961003716-d1da2413.json
#
# Default is stdout (OCI --file -). Use --file path to write to a file.
# If an oci shell wrapper prints non-OCI text to stdout, use --file or silence the wrapper.

set -euo pipefail

OUT_FILE=''
args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --file)
      OUT_FILE="${2:?--file requires a path}"
      shift 2
      ;;
    -h | --help)
      sed -n '1,20p' "$0" >&2
      exit 0
      ;;
    *)
      args+=("$1")
      shift
      ;;
  esac
done

if [[ ${#args[@]} -lt 1 ]]; then
  echo "Usage: SLI_OS_NAMESPACE=... SLI_INGEST_BUCKET=... $0 [--file OUT] OBJECT_NAME" >&2
  exit 1
fi
if [[ ${#args[@]} -gt 1 ]]; then
  echo "Expected a single OBJECT_NAME (quote the key if needed)." >&2
  exit 1
fi

OBJECT_NAME="${args[0]}"
NS="${SLI_OS_NAMESPACE:-}"
BUCKET="${SLI_INGEST_BUCKET:-}"

if [[ -z "${NS}" || -z "${BUCKET}" ]]; then
  echo "Usage: SLI_OS_NAMESPACE=... SLI_INGEST_BUCKET=... $0 [--file OUT] OBJECT_NAME" >&2
  exit 1
fi

if [[ -z "${OUT_FILE}" ]]; then
  OUT_FILE='-'
fi

PROFILE="${OCI_CLI_PROFILE:-DEFAULT}"
export OCI_CLI_PROFILE="$PROFILE"

exec oci os object get \
  --namespace-name "$NS" \
  --bucket-name "$BUCKET" \
  --name "$OBJECT_NAME" \
  --file "$OUT_FILE"
