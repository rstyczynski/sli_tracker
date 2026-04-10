#!/usr/bin/env bash
# cycle_apigw_router_passthrough.sh — SLI-35: public API Gateway + router_passthrough Fn + Object Storage.
# Provisioning uses oci_scaffold ensure/*.sh only (reference copy in this repo; do not fork logic there).
# Function implementation: fn/router_passthrough/
#
# Usage (repository root):
#   NAME_PREFIX=mygw ./tools/cycle_apigw_router_passthrough.sh
#
# Optional environment:
#   SLI_COMPARTMENT_PATH (default: /SLI_tracker) — OCI compartment path for all resources
#   SLI_FN_CONTEXT (default: sli_tracker) — Fn CLI context name (compartment-id is updated each run)
#   FN_FUNCTION_NAME, FN_FUNCTION_SRC_DIR (default: ../fn/router_passthrough relative to oci_scaffold/)
#   FN_ROUTER_AUTO_INGEST_BUCKET=true|false (default: true)
#   CYCLE_APIGW_TEST_EXPECT=router|echo (default: router)
#   CYCLE_APIGW_RUN_TEARDOWN=true — only then runs do/teardown.sh (default: keep stack for Fn redeploys)
#   FN_OS_POLICY_SKIP=true
#   OCI_REGION, APIGW_*, FN_FORCE_DEPLOY, etc.
set -euo pipefail
set -E  # ensure ERR trap fires in functions/subshells
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCAFFOLD="$REPO_ROOT/oci_scaffold"
cd "$SCAFFOLD"
export PATH="$SCAFFOLD/do:$SCAFFOLD/resource:$PATH"

export FN_FUNCTION_NAME="${FN_FUNCTION_NAME:-router_passthrough}"
export FN_FUNCTION_SRC_DIR="${FN_FUNCTION_SRC_DIR:-../fn/router_passthrough}"
export FN_ROUTER_AUTO_INGEST_BUCKET="${FN_ROUTER_AUTO_INGEST_BUCKET:-true}"

: "${NAME_PREFIX:?NAME_PREFIX must be set}"
# Ensure each run resets summary counters even if caller exported a prior run id.
unset _OCI_SCAFFOLD_RUN_ID _OCI_SCAFFOLD_STATE_FILE_REPORTED
source "$SCAFFOLD/do/oci_scaffold.sh"

_on_err() {
  local ec=$?
  local line=${BASH_LINENO[0]:-unknown}
  local cmd=${BASH_COMMAND:-unknown}
  echo "  [FAIL] cycle_apigw_router_passthrough.sh failed (exit ${ec}) at line ${line}: ${cmd}" >&2
  if [ -n "${STATE_FILE:-}" ]; then
    echo "  [FAIL] State file: ${STATE_FILE}" >&2
  fi
}
trap _on_err ERR

# ── compartment (default /SLI_tracker; not oci_scaffold) ─────────────────────
SLI_COMPARTMENT_PATH="${SLI_COMPARTMENT_PATH:-/SLI_tracker}"
_state_set '.inputs.compartment_path' "$SLI_COMPARTMENT_PATH"
ensure-compartment.sh
COMPARTMENT_OCID=$(_state_get '.compartment.ocid')

# ── fn CLI context (name is arbitrary; compartment-id must match stack) ───────
SLI_FN_CONTEXT="${SLI_FN_CONTEXT:-sli_tracker}"
_fn_bin=$(command -v fn 2>/dev/null || true)
[ -z "${_fn_bin:-}" ] && [ -x /opt/homebrew/bin/fn ] && _fn_bin=/opt/homebrew/bin/fn
if [ -z "${_fn_bin:-}" ]; then
  echo "  [ERROR] fn CLI not found in PATH. Install/configure fn first." >&2
  exit 1
fi

_api_url="https://functions.${OCI_REGION}.oci.oraclecloud.com"
_registry=$("$_fn_bin" inspect context 2>/dev/null | awk -F': ' '$1 == "registry" {print $2; exit}' || true)
[ -z "${_registry:-}" ] && { echo "  [ERROR] Could not detect fn registry from current context." >&2; exit 1; }

if "$_fn_bin" list contexts 2>/dev/null | awk '{print $2}' | grep -qx "$SLI_FN_CONTEXT"; then
  _current_ctx=$("$_fn_bin" inspect context 2>/dev/null | awk -F': ' '/^Current context:/ {print $2; exit}' || true)
  if [ "${_current_ctx:-}" != "$SLI_FN_CONTEXT" ]; then
    "$_fn_bin" use context "$SLI_FN_CONTEXT" >/dev/null
  fi
  "$_fn_bin" update context oracle.compartment-id "$COMPARTMENT_OCID" >/dev/null
  "$_fn_bin" update context api-url "$_api_url" >/dev/null
  "$_fn_bin" update context registry "$_registry" >/dev/null
else
  "$_fn_bin" create context "$SLI_FN_CONTEXT" --provider oracle --api-url "$_api_url" --registry "$_registry" >/dev/null
  "$_fn_bin" use context "$SLI_FN_CONTEXT" >/dev/null
  "$_fn_bin" update context oracle.compartment-id "$COMPARTMENT_OCID" >/dev/null
fi

echo "  [INFO] compartment path: $SLI_COMPARTMENT_PATH (ocid: $COMPARTMENT_OCID)"
echo "  [INFO] fn CLI context: $SLI_FN_CONTEXT"

# ── seed inputs ────────────────────────────────────────────────────────────
_state_set '.inputs.oci_compartment' "$COMPARTMENT_OCID"
_state_set '.inputs.oci_region'      "$OCI_REGION"
_state_set '.inputs.name_prefix'     "$NAME_PREFIX"

# Public gateway requires a public subnet (public IPs allowed) and an Internet Gateway route.
_state_set '.inputs.subnet_prohibit_public_ip' 'false'
_state_set '.inputs.sl_ingress_cidr'           '0.0.0.0/0'

if [ -n "${FN_FUNCTION_NAME:-}" ]; then
  _state_set '.inputs.fn_function_name' "$FN_FUNCTION_NAME"
fi
if [ -n "${FN_FUNCTION_SRC_DIR:-}" ]; then
  _state_set '.inputs.fn_function_src_dir' "$FN_FUNCTION_SRC_DIR"
fi

if [ -n "${APIGW_ENDPOINT_TYPE:-}" ]; then
  _state_set '.inputs.apigw_endpoint_type' "$APIGW_ENDPOINT_TYPE"
fi
if [ -n "${APIGW_PATH_PREFIX:-}" ]; then
  _state_set '.inputs.apigw_path_prefix' "$APIGW_PATH_PREFIX"
fi
if [ -n "${APIGW_ROUTE_PATH:-}" ]; then
  _state_set '.inputs.apigw_route_path' "$APIGW_ROUTE_PATH"
fi
if [ -n "${APIGW_METHODS:-}" ]; then
  _state_set '.inputs.apigw_methods' "$APIGW_METHODS"
fi

if [ "${FN_ROUTER_AUTO_INGEST_BUCKET:-}" = "true" ]; then
  ensure-bucket.sh
  export FN_ROUTER_OCI_INGEST_BUCKET="$(_state_get '.bucket.name')"
fi

# ── setup (network + Fn app + function + apigw) ─────────────────────────────
ensure-vcn.sh
ensure-sl.sh
ensure-igw.sh
ensure-rt.sh
ensure-subnet.sh

ensure-fn_app.sh
ensure-fn_function.sh

if [ -n "${FN_ROUTER_OCI_INGEST_BUCKET:-}" ]; then
  FN_FUNCTION_OCID=$(_state_get '.fn_function.ocid')

  _fn_wait_deadline=$(( $(date +%s) + 300 ))
  while true; do
    _fn_st=$(oci fn function get --function-id "$FN_FUNCTION_OCID" --query 'data."lifecycle-state"' --raw-output 2>/dev/null) || _fn_st=""
    if [ "$_fn_st" = "ACTIVE" ]; then
      break
    fi
    if [ "$(date +%s)" -ge "$_fn_wait_deadline" ]; then
      _fail "Fn function ${FN_FUNCTION_OCID} not ACTIVE after 300s (state=${_fn_st:-unknown})"
      exit 1
    fi
    _info "Fn lifecycle ${_fn_st:-unknown}; waiting for ACTIVE …"
    sleep 5
  done

  _cfg_raw=$(oci fn function get --function-id "$FN_FUNCTION_OCID" --query 'data.config' --raw-output 2>/dev/null) || _cfg_raw='null'
  if [ -z "$_cfg_raw" ]; then
    _cfg_raw='null'
  fi
  if ! _cfg_merged=$(echo "$_cfg_raw" | jq -c --arg b "$FN_ROUTER_OCI_INGEST_BUCKET" '
    def norm:
      if . == null then {}
      elif type == "string" then (try fromjson catch {})
      elif type == "array" then
        reduce .[] as $i ({};
          if ($i | type) == "object" and ($i | has("key")) and ($i | has("value"))
          then . + {($i.key): ($i.value | tostring)}
          else . end)
      elif type == "object" then (. | map_values(tostring))
      else {} end;
    norm + {OCI_INGEST_BUCKET: $b}
  '); then
    _fail "Could not merge Fn config with OCI_INGEST_BUCKET (raw config: ${_cfg_raw})"
    exit 1
  fi

  _cfg_tmp=$(mktemp -t fn-config.XXXXXX)
  printf '%s\n' "$_cfg_merged" >"$_cfg_tmp"
  if ! oci fn function update \
    --function-id "$FN_FUNCTION_OCID" \
    --config "file://${_cfg_tmp}" \
    --force \
    --wait-for-state ACTIVE \
    --max-wait-seconds 300 >/dev/null; then
    rm -f "$_cfg_tmp"
    _fail "oci fn function update --config failed (see stderr above)"
    exit 1
  fi
  rm -f "$_cfg_tmp"
  _done "Fn config OCI_INGEST_BUCKET=$FN_ROUTER_OCI_INGEST_BUCKET"
fi

if [ "${FN_ROUTER_AUTO_INGEST_BUCKET:-}" = "true" ]; then
  bash "$REPO_ROOT/tools/ensure_fn_resource_principal_os_policy.sh"
fi

ensure-apigw_fn_policy.sh
ensure-apigw.sh
ensure-apigw_deployment.sh

# ── test: call deployment endpoint over Internet ───────────────────────────
DEPLOYMENT_ENDPOINT=$(_state_get '.apigw_deployment.endpoint')
if [ -z "${DEPLOYMENT_ENDPOINT:-}" ]; then
  DEPLOYMENT_ENDPOINT=$(_state_get '.apigw.deployment_endpoint')
fi
ROUTE_PATH=$(_state_get '.inputs.apigw_route_path')
ROUTE_PATH="${ROUTE_PATH:-/}"

_info "API endpoint: ${DEPLOYMENT_ENDPOINT:-<unknown>}"

# Bash has no null; _state_get uses jq 'select(. != null)' so JSON null becomes empty.
if [ -z "${DEPLOYMENT_ENDPOINT:-}" ]; then
  _fail "Missing deployment endpoint (API GW deploy may have failed)."
  exit 1
fi

base="${DEPLOYMENT_ENDPOINT%/}"
path="/${ROUTE_PATH#/}"
url="${base}${path}"

_cycle_expect="${CYCLE_APIGW_TEST_EXPECT:-router}"
if [ "$_cycle_expect" = "router" ]; then
  payload='{"message":"hello from router cycle","ts":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}'
else
  payload='{"message":"hello from cycle-apigw","ts":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}'
fi
resp=$(mktemp -t apigw-call.XXXXXX)
_curl_code_file=$(mktemp -t apigw-curlcode.XXXXXX)
_curl_err_file=$(mktemp -t apigw-curlerr.XXXXXX)
: >"$resp"
http_code="000"
_curl_exit=0

# Public API GW hostnames often lag OCI "deployment ready"; wait for DNS before the
# single POST (still one Fn invocation — no retry POSTs).
_host=$(echo "$DEPLOYMENT_ENDPOINT" | sed -E 's#^https?://##' | sed -E 's#/.*$##')
_apigw_skip_curl=false
_dns_max=300
if [ -n "$_host" ]; then
  if ! _wait_dns_hostname "$_host" "DNS (API Gateway)" "$_dns_max" 5; then
    _fail "Gateway hostname still not in DNS after ${_dns_max}s: $_host"
    _apigw_skip_curl=true
  fi
fi

# Prefer standard-PATH curl: some shells wrap `curl` (e.g. OCI helpers); wrappers
# often break background redirects and yield an empty HTTP code file.
_curl_bin=$(command -p curl 2>/dev/null || true)
[ -z "${_curl_bin:-}" ] && [ -x /usr/bin/curl ] && _curl_bin=/usr/bin/curl
[ -z "${_curl_bin:-}" ] && _curl_bin=$(command -v curl 2>/dev/null || true)

if [ "$_apigw_skip_curl" = true ]; then
  :
elif [ -z "${_curl_bin:-}" ]; then
  _fail "curl not found in PATH"
else
  # dig can see the hostname before the resolver curl uses; brief pause + retries on DNS/connect.
  if [ -n "${_host:-}" ]; then
    _pds="${CYCLE_APIGW_POST_DNS_SLEEP:-45}"
    case "$_pds" in
      '' | *[!0-9]*) _pds=45 ;;
    esac
    if [ "$_pds" -gt 0 ] 2>/dev/null; then
      _info "Post-DNS stabilization sleep ${_pds}s (CYCLE_APIGW_POST_DNS_SLEEP=0 to skip) …"
      sleep "$_pds"
    fi
  fi

  _max_try="${CYCLE_APIGW_CURL_ATTEMPTS:-12}"
  case "$_max_try" in
    '' | *[!0-9]*) _max_try=12 ;;
  esac
  _retry_sleep="${CYCLE_APIGW_CURL_RETRY_SLEEP:-45}"
  case "$_retry_sleep" in
    '' | *[!0-9]*) _retry_sleep=45 ;;
  esac

  _try=1
  http_code="000"
  _curl_exit=1
  while [ "$_try" -le "$_max_try" ]; do
    : >"$_curl_code_file"
    : >"$_curl_err_file"
    _info "API Gateway POST attempt ${_try}/${_max_try} (same payload; Fn may run once per success)"

    trap '' ERR
    set +e
    "$_curl_bin" -sS -o "$resp" -w "%{http_code}" \
      --connect-timeout 30 --max-time 120 \
      -H "content-type: application/json" \
      --data "$payload" \
      "$url" >"$_curl_code_file" 2>"$_curl_err_file"
    _curl_exit=$?
    set -e
    trap _on_err ERR

    http_code=$(tr -d ' \n\r' <"$_curl_code_file" 2>/dev/null || true)
    [ -z "$http_code" ] && http_code="000"
    _curl_err=$(head -8 "$_curl_err_file" 2>/dev/null | paste -sd ' ' - || true)

    if [ "$http_code" = "200" ] && [ "$_curl_exit" -eq 0 ]; then
      break
    fi
    [ -n "$_curl_err" ] && _info "curl: ${_curl_err}"
    if [ "$_try" -lt "$_max_try" ]; then
      _info "Waiting ${_retry_sleep}s before retry …"
      sleep "$_retry_sleep"
    fi
    _try=$((_try + 1))
  done
  rm -f "$_curl_code_file" "$_curl_err_file"
fi

_jq_ok=1
if [ "$http_code" = "200" ]; then
  if [ "$_cycle_expect" = "router" ]; then
    jq -e '.status == "routed" and (.deliveries | type == "array") and ((.deliveries | length) >= 1)' "$resp" >/dev/null 2>&1 || _jq_ok=0
  else
    jq -e '.ok == true and (.echo.message // "") != ""' "$resp" >/dev/null 2>&1 || _jq_ok=0
  fi
else
  _jq_ok=0
fi

if [ "$_jq_ok" -eq 1 ]; then
  _ok "API GW call OK: $url (expect=${_cycle_expect})"
else
  _fail "API GW call failed: HTTP $http_code ($url) (expect=${_cycle_expect})"
  _info "Response: $(cat "$resp" 2>/dev/null || true)"
fi

rm -f "$resp"

print_summary

# ── summary (no teardown by default — reuse GW/VCN; redeploy Fn via func.yaml bump) ──
echo ""
_ep="$(_state_get '.apigw_deployment.endpoint')"
[ -z "${_ep:-}" ] && _ep="$(_state_get '.apigw.deployment_endpoint')"
echo "  API endpoint: ${_ep:-}"
echo "  Fn App      : $(_state_get '.fn_app.ocid')"
echo "  Fn Function : $(_state_get '.fn_function.ocid')"
_gw="$(_state_get '.apigw_gateway.ocid')"
[ -z "${_gw:-}" ] && _gw="$(_state_get '.apigw.gateway_ocid')"
_dep="$(_state_get '.apigw_deployment.ocid')"
[ -z "${_dep:-}" ] && _dep="$(_state_get '.apigw.deployment_ocid')"
echo "  ApiGw       : ${_gw:-}"
echo "  Deployment  : ${_dep:-}"
echo "  State file  : $STATE_FILE"
echo ""

if [ "${CYCLE_APIGW_RUN_TEARDOWN:-}" = "true" ]; then
  _info "CYCLE_APIGW_RUN_TEARDOWN=true — tearing down stack (use only for broken deploys or sprint-end cleanup)"
  NAME_PREFIX=$NAME_PREFIX do/teardown.sh
else
  _info "Teardown skipped (default). Reuse: NAME_PREFIX=$NAME_PREFIX — bump fn/router_passthrough/func.yaml version + FN_FORCE_DEPLOY=true to redeploy code only."
  _info "Sprint-end cleanup (same idea as tests/cleanup_sli_buckets.sh): NAME_PREFIX=$NAME_PREFIX ./tests/cleanup_router_apigw_stack.sh"
fi
