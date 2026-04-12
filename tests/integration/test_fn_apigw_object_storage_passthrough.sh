#!/usr/bin/env bash
# Integration: API Gateway → router_passthrough Fn → Object Storage (pass-through JSONata $).
#
# Uses a **stable** NAME_PREFIX (default sli-router-passthrough-dev) under compartment **/SLI_tracker**
# so repeated runs reuse VCN / API GW / DNS — redeploy Fn code with **func.yaml version bump** +
# **FN_FORCE_DEPLOY=true** only when the handler changed.
# Router configuration in **Object Storage** (not bundled in the image): `config/routing.json` and
# `config/passthrough.jsonata` by default, uploaded from **tests/fixtures/fn_router_passthrough/** during **cycle_apigw_router_passthrough.sh**.
# Routing includes GitHub **`X-GitHub-Event`** paths under **`ingest/github/<event>/`** (see Sprint 23 / SLI-36).
#
# Does **not** tear down API GW / VCN / Fn app (same idea as not deleting buckets after every test).
# Sprint-end cleanup: **tests/cleanup_router_apigw_stack.sh** (and **tests/cleanup_sli_buckets.sh** for sli-* buckets).
#
# Requires: oci, fn, jq, curl; OCI auth (same as other integration tests).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
OCI_PROFILE="${SLI_INTEGRATION_OCI_PROFILE:-DEFAULT}"
export OCI_CLI_PROFILE="$OCI_PROFILE"

echo "=== Gate: OCI auth (profile=$OCI_PROFILE) ==="
oci iam region list --profile "$OCI_PROFILE" >/dev/null 2>&1

_fn_bin=$(command -v fn 2>/dev/null || true)
[ -z "${_fn_bin:-}" ] && [ -x /opt/homebrew/bin/fn ] && _fn_bin=/opt/homebrew/bin/fn
if [ -z "${_fn_bin:-}" ]; then
  echo "FAIL: fn CLI not found (required for cycle-apigw deploy)" >&2
  exit 1
fi

SCAFFOLD="${REPO_ROOT}/oci_scaffold"
FN_SRC="${REPO_ROOT}/fn/router_passthrough"

TS="$(date -u '+%Y%m%d%H%M%S')"
# Stable prefix reuses existing stack (avoids new API GW hostnames / DNS on every run).
NAME_PREFIX="${SLI_FN_APIGW_ROUTER_PREFIX:-sli-router-passthrough-dev}"
export NAME_PREFIX

export SLI_COMPARTMENT_PATH="${SLI_COMPARTMENT_PATH:-/SLI_tracker}"
export FN_FUNCTION_NAME="${FN_FUNCTION_NAME:-router_passthrough}"
export FN_FUNCTION_SRC_DIR="${FN_FUNCTION_SRC_DIR:-../fn/router_passthrough}"
export FN_ROUTER_AUTO_INGEST_BUCKET=true
export CYCLE_APIGW_TEST_EXPECT=router
# After router_core or routing fixture changes, deploy once (bump func.yaml). Default true so CI picks up new routing code.
export FN_FORCE_DEPLOY="${FN_FORCE_DEPLOY:-true}"

echo "=== npm install (Fn bundle) ==="
( cd "$FN_SRC" && npm install >/dev/null )

echo "=== cycle_apigw_router_passthrough (NAME_PREFIX=$NAME_PREFIX, compartment=$SLI_COMPARTMENT_PATH) ==="
# API Gateway hostnames can lag public DNS vs dig; stronger defaults for automated runs (override anytime).
export CYCLE_APIGW_POST_DNS_SLEEP="${CYCLE_APIGW_POST_DNS_SLEEP:-60}"
export CYCLE_APIGW_CURL_ATTEMPTS="${CYCLE_APIGW_CURL_ATTEMPTS:-15}"
export CYCLE_APIGW_CURL_RETRY_SLEEP="${CYCLE_APIGW_CURL_RETRY_SLEEP:-45}"

if ! bash "${REPO_ROOT}/tools/cycle_apigw_router_passthrough.sh"; then
  echo "FAIL: cycle_apigw_router_passthrough.sh exited non-zero" >&2
  exit 1
fi

STATE_FILE="${SCAFFOLD}/state-${NAME_PREFIX}.json"
if [[ ! -f "$STATE_FILE" ]]; then
  echo "FAIL: state file missing: $STATE_FILE" >&2
  exit 1
fi

DEPLOYMENT_ENDPOINT=$(jq -r '.apigw_deployment.endpoint // .apigw.deployment_endpoint // empty' "$STATE_FILE")
ROUTE_PATH=$(jq -r '.inputs.apigw_route_path // "/"' "$STATE_FILE")
BUCKET=$(jq -r '.bucket.name // empty' "$STATE_FILE")
NS=$(jq -r '.bucket.namespace // empty' "$STATE_FILE")

if [[ -z "$DEPLOYMENT_ENDPOINT" || -z "$BUCKET" || -z "$NS" ]]; then
  echo "FAIL: could not read endpoint/bucket/namespace from state" >&2
  jq . "$STATE_FILE" >&2 || true
  exit 1
fi

base="${DEPLOYMENT_ENDPOINT%/}"
path="/${ROUTE_PATH#/}"
url="${base}${path}"

OBJ="it-${TS}.json"
_payload=$(jq -n --arg fn "$OBJ" '{body: {integration: true, marker: "sli-35"}, source_meta: {file_name: $fn}}')

echo "=== POST (deterministic object ingest/${OBJ}) ==="
_resp=$(mktemp)
_http=$(command -p curl 2>/dev/null || true)
[ -z "${_http:-}" ] && _http=$(command -v curl 2>/dev/null || true)
if [ -z "${_http:-}" ]; then
  echo "FAIL: curl not found" >&2
  exit 1
fi

_http_code=$("$_http" -sS -o "$_resp" -w "%{http_code}" \
  --connect-timeout 30 --max-time 120 \
  -H "content-type: application/json" \
  --data "$_payload" \
  "$url" || true)
if [[ "$_http_code" != "200" ]]; then
  echo "FAIL: POST did not return HTTP 200 (got ${_http_code})" >&2
  cat "$_resp" >&2 || true
  rm -f "$_resp"
  exit 1
fi

if ! jq -e '.status == "routed"' "$_resp" >/dev/null 2>&1; then
  echo "FAIL: expected .status == routed in Fn response" >&2
  cat "$_resp" >&2 || true
  rm -f "$_resp"
  exit 1
fi
rm -f "$_resp"

echo "=== Verify object in bucket (with retries) ==="
_object_path="ingest/${OBJ}"
_ok=0
for _i in $(seq 1 12); do
  if oci os object get \
    --profile "$OCI_PROFILE" \
    --namespace-name "$NS" \
    --bucket-name "$BUCKET" \
    --name "$_object_path" \
    --file - 2>/dev/null | jq -e '.integration == true and .marker == "sli-35"' >/dev/null 2>&1; then
    _ok=1
    break
  fi
  sleep 5
done

if [[ "$_ok" -ne 1 ]]; then
  echo "FAIL: object ${_object_path} missing or body mismatch after retries" >&2
  exit 1
fi

PING_OBJ="it-ping-${TS}.json"
_ping_body=$(jq -c . "${REPO_ROOT}/tests/fixtures/github_webhook_samples/ping.json")
_payload_ping=$(jq -n --arg fn "$PING_OBJ" --argjson b "$_ping_body" \
  '{body: $b, headers: {"X-GitHub-Event": "ping"}, source_meta: {file_name: $fn}}')

echo "=== POST GitHub ping-shaped payload (ingest/github/ping/${PING_OBJ}) ==="
_http_code=$("$_http" -sS -o "$_resp" -w "%{http_code}" \
  --connect-timeout 30 --max-time 120 \
  -H "content-type: application/json" \
  --data "$_payload_ping" \
  "$url" || true)
if [[ "$_http_code" != "200" ]]; then
  echo "FAIL: ping POST did not return HTTP 200 (got ${_http_code})" >&2
  cat "$_resp" >&2 || true
  rm -f "$_resp"
  exit 1
fi
if ! jq -e '.status == "routed"' "$_resp" >/dev/null 2>&1; then
  echo "FAIL: ping response expected .status == routed" >&2
  cat "$_resp" >&2 || true
  rm -f "$_resp"
  exit 1
fi
rm -f "$_resp"

_ping_path="ingest/github/ping/${PING_OBJ}"
_ok_ping=0
for _i in $(seq 1 12); do
  if oci os object get \
    --profile "$OCI_PROFILE" \
    --namespace-name "$NS" \
    --bucket-name "$BUCKET" \
    --name "$_ping_path" \
    --file - 2>/dev/null | jq -e '.hook_id == 1' >/dev/null 2>&1; then
    _ok_ping=1
    break
  fi
  sleep 5
done

if [[ "$_ok_ping" -ne 1 ]]; then
  echo "FAIL: object ${_ping_path} missing or body mismatch after retries" >&2
  exit 1
fi

echo "PASS"
echo "  [info] Stack left running (API GW + Fn). Redeploy handler only: bump fn/router_passthrough/func.yaml version + FN_FORCE_DEPLOY=true"
echo "  [info] Sprint-end teardown (like bucket cleanup): NAME_PREFIX=$NAME_PREFIX ${REPO_ROOT}/tests/cleanup_router_apigw_stack.sh"
