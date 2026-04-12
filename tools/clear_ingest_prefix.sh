#!/usr/bin/env bash
# Delete every object whose name starts with PREFIX in the router ingest bucket (OCI bulk-delete).
# Default prefix is ingest/ (entire ingest tree). Objects outside the chosen prefix are untouched
# (e.g. config/routing.json is not under ingest/ and is kept).
#
# Usage:
#   SLI_OS_NAMESPACE=... SLI_INGEST_BUCKET=... ./tools/clear_ingest_prefix.sh --dry-run
#   SLI_OS_NAMESPACE=... SLI_INGEST_BUCKET=... ./tools/clear_ingest_prefix.sh --yes
#   ... ./tools/clear_ingest_prefix.sh --dir github/workflow_run --dry-run
#   ... ./tools/clear_ingest_prefix.sh --dir github/workflow_run --recursive --dry-run
#   ... ./tools/clear_ingest_prefix.sh --prefix ingest/github/ping/ --yes
#
# Real delete requires --yes (or SLI_CLEAR_INGEST_YES=1).
# Use only one of --dir or --prefix (not both). --dir is relative to ingest/ unless the value
# already starts with ingest/.
#
# With --dir only: OCI bulk-delete uses --delimiter / so only objects *directly* under that
# logical directory are removed (no deeper subpaths). Add --recursive to also delete everything
# nested under that directory. Without --dir, prefix ingest/ deletes the full tree (unchanged).

set -euo pipefail

DRY_RUN=0
YES=0
RECURSIVE=0
PREFIX='ingest/'
HAVE_PREFIX=0
HAVE_DIR=0
DIR_ARG=''
args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --yes)
      YES=1
      shift
      ;;
    --recursive)
      RECURSIVE=1
      shift
      ;;
    --prefix)
      PREFIX="${2:?--prefix requires a value (trailing / recommended)}"
      HAVE_PREFIX=1
      shift 2
      ;;
    --dir)
      DIR_ARG="${2:?--dir requires a path (e.g. github/workflow_run or ingest/github/ping/)}"
      HAVE_DIR=1
      shift 2
      ;;
    -h | --help)
      sed -n '1,45p' "$0" >&2
      exit 0
      ;;
    *)
      args+=("$1")
      shift
      ;;
  esac
done

if [[ "$HAVE_PREFIX" -eq 1 && "$HAVE_DIR" -eq 1 ]]; then
  echo "Use only one of --prefix or --dir." >&2
  exit 1
fi

if [[ "$RECURSIVE" -eq 1 && "$HAVE_DIR" -ne 1 ]]; then
  echo "--recursive is only valid with --dir (without --dir, the default already clears the full ingest/ tree)." >&2
  exit 1
fi

if [[ "$HAVE_DIR" -eq 1 ]]; then
  d="${DIR_ARG#./}"
  d="${d#/}"
  # strip trailing slashes for normalization, then add single /
  while [[ "$d" == */ ]]; do
    d="${d%/}"
  done
  if [[ -z "$d" || "$d" == "." || "$d" == "ingest" ]]; then
    PREFIX='ingest/'
  elif [[ "$d" == *'..'* ]]; then
    echo "--dir must not contain .." >&2
    exit 1
  elif [[ "$d" == ingest/* ]]; then
    PREFIX="${d}/"
  else
    PREFIX="ingest/${d}/"
  fi
  if [[ "$PREFIX" != ingest/* ]]; then
    echo "--dir must resolve to a prefix under ingest/" >&2
    exit 1
  fi
fi

NS="${SLI_OS_NAMESPACE:-${args[0]:-}}"
BUCKET="${SLI_INGEST_BUCKET:-${args[1]:-}}"

if [[ -z "${NS:-}" || -z "${BUCKET:-}" ]]; then
  echo "Usage: SLI_OS_NAMESPACE=... SLI_INGEST_BUCKET=... $0 [--dir PATH [--recursive]] [--prefix PREFIX] --dry-run | --yes" >&2
  exit 1
fi

if [[ ${#args[@]} -gt 2 ]]; then
  echo "Unexpected extra arguments (namespace and bucket come from env or first two args only)." >&2
  exit 1
fi

if [[ "$YES" -eq 1 && "$DRY_RUN" -eq 1 ]]; then
  echo "Use only one of --dry-run or --yes." >&2
  exit 1
fi

if [[ "$YES" -ne 1 && "$DRY_RUN" -ne 1 ]]; then
  if [[ "${SLI_CLEAR_INGEST_YES:-}" == "1" ]]; then
    YES=1
  else
    echo "Refusing: deletes objects under prefix \"${PREFIX}\" in bucket \"${BUCKET}\"." >&2
    if [[ "$HAVE_DIR" -eq 1 && "$RECURSIVE" -eq 0 ]]; then
      echo "  (--dir without --recursive: only direct objects under that path, not nested subdirs)" >&2
    fi
    echo "  Preview:  $0 [--dir github/ping [--recursive] | --prefix ingest/...] --dry-run" >&2
    echo "  Execute:  $0 [--dir ...] --yes   (or SLI_CLEAR_INGEST_YES=1 $0)" >&2
    exit 1
  fi
fi

PROFILE="${OCI_CLI_PROFILE:-DEFAULT}"
export OCI_CLI_PROFILE="$PROFILE"

oci_args=(
  os object bulk-delete
  --namespace-name "$NS"
  --bucket-name "$BUCKET"
  --prefix "$PREFIX"
)

# --dir: shallow delete (one hierarchy level) unless --recursive
if [[ "$HAVE_DIR" -eq 1 && "$RECURSIVE" -eq 0 ]]; then
  oci_args+=(--delimiter /)
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  oci_args+=(--dry-run)
else
  oci_args+=(--force)
fi

_delim='off'
[[ "$HAVE_DIR" -eq 1 && "$RECURSIVE" -eq 0 ]] && _delim='on'
echo "# profile=${PROFILE} namespace=${NS} bucket=${BUCKET} prefix=${PREFIX} delimiter_slash=${_delim} recursive=${RECURSIVE} dry_run=${DRY_RUN}" >&2
exec oci "${oci_args[@]}"
