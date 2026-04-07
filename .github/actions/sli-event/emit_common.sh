#!/usr/bin/env bash
# Shared pure helpers for SLI event payload assembly.
# No transport logic here. Source this file; do not execute directly.
# Used by emit_oci.sh and emit_curl.sh.

# Echo normalized JSON object: empty/null/invalid -> {}
sli_normalize_json_object() {
  local raw="${1:-}"
  [[ -z "$raw" || "$raw" == "null" ]] && raw='{}'
  if ! echo "$raw" | jq -e . >/dev/null 2>&1; then
    echo '{}'
    return 0
  fi
  echo "$raw" | jq -c .
}

# Build BASE log object from env (expects GITHUB_* + SLI_OUTCOME + optional SLI_TIMESTAMP).
# Schema: workflow.* = GitHub Actions runtime context; repo.* = repository/git state.
sli_build_base_json() {
  local ts="${SLI_TIMESTAMP:-}"
  [[ -z "$ts" ]] && ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  jq -nc \
    --arg ts        "$ts" \
    --arg outcome   "${SLI_OUTCOME:?SLI_OUTCOME required}" \
    --arg run_id    "${GITHUB_RUN_ID:-}" \
    --arg run_num   "${GITHUB_RUN_NUMBER:-}" \
    --arg run_att   "${GITHUB_RUN_ATTEMPT:-}" \
    --arg repo      "${GITHUB_REPOSITORY:-}" \
    --arg repo_id   "${GITHUB_REPOSITORY_ID:-}" \
    --arg ref       "${GITHUB_REF_NAME:-}" \
    --arg ref_full  "${GITHUB_REF:-}" \
    --arg sha       "${GITHUB_SHA:-}" \
    --arg wf        "${GITHUB_WORKFLOW:-}" \
    --arg wf_ref    "${GITHUB_WORKFLOW_REF:-}" \
    --arg job_id    "${GITHUB_JOB:-}" \
    --arg ev        "${GITHUB_EVENT_NAME:-}" \
    --arg actor     "${GITHUB_ACTOR:-}" \
    '{
      source:    "github-actions/sli-tracker",
      outcome:   $outcome,
      timestamp: $ts,
      workflow: {
        run_id:      $run_id,
        run_number:  $run_num,
        run_attempt: $run_att,
        name:        $wf,
        ref:         $wf_ref,
        job:         $job_id,
        event_name:  $ev,
        actor:       $actor
      },
      repo: {
        repository:    $repo,
        repository_id: $repo_id,
        ref:           $ref,
        ref_full:      $ref_full,
        sha:           $sha
      }
    }'
}

# Merge inputs-json + context-json; strip oci from flat merge (oci used only for transport).
sli_merge_flat_context() {
  local ij ctx
  ij="$(sli_normalize_json_object "${1:-}")"
  ctx="$(sli_normalize_json_object "${2:-}")"
  jq -n --argjson i "$ij" --argjson c "$ctx" '$i * ($c | del(.oci))'
}

# Extract .oci from context for transport backends.
sli_extract_oci_json() {
  local ctx
  ctx="$(sli_normalize_json_object "${1:-}")"
  echo "$ctx" | jq -c '.oci // {}'
}

# Paths from workflow outputs are literal strings: ~/.oci/config does not auto-expand.
sli_expand_oci_config_path() {
  local p="${1:-}"
  [[ -z "$p" ]] && { echo ""; return; }
  if [[ "$p" == "~" ]]; then
    echo "$HOME"
  elif [[ "${p:0:1}" == "~" && "${p:1:1}" == "/" ]]; then
    echo "${HOME}${p:1}"
  else
    echo "$p"
  fi
}

# Read a field value from an OCI config file for a given profile (no [DEFAULT] merge).
# Used by emit_curl.sh (signing) and emit_oci.sh (OCI CLI --auth).
# Usage: _oci_config_field <config_file> <profile_name> <field_name>
_oci_config_field() {
  local file="$1" profile="$2" field="$3"
  awk -v prof="[$profile]" -v key="$field" '
    /^\[/ { in_prof = ($0 == prof) }
    in_prof && $0 ~ "^" key "[ \t]*=" {
      sub(/^[^=]*=[ \t]*/, "")
      print
      exit
    }
  ' "$file"
}

# failure_reasons map from github.steps JSON (failed steps only).
sli_failure_reasons_from_steps_json() {
  local sj
  sj="$(sli_normalize_json_object "${1:-}")"
  echo "$sj" | jq -c '
    def upcase:
      ("a" | explode | .[0]) as $a | ("z" | explode | .[0]) as $z |
      explode | map(if . >= $a and . <= $z then . - 32 else . end) | implode;
    if type == "object" then
      reduce to_entries[] as $s ({};
        if ($s.value | type) == "object" and (($s.value).outcome // "") == "failure" then
          . + { ("SLI_FAILURE_REASON_" + (($s.key | upcase | gsub("-"; "_")))):
                ("step_id=" + $s.key + "; outputs=" + ((($s.value).outputs // {}) | tojson)) }
        else . end)
    else {} end'
}

# Merge failure_reasons: env companion keys override steps-derived keys.
sli_merge_failure_reasons() {
  local s="${1:-}" e="${2:-}"
  [[ -z "$s" ]] && s='{}'
  [[ -z "$e" ]] && e='{}'
  jq -n --argjson s "$s" --argjson e "$e" '$s * $e'
}

# SLI_FAILURE_REASON_* from current process environment.
sli_failure_reasons_from_env() {
  jq -n 'env | with_entries(select(.key | startswith("SLI_FAILURE_REASON_")))'
}

# Unescape top-level string fields that are JSON-encoded arrays or objects.
sli_unescape_json_fields() {
  local payload="${1:?}"
  echo "$payload" | jq -c '
    with_entries(
      if (.value | type) == "string" and ((.value | startswith("[")) or (.value | startswith("{")))
      then .value |= (. as $orig | try fromjson catch $orig)
      else . end
    )'
}

# Map SLI outcome string to OCI Monitoring metric value (1=success, 0=anything else).
sli_outcome_to_metric_value() {
  local outcome="${1:-}"
  if [[ "$outcome" == "success" ]]; then
    echo 1
  else
    echo 0
  fi
}

# Post an 'outcome' metric to OCI Monitoring via curl + OCI request signing.
# Usage: sli_emit_metric <log_entry_json> <oci_config_file> <oci_profile>
# Reads: SLI_METRIC_NAMESPACE (default: sli_tracker), OCI_API_DOMAIN, SLI_EMIT_CURL_VERBOSE.
sli_emit_metric() {
  local log_entry="$1" oci_config="$2" oci_profile="$3"

  local region tenancy user_ocid fingerprint key_file security_token_file security_token
  region="$(_oci_config_field "$oci_config" "$oci_profile" region)"
  tenancy="$(_oci_config_field "$oci_config" "$oci_profile" tenancy)"
  user_ocid="$(_oci_config_field "$oci_config" "$oci_profile" user)"
  fingerprint="$(_oci_config_field "$oci_config" "$oci_profile" fingerprint)"
  key_file="$(_oci_config_field "$oci_config" "$oci_profile" key_file)"
  key_file="$(sli_expand_oci_config_path "$key_file")"
  security_token_file="$(_oci_config_field "$oci_config" "$oci_profile" security_token_file)"
  security_token_file="$(sli_expand_oci_config_path "$security_token_file")"
  security_token=""
  if [[ -n "$security_token_file" && -f "$security_token_file" ]]; then
    security_token="$(cat "$security_token_file")"
  fi

  if [[ -z "$region" || -z "$key_file" || ! -f "$key_file" ]]; then
    echo "::warning::SLI metric push skipped — missing region or key_file in profile $oci_profile"
    return 0
  fi
  if [[ -z "$security_token" ]]; then
    if [[ -z "$user_ocid" || -z "$fingerprint" ]]; then
      echo "::warning::SLI metric push skipped — missing user/fingerprint in profile $oci_profile"
      return 0
    fi
  fi
  # compartmentId required by OCI Monitoring. Use SLI_METRIC_COMPARTMENT if set,
  # else fall back to tenancy from the OCI profile (root compartment).
  local _compartment="${SLI_METRIC_COMPARTMENT:-$tenancy}"

  local outcome metric_val ns ts
  outcome="$(echo "$log_entry" | jq -r '.outcome // "unknown"')"
  metric_val=$(sli_outcome_to_metric_value "$outcome")
  ns="${SLI_METRIC_NAMESPACE:-sli_tracker}"
  ts="$(echo "$log_entry" | jq -r '.timestamp')"

  local payload
  payload="$(jq -nc \
    --arg  ns    "$ns" \
    --arg  comp  "$_compartment" \
    --argjson val "$metric_val" \
    --arg  ts    "$ts" \
    --argjson entry "$log_entry" \
    '{"metricData": [{
      "namespace":     $ns,
      "name":          "outcome",
      "compartmentId": $comp,
      "dimensions": (
        {
          "workflow_name":   ($entry.workflow.name     // ""),
          "workflow_job":    ($entry.workflow.job      // ""),
          "repo_repository": ($entry.repo.repository   // ""),
          "repo_ref":        ($entry.repo.ref          // "")
        }
        | with_entries(select(.value != null and .value != ""))
        | if (length == 0) then {"emit_env":"local"} else . end
      ),
      "datapoints": [{"timestamp": $ts, "value": ($val | tonumber)}]
    }]}')"

  local _api_domain host date content_len body_hash request_target signed_headers signing_string signature key_id auth
  _api_domain="${OCI_API_DOMAIN:-oraclecloud.com}"
  host="telemetry-ingestion.${region}.oci.${_api_domain}"
  date="$(date -u "+%a, %d %b %Y %H:%M:%S GMT")"
  content_len="$(printf '%s' "$payload" | wc -c | tr -d ' ')"
  body_hash="$(printf '%s' "$payload" | openssl dgst -binary -sha256 | openssl base64 -A)"
  request_target="post /20180401/metrics"
  signed_headers="date (request-target) host content-length content-type x-content-sha256"
  signing_string="date: ${date}
(request-target): ${request_target}
host: ${host}
content-length: ${content_len}
content-type: application/json
x-content-sha256: ${body_hash}"

  signature="$(printf '%s' "$signing_string" | openssl dgst -sha256 -sign "$key_file" | openssl base64 -A)"
  if [[ -n "$security_token" ]]; then
    key_id="ST\$${security_token}"
  else
    key_id="${tenancy}/${user_ocid}/${fingerprint}"
  fi
  auth='Signature algorithm="rsa-sha256",headers="'"${signed_headers}"'",keyId="'"${key_id}"'",signature="'"${signature}"'",version="1"'

  local _resp_file _http_code _body
  _resp_file="$(mktemp)"
  _http_code="$(curl -s -w '%{http_code}' -o "$_resp_file" \
    -X POST \
    "https://${host}/20180401/metrics" \
    -H "Authorization: ${auth}" \
    -H "Date: ${date}" \
    -H "Host: ${host}" \
    -H "x-content-sha256: ${body_hash}" \
    -H "Content-Type: application/json" \
    -H "Content-Length: ${content_len}" \
    -d "$payload" 2>/dev/null)" || true
  _body="$(cat "$_resp_file" 2>/dev/null || true)"
  rm -f "$_resp_file"

  if [[ "$_http_code" =~ ^2[0-9][0-9]$ ]]; then
    echo "::notice::SLI metric pushed to OCI Monitoring (namespace: $ns, outcome: $outcome, value: $metric_val)"
  else
    echo "::warning::SLI metric push failed (non-fatal, HTTP ${_http_code})"
    if [[ -n "${SLI_EMIT_CURL_VERBOSE:-}" ]]; then
      echo "::warning::metric response: ${_body:0:500}"
    fi
  fi
}

# Combine base + flat + failure_reasons into final log entry JSON.
sli_build_log_entry() {
  local base flat fr result
  base="${1:?}"
  flat="${2:?}"
  fr="${3:?}"
  result=$(echo "$base" | jq --argjson ctx "$flat" '. + $ctx' | jq --argjson fr "$fr" '. + {failure_reasons: $fr}')
  sli_unescape_json_fields "$result"
}
