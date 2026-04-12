#!/usr/bin/env bash
# List newest object names under router ingest prefixes (filenames only, no JSON bodies).
#
# Usage:
#   OCI_CLI_PROFILE=DEFAULT SLI_OS_NAMESPACE=myns SLI_INGEST_BUCKET=mybucket \
#     ./tools/list_github_ingest_prefixes.sh [--limit N]
#
# Namespace: oci os ns get --query data --raw-output
#
# The merged section combines shallow lists (small limits) so the script stays fast;
# it does not scan the whole bucket.

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

# Per-prefix list cap (keep responses small; sort client-side by time).
LIST_CAP=200

echo "# profile=${PROFILE} namespace=${NS} bucket=${BUCKET} limit=${LIMIT}"
echo

# Newest-first object names only (one path per line).
print_names_newest() {
  local json="$1"
  local lim="$2"
  echo "$json" | jq -r --argjson lim "$lim" '
    [ .data[]? | select(type == "object") and (.name | type == "string")
      | {name, tc: (.["time-created"] // .timeCreated // "")} ]
    | sort_by(.tc) | reverse | .[0:$lim][]
    | .name
  ' 2>/dev/null || echo "  (list parse error)" >&2
}

for ev in ping push workflow_run pull_request; do
  pref="ingest/github/${ev}/"
  echo "## ${pref}"
  if ! out=$(oci os object list \
    --namespace-name "$NS" \
    --bucket-name "$BUCKET" \
    --prefix "$pref" \
    --limit "$LIST_CAP" \
    --fields 'name,timeCreated' 2>/dev/null); then
    echo "  (oci list failed)"
  else
    print_names_newest "$out" "$LIMIT" | while IFS= read -r line || [[ -n "$line" ]]; do
      [[ -z "$line" ]] && continue
      printf '%s\n' "$line"
    done
  fi
  echo
done

echo "## ingest/dead_letter/"
if ! out_dl=$(oci os object list \
  --namespace-name "$NS" \
  --bucket-name "$BUCKET" \
  --prefix "ingest/dead_letter/" \
  --limit "$LIST_CAP" \
  --fields 'name,timeCreated' 2>/dev/null); then
  echo "  (oci list failed)"
else
  print_names_newest "$out_dl" "$LIMIT" | while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" ]] && continue
    printf '%s\n' "$line"
  done
fi
echo

echo "## ingest/ (merged newest names: github/* + dead_letter/* + flat ingest/<file>)"
tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/gh-ingest.XXXXXX")
cleanup() { rm -rf "$tmpdir"; }
trap cleanup EXIT

gh_out='{"data":[]}'
if gh_json=$(oci os object list \
  --namespace-name "$NS" \
  --bucket-name "$BUCKET" \
  --prefix "ingest/github/" \
  --limit "$LIST_CAP" \
  --fields 'name,timeCreated' 2>/dev/null); then
  gh_out="$gh_json"
fi
dl_out='{"data":[]}'
if dl_json=$(oci os object list \
  --namespace-name "$NS" \
  --bucket-name "$BUCKET" \
  --prefix "ingest/dead_letter/" \
  --limit "$LIST_CAP" \
  --fields 'name,timeCreated' 2>/dev/null); then
  dl_out="$dl_json"
fi
flat_out='{"data":[]}'
if flat_json=$(oci os object list \
  --namespace-name "$NS" \
  --bucket-name "$BUCKET" \
  --prefix "ingest/" \
  --limit 120 \
  --fields 'name,timeCreated' 2>/dev/null); then
  flat_out="$flat_json"
fi

echo "$gh_out" | jq '[.data[]? | select(type == "object")]' >"$tmpdir/gh.json"
echo "$dl_out" | jq '[.data[]? | select(type == "object")]' >"$tmpdir/dl.json"
echo "$flat_out" | jq '[.data[]? | select(type == "object")]' >"$tmpdir/flat.json"

_merged_ok=1
if ! jq -rn --argjson lim "$LIMIT" --slurpfile gh "$tmpdir/gh.json" --slurpfile dl "$tmpdir/dl.json" --slurpfile raw "$tmpdir/flat.json" '
  ($gh[0] + $dl[0]) as $g
  | ($raw[0]
    | map(select((.name | type == "string") and (.name | test("^ingest/[^/]+$"))))) as $flat
  | ($g + $flat)
  | map({name, tc: (.["time-created"] // .timeCreated // "")})
  | unique_by(.name)
  | sort_by(.tc)
  | reverse
  | .[0:$lim][]
  | .name
' >"$tmpdir/merged.txt" 2>/dev/null; then
  _merged_ok=0
fi
if [[ "$_merged_ok" -ne 1 ]]; then
  echo "  (merge failed)"
elif [[ ! -s "$tmpdir/merged.txt" ]]; then
  echo "  (no objects matched)"
else
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" ]] && continue
    printf '%s\n' "$line"
  done <"$tmpdir/merged.txt"
fi
