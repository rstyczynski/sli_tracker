#!/usr/bin/env bash
set -euo pipefail

# Live integration test for SLI-20:
# - emit two outcome datapoints with a unique dimension set
# - query them back via tools/sli_compute_sli_metrics.js live mode
#
# Requires a working local OCI profile (same assumption as other integration tests).

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ACTION_DIR="${REPO_ROOT}/.github/actions/sli-event"
TOOL="${REPO_ROOT}/tools/sli_compute_sli_metrics.js"

OCI_INT_PROFILE="${SLI_INTEGRATION_OCI_PROFILE:-SLI_TEST}"

if [[ "${SLI_SKIP_COMPUTE_METRICS_LIVE:-}" == "1" ]]; then
  echo "SKIP: SLI_SKIP_COMPUTE_METRICS_LIVE=1 (Monitoring ingest latency / CI without live metrics)"
  exit 0
fi

if ! command -v oci >/dev/null 2>&1; then
  echo "SKIP: oci CLI not found (required to resolve tenancy OCID + auth gate)"
  exit 0
fi

echo "=== Auth gate: OCI profile $OCI_INT_PROFILE ==="
if ! oci iam region list --profile "$OCI_INT_PROFILE" >/dev/null 2>&1; then
  if oci iam region list --profile "$OCI_INT_PROFILE" --auth security_token >/dev/null 2>&1; then
    echo "OK: OCI profile valid (security_token)."
  else
    echo "SKIP: OCI profile $OCI_INT_PROFILE not currently valid (no auth loop in this test)."
    exit 0
  fi
else
  echo "OK: OCI profile valid."
fi

TENANCY_OCID="$(awk -v prof="[$OCI_INT_PROFILE]" -v key="tenancy" '
  /^\[/ { in_prof = ($0 == prof) }
  in_prof && $0 ~ "^" key "[ \t]*=" { sub(/^[^=]*=[ \t]*/, ""); print; exit }
' "${HOME}/.oci/config" 2>/dev/null || true)"

[[ -n "$TENANCY_OCID" ]] || { echo "FAIL: could not resolve tenancy OCID"; exit 1; }

MARKER="sli20-live-$(date -u +%s)"

export GITHUB_WORKFLOW="SLI-20 live ${MARKER}"
export GITHUB_JOB="emit-metric-local"
export GITHUB_REPOSITORY="rstyczynski/sli_tracker"

export INPUTS_JSON="{}"
export STEPS_JSON='{"test_script":{"outcome":"failure","outputs":{}}}'

export EMIT_BACKEND=curl
export EMIT_TARGET=metric
export SLI_METRIC_COMPARTMENT="$TENANCY_OCID"
export SLI_CONTEXT_JSON='{"oci":{"config-file":"~/.oci/config","profile":"'"$OCI_INT_PROFILE"'"}}'

echo "=== Emit: success ==="
SLI_OUTCOME=success bash "${ACTION_DIR}/emit_curl.sh" >/dev/null
echo "=== Emit: failure ==="
SLI_OUTCOME=failure bash "${ACTION_DIR}/emit_curl.sh" >/dev/null

# Query back with dimension filter workflow_name (maps to workflow.name in metric dims)
DIM_WORKFLOW_NAME="SLI-20 live ${MARKER}"

_POLL_ATTEMPTS="${SLI_METRICS_LIVE_POLL_ATTEMPTS:-20}"
_POLL_SLEEP="${SLI_METRICS_LIVE_POLL_SLEEP_SEC:-30}"
echo "=== Poll live SLI compute (attempts=${_POLL_ATTEMPTS}, sleep=${_POLL_SLEEP}s) ==="
attempt=0
while [[ $attempt -lt "$_POLL_ATTEMPTS" ]]; do
  attempt=$((attempt + 1))
  sleep "$_POLL_SLEEP"
  # Use 1m resolution: 1d buckets often omit same-day / just-ingested custom metric points in summarizeMetricsData.
  out="$("$TOOL" \
    --window-days 1 \
    --mql-resolution 1m \
    --namespace sli_tracker \
    --metric-name outcome \
    --compartment-id "$TENANCY_OCID" \
    --oci-config-file "~/.oci/config" \
    --oci-profile "$OCI_INT_PROFILE" \
    --dimension workflow_name="$DIM_WORKFLOW_NAME" \
    --output json || true)"

  total="$(echo "$out" | jq -r '.total_count // 0' 2>/dev/null || echo 0)"
  if [[ "$total" == "2" ]]; then
    success="$(echo "$out" | jq -r '.success_count' 2>/dev/null || echo "")"
    sli="$(echo "$out" | jq -r '.sli' 2>/dev/null || echo "")"
    [[ "$success" == "1" ]] || { echo "FAIL: expected success_count=1, got $success"; echo "$out"; exit 1; }
    python3 - "$sli" <<'PY'
import sys
v=float(sys.argv[1])
assert abs(v - 0.5) < 1e-12, v
PY
    echo "PASS: live SLI query returned total=2 success=1 sli=0.5"
    exit 0
  fi
  echo "# not ready yet (total_count=$total), attempt $attempt/${_POLL_ATTEMPTS}"
done

echo "FAIL: live SLI query did not observe 2 datapoints within polling window (tune SLI_METRICS_LIVE_POLL_* or set SLI_SKIP_COMPUTE_METRICS_LIVE=1)"
exit 1

