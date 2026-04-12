#!/usr/bin/env bash
# List newest object names under router ingest prefixes (filenames only, no JSON bodies).
#
# Usage:
#   OCI_CLI_PROFILE=DEFAULT SLI_OS_NAMESPACE=myns SLI_INGEST_BUCKET=mybucket \
#     ./tools/list_github_ingest_prefixes.sh [--limit N]
#
# Some shells wrap `oci` and print banner lines to stdout before the JSON document.
# We strip everything before the first line that starts with '[' or '{' so jq always
# sees a single JSON value.

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

LIST_CAP=200

echo "# profile=${PROFILE} namespace=${NS} bucket=${BUCKET} limit=${LIMIT}"
echo

# Drop OCI wrapper noise on stdout; keep from first JSON-looking line to EOF.
strip_leading_nonjson() {
  sed -n '/^[[:space:]]*[[{]/,$p'
}

# Return JSON array of object summaries (OCI --query data --raw-output), or [].
fetch_data_array() {
  local prefix="$1"
  local lim="${2:-$LIST_CAP}"
  local raw
  raw=$(
    oci os object list \
      --namespace-name "$NS" \
      --bucket-name "$BUCKET" \
      --prefix "$prefix" \
      --limit "$lim" \
      --fields 'name,timeCreated' \
      --query 'data' \
      --raw-output 2>/dev/null | strip_leading_nonjson
  ) || true
  raw="${raw//$'\r'/}"
  if [[ -z "${raw//[:space:]}" ]] || [[ "$raw" == 'null' ]]; then
    printf '%s\n' '[]'
    return
  fi
  printf '%s\n' "$raw"
}

# Newest-first object names (input: JSON array of object summaries).
print_names_newest_from_array() {
  local arr_json="$1"
  local lim="$2"
  if ! echo "$arr_json" | jq -e . >/dev/null 2>&1; then
    echo "  (list parse error: invalid JSON from oci)" >&2
    return
  fi
  echo "$arr_json" | jq -r --argjson lim "$lim" '
    [ .[]?
      | select(type == "object" and (.name | type == "string"))
      | {name, tc: (.["time-created"] // .timeCreated // "")} ]
    | sort_by(.tc) | reverse | .[0:$lim][]
    | .name
  ' 2>/dev/null || echo "  (list jq error)" >&2
}

for ev in ping push workflow_run pull_request; do
  pref="ingest/github/${ev}/"
  echo "## ${pref}"
  arr=$(fetch_data_array "$pref" "$LIST_CAP")
  print_names_newest_from_array "$arr" "$LIMIT" | while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" ]] && continue
    printf '%s\n' "$line"
  done
  echo
done

echo "## ingest/dead_letter/"
arr_dl=$(fetch_data_array "ingest/dead_letter/" "$LIST_CAP")
print_names_newest_from_array "$arr_dl" "$LIMIT" | while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -z "$line" ]] && continue
  printf '%s\n' "$line"
done
echo

echo "## ingest/"
arr_ingest=$(fetch_data_array "ingest/" "$LIST_CAP")
print_names_newest_from_array "$arr_ingest" "$LIMIT" | while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -z "$line" ]] && continue
  printf '%s\n' "$line"
done
