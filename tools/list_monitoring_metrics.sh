#!/usr/bin/env bash
# List metric *definitions* in an OCI compartment (namespace + name + dimension key/value sets
# that Monitoring has seen for custom metrics), grouped by namespace.
# This is **not** time-series data: there are **no numeric values** or timestamps here. For values
# over a window use `oci monitoring metric-data summarize-metrics-data` or
# `tools/sli_compute_sli_metrics.js` (see integration tests).
#
# Complements ./tools/list_github_ingest_prefixes.sh (Object Storage keys vs Monitoring catalog).
# For bucket bodies + metric *values* in one run, see ./validate_router_ingest_and_metrics.sh.
#
# Default namespaces match this repo's custom metrics:
#   - github_actions — router fan-out (workflow_run_result, workflow_run_duration_s)
#   - sli_tracker — emit.sh outcome / SLI metrics
#
# Uses: oci monitoring metric list (see listMetrics API).
#
# Usage:
#   OCI_CLI_PROFILE=DEFAULT \
#   SLI_OCI_STATE_FILE=oci_scaffold/state-sli-router-passthrough-dev.json \
#     ./tools/list_monitoring_metrics.sh [--limit N]
#
# Compartment resolution (first hit wins):
#   --compartment-id OCID | SLI_METRIC_COMPARTMENT | OCI_MONITORING_COMPARTMENT_ID
#   | SLI_OCI_STATE_FILE / --state-file PATH  (reads .compartment.ocid or .inputs.oci_compartment)
#
# When using a state file, .inputs.oci_region is applied as --region if you did not pass --region.
#
# Optional:
#   --region REGION          (else OCI_CLI_REGION / region in profile)
#   --metric-name NAME       filter to one metric name (OCI --name)
#   --subtree                include metrics from subcompartments (--compartment-id-in-subtree true)
#   --any-namespace          one list call with no --namespace (respects --limit for the whole result)
#
# Some shells wrap `oci` and print banner lines to stdout before the JSON document.
# We strip everything before the first line that starts with '[' or '{' so jq always
# sees a single JSON value.

set -euo pipefail

LIMIT=30
REGION_ARGS=()
METRIC_NAME_ARGS=()
SUBTREE=0
ANY_NS=0
NAMESPACES=()
COMPARTMENT_ID=""
STATE_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --limit)
      LIMIT="${2:?--limit requires a number}"
      shift 2
      ;;
    --namespace)
      NAMESPACES+=("${2:?--namespace requires a value}")
      shift 2
      ;;
    --compartment-id)
      COMPARTMENT_ID="${2:?--compartment-id requires an OCID}"
      shift 2
      ;;
    --state-file)
      STATE_FILE="${2:?--state-file requires a path}"
      shift 2
      ;;
    --region)
      REGION_ARGS=(--region "${2:?--region requires a value}")
      shift 2
      ;;
    --metric-name)
      METRIC_NAME_ARGS=(--name "${2:?--metric-name requires a value}")
      shift 2
      ;;
    --subtree)
      SUBTREE=1
      shift
      ;;
    --any-namespace)
      ANY_NS=1
      shift
      ;;
    -h | --help)
      sed -n '1,45p' "$0" >&2
      exit 0
      ;;
    *)
      echo "Unknown option: $1 (try --help)" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$STATE_FILE" ]]; then
  STATE_FILE="${SLI_OCI_STATE_FILE:-}"
fi

if [[ -z "$COMPARTMENT_ID" ]]; then
  COMPARTMENT_ID="${SLI_METRIC_COMPARTMENT:-${OCI_MONITORING_COMPARTMENT_ID:-}}"
fi

if [[ -z "$COMPARTMENT_ID" && -n "$STATE_FILE" ]]; then
  if [[ ! -f "$STATE_FILE" ]]; then
    echo "State file not found: $STATE_FILE" >&2
    exit 1
  fi
  COMPARTMENT_ID="$(
    jq -r '.compartment.ocid // .inputs.oci_compartment // empty' "$STATE_FILE" 2>/dev/null || true
  )"
  if [[ ${#REGION_ARGS[@]} -eq 0 ]]; then
    _state_region="$(jq -r '.inputs.oci_region // empty' "$STATE_FILE" 2>/dev/null || true)"
    if [[ -n "${_state_region//[:space:]}" ]]; then
      REGION_ARGS=(--region "$_state_region")
    fi
  fi
fi

if [[ -z "$COMPARTMENT_ID" ]]; then
  echo "Usage: set SLI_METRIC_COMPARTMENT or OCI_MONITORING_COMPARTMENT_ID, pass --compartment-id OCID," >&2
  echo "  or set SLI_OCI_STATE_FILE / --state-file to an oci_scaffold state JSON (e.g. state-sli-router-passthrough-dev.json)." >&2
  echo "  jq hint: jq -r '.compartment.ocid' oci_scaffold/state-<NAME_PREFIX>.json" >&2
  echo "  $0 [--limit N] [--namespace NS]... [--region R] [--metric-name N] [--subtree] [--any-namespace] [--state-file PATH]" >&2
  exit 1
fi

PROFILE="${OCI_CLI_PROFILE:-DEFAULT}"
export OCI_CLI_PROFILE="$PROFILE"

if [[ ${#REGION_ARGS[@]} -eq 0 && -n "${OCI_CLI_REGION:-}" ]]; then
  REGION_ARGS=(--region "$OCI_CLI_REGION")
fi

SUBTREE_ARGS=()
if [[ "$SUBTREE" -eq 1 ]]; then
  SUBTREE_ARGS=(--compartment-id-in-subtree true)
fi

if [[ "$ANY_NS" -eq 1 ]]; then
  NAMESPACES=("")
fi
if [[ ${#NAMESPACES[@]} -eq 0 ]]; then
  NAMESPACES=(github_actions sli_tracker)
fi

echo "# profile=${PROFILE} compartment=${COMPARTMENT_ID} limit=${LIMIT}"
if [[ ${#REGION_ARGS[@]} -gt 0 ]]; then
  echo "# region args: ${REGION_ARGS[*]}"
fi
if [[ ${#METRIC_NAME_ARGS[@]} -gt 0 ]]; then
  echo "# metric name filter: ${METRIC_NAME_ARGS[*]}"
fi
if [[ "$SUBTREE" -eq 1 ]]; then
  echo "# compartment subtree: true"
fi
echo "# Output: OCI listMetrics — one row per distinct (namespace, name, dimensions)."
echo "# Columns (tab-separated): namespace | metric_name | dimensions"
echo "# dimensions: sorted as key=value key=value … (the metric’s label set)."
echo "# Values: not available from this API; use summarize-metrics-data / sli_compute_sli_metrics.js."
echo

strip_leading_nonjson() {
  sed -n '/^[[:space:]]*[[{]/,$p'
}

# Prints JSON array (metric list "data" field), or [].
fetch_metrics_json() {
  local ns="$1"
  local raw
  local ns_args=()
  if [[ -n "$ns" ]]; then
    ns_args=(--namespace "$ns")
  fi
  raw=$(
    oci monitoring metric list \
      "${REGION_ARGS[@]}" \
      --compartment-id "$COMPARTMENT_ID" \
      "${SUBTREE_ARGS[@]}" \
      "${ns_args[@]}" \
      "${METRIC_NAME_ARGS[@]}" \
      --limit "$LIMIT" \
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

# One line per definition: name + sorted dimensions.
format_metric_lines() {
  local arr_json="$1"
  if ! echo "$arr_json" | jq -e . >/dev/null 2>&1; then
    echo "  (list parse error: invalid JSON from oci)" >&2
    return
  fi
  echo "$arr_json" | jq -r '
    [ .[]?
      | select(type == "object")
      | {
          name: (.name // ""),
          ns: (.namespace // ""),
          dim: (."dimension-values" // .dimensions // {})
        }
      | select(.name != "")
      | . as $m
      | ($m.dim
          | if type == "object" then
              to_entries | sort_by(.key) | map("\(.key)=\(.value|tostring)") | join(" ")
            elif type == "array" then
              (map(
                  if type == "object" and (.name != null) and (.value != null) then "\(.name)=\(.value)"
                  else tostring end
                ) | join(" "))
            else
              ""
            end) as $ds
      | "\($m.ns)\t\($m.name)\t\($ds)"
    ]
    | unique
    | .[]
  ' 2>/dev/null || echo "  (list jq error)" >&2
}

for ns in "${NAMESPACES[@]}"; do
  if [[ -z "$ns" ]]; then
    echo "## (all namespaces, single page --limit=${LIMIT})"
  else
    echo "## namespace ${ns}"
  fi
  arr=$(fetch_metrics_json "$ns")
  _body="$(format_metric_lines "$arr" | sort -u || true)"
  printf '%s\t%s\t%s\n' "namespace" "metric_name" "dimensions"
  if [[ -n "$_body" ]]; then
    printf '%s\n' "$_body"
  fi
  echo
done
