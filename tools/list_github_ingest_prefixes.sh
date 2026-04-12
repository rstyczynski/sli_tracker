#!/usr/bin/env bash
# List the newest objects under each GitHub-event prefix used by router_passthrough
# (ingest/github/<event>/). Intended for operators after real or synthetic webhook posts.
#
# Usage:
#   OCI_CLI_PROFILE=DEFAULT SLI_OS_NAMESPACE=myns SLI_INGEST_BUCKET=mybucket \
#     ./tools/list_github_ingest_prefixes.sh [--limit N]
#
# Namespace name: oci os ns get --query data --raw-output
#
# The CLI returns list results in arbitrary order; this script sorts by timeCreated in jq.

set -euo pipefail

LIMIT=5
args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --limit)
      LIMIT="${2:?--limit requires a number}"
      shift 2
      ;;
    *)
      args+=("$1")
      shift
      ;;
  esac
done

NS="${SLI_OS_NAMESPACE:-${args[0]:-}}"
BUCKET="${SLI_INGEST_BUCKET:-${args[1]:-}}"

if [[ -z "${NS:-}" || -z "${BUCKET:-}" ]]; then
  echo "Usage: SLI_OS_NAMESPACE=... SLI_INGEST_BUCKET=... $0 [--limit N]" >&2
  exit 1
fi

PROFILE="${OCI_CLI_PROFILE:-DEFAULT}"
export OCI_CLI_PROFILE="$PROFILE"

PREFIXES=(ping push workflow_run pull_request)

echo "# profile=${PROFILE} namespace=${NS} bucket=${BUCKET} limit=${LIMIT}"
echo

for ev in "${PREFIXES[@]}"; do
  pref="ingest/github/${ev}/"
  echo "## ${pref}"
  if ! out=$(oci os object list \
    --namespace-name "$NS" \
    --bucket-name "$BUCKET" \
    --prefix "$pref" \
    --limit 200 \
    --fields 'name,size,timeCreated' 2>/dev/null); then
    echo "  (list failed — check auth, bucket, prefix)"
    continue
  fi
  echo "$out" | jq -r --argjson lim "$LIMIT" '
    [ .data[]? | {name, size, tc: (.["time-created"] // .timeCreated // "")} ]
    | sort_by(.tc) | reverse | .[0:$lim][]
    | "  \(.tc)  \(.name)  (\(.size) bytes)"
  ' 2>/dev/null || echo "$out" | jq .
  echo
done

echo "## default ingest/ (latest under ingest/, excluding ingest/github/*)"
if ! out=$(oci os object list \
  --namespace-name "$NS" \
  --bucket-name "$BUCKET" \
  --prefix "ingest/" \
  --limit 500 \
  --fields 'name,size,timeCreated' 2>/dev/null); then
  echo "  (list failed)"
  exit 0
fi
echo "$out" | jq -r --argjson lim "$LIMIT" '
  [ .data[]? | select(.name | startswith("ingest/github/") | not) | {name, size, tc: (.["time-created"] // .timeCreated // "")} ]
  | sort_by(.tc) | reverse | .[0:$lim][]
  | "  \(.tc)  \(.name)  (\(.size) bytes)"
' 2>/dev/null || echo "$out" | jq .
