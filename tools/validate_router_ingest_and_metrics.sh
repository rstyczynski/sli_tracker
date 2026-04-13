#!/usr/bin/env bash
# Validate recent router ingest in Object Storage and metric *values* in OCI Monitoring.
#
# - Bucket: lists newest object keys under selected prefixes; optionally peeks JSON summary
#   of the newest `ingest/github/workflow_run/*` object.
# - Metrics: `oci monitoring metric-data summarize-metrics-data` for
#   `github_actions.workflow_run_result` and `workflow_run_duration_s` (values + timestamps).
#
# Requires: oci, jq. Compartment / bucket / region from oci_scaffold state (same idea as
# `list_monitoring_metrics.sh` / `list_github_ingest_prefixes.sh`).
#
# Usage:
#   OCI_CLI_PROFILE=DEFAULT \
#   SLI_OCI_STATE_FILE=oci_scaffold/state-sli-router-passthrough-dev.json \
#     ./tools/validate_router_ingest_and_metrics.sh [--minutes 45] [--limit 5] [--no-peek]
#
# Object Storage: `oci os object list` returns **prefix order**, not time order. This script sorts
# by `timeCreated` client-side. For busy prefixes (`workflow_run`, `dead_letter`) it fetches up to
# SLI_VALIDATE_OS_LIST_LIMIT objects (default 1000) so "newest keys" and "peek newest" match.
# Raise the env var if you have more objects than that under one prefix.

set -euo pipefail

STATE_FILE="${SLI_OCI_STATE_FILE:-}"
MINUTES=45
LIMIT=5
PEEK=1
OS_DENSE_LIMIT="${SLI_VALIDATE_OS_LIST_LIMIT:-1000}"
OS_NORMAL_LIMIT=200

while [[ $# -gt 0 ]]; do
  case "$1" in
    --state-file)
      STATE_FILE="${2:?--state-file requires a path}"
      shift 2
      ;;
    --minutes)
      MINUTES="${2:?--minutes requires a number}"
      shift 2
      ;;
    --limit)
      LIMIT="${2:?--limit requires a number}"
      shift 2
      ;;
    --no-peek)
      PEEK=0
      shift
      ;;
    -h | --help)
      sed -n '1,22p' "$0" >&2
      exit 0
      ;;
    *)
      echo "Unknown option: $1 (try --help)" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$STATE_FILE" || ! -f "$STATE_FILE" ]]; then
  echo "Set SLI_OCI_STATE_FILE or pass --state-file to oci_scaffold state JSON." >&2
  exit 1
fi

PROFILE="${OCI_CLI_PROFILE:-DEFAULT}"
export OCI_CLI_PROFILE="$PROFILE"

NS="$(jq -r '.bucket.namespace // empty' "$STATE_FILE")"
BUCKET="$(jq -r '.bucket.name // empty' "$STATE_FILE")"
COMPARTMENT="$(jq -r '.compartment.ocid // .inputs.oci_compartment // empty' "$STATE_FILE")"
REGION="$(jq -r '.inputs.oci_region // empty' "$STATE_FILE")"

if [[ -z "$NS" || -z "$BUCKET" ]]; then
  echo "State file missing .bucket.namespace or .bucket.name: $STATE_FILE" >&2
  exit 1
fi
if [[ -z "$COMPARTMENT" ]]; then
  echo "State file missing compartment OCID: $STATE_FILE" >&2
  exit 1
fi

REGION_ARGS=()
if [[ -n "${REGION//[:space:]}" ]]; then
  REGION_ARGS=(--region "$REGION")
fi

END="$(date -u '+%Y-%m-%dT%H:%M:%S.000Z')"
START="$(date -u -v-"${MINUTES}"M '+%Y-%m-%dT%H:%M:%S.000Z' 2>/dev/null || date -u --date="-${MINUTES} minutes" '+%Y-%m-%dT%H:%M:%S.000Z')"

strip_leading_nonjson() {
  sed -n '/^[[:space:]]*[[{]/,$p'
}

fetch_data_array() {
  local prefix="$1"
  local lim="${2:-200}"
  local raw
  raw=$(
    oci os object list \
      "${REGION_ARGS[@]}" \
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

print_newest_names() {
  local arr_json="$1"
  local lim="$2"
  echo "$arr_json" | jq -r --argjson lim "$lim" '
    [ .[]?
      | select(type == "object" and (.name | type == "string"))
      | {name, tc: (.["time-created"] // .timeCreated // "")} ]
    | sort_by(.tc) | reverse | .[0:$lim][]
    | .name
  ' 2>/dev/null || true
}

echo "# validate_router_ingest_and_metrics"
echo "# profile=${PROFILE} state=${STATE_FILE}"
echo "# bucket=${BUCKET} namespace=${NS}"
echo "# compartment=${COMPARTMENT}"
echo "# monitoring window: ${START} .. ${END} (last ${MINUTES} min)"
if [[ ${#REGION_ARGS[@]} -gt 0 ]]; then
  echo "# region: ${REGION_ARGS[1]}"
fi
echo "# OS list page: workflow_run + dead_letter use limit=${OS_DENSE_LIMIT} (others ${OS_NORMAL_LIMIT}) for time-sort"
echo

WF_ARR='[]'
DL_ARR='[]'

echo "=== Object Storage — newest keys (limit ${LIMIT}) ==="
for pref in \
  "ingest/github/workflow_run/" \
  "ingest/dead_letter/" \
  "ingest/github/ping/" \
  "ingest/no_github_event/"; do
  echo "## ${pref}"
  fetch_lim="$OS_NORMAL_LIMIT"
  if [[ "$pref" == "ingest/github/workflow_run/" || "$pref" == "ingest/dead_letter/" ]]; then
    fetch_lim="$OS_DENSE_LIMIT"
  fi
  arr=$(fetch_data_array "$pref" "$fetch_lim")
  if [[ "$pref" == "ingest/github/workflow_run/" ]]; then
    WF_ARR="$arr"
  elif [[ "$pref" == "ingest/dead_letter/" ]]; then
    DL_ARR="$arr"
  fi
  lines=$(print_newest_names "$arr" "$LIMIT")
  if [[ -z "${lines//[:space:]}" ]]; then
    echo "  (none)"
  else
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ -z "$line" ]] && continue
      printf '  %s\n' "$line"
    done <<<"$lines"
  fi
  echo
done

if [[ "$PEEK" -eq 1 ]]; then
  wf_new="$(print_newest_names "$WF_ARR" 1 | head -1)"
  echo "=== Object Storage — peek newest workflow_run object (summary JSON) ==="
  if [[ -z "$wf_new" ]]; then
    echo "  (no ingest/github/workflow_run/ object to peek)"
  else
    echo "# object: ${wf_new}"
    _raw="$(
      oci os object get \
        "${REGION_ARGS[@]}" \
        --namespace-name "$NS" \
        --bucket-name "$BUCKET" \
        --name "$wf_new" \
        --file - 2>/dev/null | strip_leading_nonjson
    )" || _raw=""
    if echo "$_raw" | jq -e . >/dev/null 2>&1; then
      echo "$_raw" | jq -c '{
        action,
        repository: (.repository.full_name // null),
        workflow_run: (.workflow_run // null | {
          name, status, conclusion, event, created_at, updated_at
        })
      }' 2>/dev/null || echo "$_raw" | jq -c . | head -c 4000
    else
      echo "  (non-JSON or empty body, first 240 bytes:)"
      printf '%s\n' "${_raw:0:240}"
    fi
    echo "# note: bucket keeps every workflow_run webhook; Monitoring only ingests when action=completed (see workflow_run_metric.jsonata)."
  fi
  echo

  dl_new="$(print_newest_names "$DL_ARR" 1 | head -1)"
  echo "=== Object Storage — peek newest dead_letter object (top-level keys only) ==="
  if [[ -z "$dl_new" ]]; then
    echo "  (none — good if routing/metrics are healthy)"
  else
    echo "# object: ${dl_new}"
    _dl="$(
      oci os object get \
        "${REGION_ARGS[@]}" \
        --namespace-name "$NS" \
        --bucket-name "$BUCKET" \
        --name "$dl_new" \
        --file - 2>/dev/null | strip_leading_nonjson
    )" || _dl=""
    if echo "$_dl" | jq -e . >/dev/null 2>&1; then
      echo "$_dl" | jq -c 'if type == "object" then (keys | sort) else . end' 2>/dev/null || echo "$_dl" | head -c 800
    else
      echo "$_dl" | head -c 800
    fi
  fi
  echo
fi

summarize_to_table() {
  local title="$1"
  local mql="$2"
  echo "## ${title}"
  local raw
  raw=$(
    oci monitoring metric-data summarize-metrics-data \
      "${REGION_ARGS[@]}" \
      --compartment-id "$COMPARTMENT" \
      --namespace github_actions \
      --start-time "$START" \
      --end-time "$END" \
      --resolution 1m \
      --query-text "$mql" \
      --query 'data' \
      --raw-output 2>/dev/null | strip_leading_nonjson
  ) || raw="[]"
  raw="${raw//$'\r'/}"
  if [[ -z "${raw//[:space:]}" ]] || [[ "$raw" == 'null' ]]; then
    raw='[]'
  fi
  if ! echo "$raw" | jq -e . >/dev/null 2>&1; then
    echo "  (invalid JSON from oci summarize-metrics-data)"
    echo
    return
  fi
  local cnt
  cnt="$(echo "$raw" | jq '[.[]? | ."aggregated-datapoints"[]?] | length' 2>/dev/null || echo 0)"
  if [[ "${cnt:-0}" -eq 0 ]]; then
    echo "  (no aggregated datapoints in window — ingest delay, empty compartment, or no matching series)"
  else
    echo "$raw" | jq -r '
      .[]?
      | select(type == "object")
      | . as $s
      | ($s.dimensions // {} | to_entries | sort_by(.key) | map("\(.key)=\(.value)") | join(" ")) as $dim
      | ($s."aggregated-datapoints" // [])[]
      | [$s.name // "", $dim, (.timestamp // ""), (.value // "")] | @tsv
    ' 2>/dev/null | column -t -s $'\t' 2>/dev/null || echo "$raw" | jq .
  fi
  echo
}

echo "=== OCI Monitoring — datapoints (values) in window ==="
echo "# MQL resolution 1m; columns: metric_name  dimensions  timestamp  value"
summarize_to_table "github_actions.workflow_run_result[5m].mean()" 'workflow_run_result[5m].mean()'
summarize_to_table "github_actions.workflow_run_duration_s[5m].mean()" 'workflow_run_duration_s[5m].mean()'

echo "# Tip: metric *definitions* (no values): ./tools/list_monitoring_metrics.sh --state-file \"${STATE_FILE}\""
echo "# Tip: more bucket keys: SLI_OS_NAMESPACE=${NS} SLI_INGEST_BUCKET=${BUCKET} ./tools/list_github_ingest_prefixes.sh"
