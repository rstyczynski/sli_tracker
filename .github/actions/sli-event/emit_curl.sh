#!/usr/bin/env bash
# SLI event emitter — curl + openssl backend (zero install).
# Sources emit_common.sh for payload assembly; pushes via OCI request signing.
# Supports API-key profiles and session-token profiles (keyId ST$<token>, same as oci-python-sdk Signer).
# Requires: curl, openssl, jq (all pre-installed on ubuntu-latest).

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/emit_common.sh"

# _oci_config_field is defined in emit_common.sh (session vs API-key field parsing).

sli_emit_main() {
  local TIMESTAMP BASE IJ CTX OCI_JSON FLAT LOG_ENTRY
  local FAILURE_REASONS_ENV FAILURE_REASONS_STEPS FAILURE_REASONS BATCH

  TIMESTAMP="${SLI_TIMESTAMP:-$(date -u +"%Y-%m-%dT%H:%M:%SZ")}"
  export SLI_TIMESTAMP="$TIMESTAMP"

  BASE="$(sli_build_base_json)"
  IJ="$(sli_normalize_json_object "${INPUTS_JSON:-}")"
  CTX="$(sli_normalize_json_object "${SLI_CONTEXT_JSON:-}")"
  OCI_JSON="$(sli_extract_oci_json "$CTX")"
  FLAT="$(sli_merge_flat_context "$IJ" "$CTX")"

  FAILURE_REASONS_ENV="$(sli_failure_reasons_from_env)"
  FAILURE_REASONS_STEPS="$(sli_failure_reasons_from_steps_json "${STEPS_JSON:-}")"
  FAILURE_REASONS="$(sli_merge_failure_reasons "$FAILURE_REASONS_STEPS" "$FAILURE_REASONS_ENV")"
  LOG_ENTRY="$(sli_build_log_entry "$BASE" "$FLAT" "$FAILURE_REASONS")"

  echo "::group::Received steps-json"
  echo "$STEPS_JSON" | jq .
  echo "::endgroup::"
  
  echo "::group::SLI Report payload"
  echo "$LOG_ENTRY" | jq .
  echo "::endgroup::"

  local OCI_LOG_ID OCI_CONFIG OCI_PROFILE
  OCI_LOG_ID="${SLI_OCI_LOG_ID:-}"
  OCI_LOG_ID="${OCI_LOG_ID:-$(echo "$OCI_JSON" | jq -r '."log-id" // empty')}"
  OCI_CONFIG="$(echo "$OCI_JSON" | jq -r '."config-file" // empty')"
  OCI_CONFIG="$(sli_expand_oci_config_path "$OCI_CONFIG")"
  OCI_PROFILE="$(echo "$OCI_JSON" | jq -r '."profile" // "DEFAULT"')"

  local EMIT_TARGET="${EMIT_TARGET:-log,metric}"

  if [[ -n "${SLI_SKIP_OCI_PUSH:-}" ]]; then
    echo "::notice::SLI OCI push skipped (SLI_SKIP_OCI_PUSH set)"
    return 0
  fi

  if [[ -n "$OCI_CONFIG" && -f "$OCI_CONFIG" ]]; then
    local TENANCY USER_OCID FINGERPRINT KEY_FILE REGION
    TENANCY="$(_oci_config_field "$OCI_CONFIG" "$OCI_PROFILE" tenancy)"
    USER_OCID="$(_oci_config_field "$OCI_CONFIG" "$OCI_PROFILE" user)"
    FINGERPRINT="$(_oci_config_field "$OCI_CONFIG" "$OCI_PROFILE" fingerprint)"
    KEY_FILE="$(_oci_config_field "$OCI_CONFIG" "$OCI_PROFILE" key_file)"
    REGION="$(_oci_config_field "$OCI_CONFIG" "$OCI_PROFILE" region)"
    local _api_domain
    _api_domain="$(_oci_config_field "$OCI_CONFIG" "$OCI_PROFILE" api_domain)"
    API_DOMAIN="${_api_domain:-${OCI_API_DOMAIN:-oraclecloud.com}}"
    KEY_FILE="$(sli_expand_oci_config_path "$KEY_FILE")"

    local SECURITY_TOKEN_FILE SECURITY_TOKEN
    SECURITY_TOKEN_FILE="$(_oci_config_field "$OCI_CONFIG" "$OCI_PROFILE" security_token_file)"
    SECURITY_TOKEN_FILE="$(sli_expand_oci_config_path "$SECURITY_TOKEN_FILE")"
    SECURITY_TOKEN=""
    if [[ -n "$SECURITY_TOKEN_FILE" && -f "$SECURITY_TOKEN_FILE" ]]; then
      SECURITY_TOKEN="$(cat "$SECURITY_TOKEN_FILE")"
    fi

    # ── Log push (EMIT_TARGET includes "log") ──
    if [[ "$EMIT_TARGET" == *log* ]]; then
      if [[ -n "$OCI_LOG_ID" ]]; then
        if [[ -n "$SECURITY_TOKEN" ]]; then
          if [[ -z "$KEY_FILE" || -z "$REGION" ]]; then
            echo "::warning::SLI curl log push failed — session token profile $OCI_PROFILE needs key_file and region"
          fi
        else
          if [[ -z "$TENANCY" || -z "$USER_OCID" || -z "$FINGERPRINT" || -z "$KEY_FILE" || -z "$REGION" ]]; then
            echo "::warning::SLI curl log push failed — missing fields in profile $OCI_PROFILE (need tenancy/user/fingerprint/key_file/region)"
          fi
        fi
        if [[ ! -f "$KEY_FILE" ]]; then
          echo "::warning::SLI curl log push failed — key_file not found: $KEY_FILE"
        else
          # Same wire format as `oci logging-ingestion put-logs`: POST body with specversion + logEntryBatches.
          local BATCH
          BATCH=$(jq -nc \
            --arg ts "$TIMESTAMP" \
            --argjson entry "$LOG_ENTRY" \
            '{
              specversion: "1.0",
              logEntryBatches: [{
                defaultlogentrytime: $ts,
                source: "github-actions/sli-tracker",
                type: "sli-event",
                entries: [{ data: ($entry | tostring), id: ($ts + "-sli"), time: $ts }]
              }]
            }')

          local HOST DATE BODY_HASH REQUEST_TARGET SIGNING_STRING SIGNATURE KEY_ID AUTH
          HOST="ingestion.logging.${REGION}.oci.${API_DOMAIN}"
          DATE="$(date -u "+%a, %d %b %Y %H:%M:%S GMT")"
          BODY_HASH="$(printf '%s' "$BATCH" | openssl dgst -binary -sha256 | openssl base64 -A)"
          REQUEST_TARGET="post /20200831/logs/${OCI_LOG_ID}/actions/push"

          # Byte length of UTF-8 body (${#BATCH} counts characters — wrong for non-ASCII).
          local _content_len
          _content_len="$(printf '%s' "$BATCH" | wc -c | tr -d ' ')"

          # Header order MUST match oci-python-sdk Signer (AbstractBaseSigner.create_signers):
          # generic: date, (request-target), host — body: content-length, content-type, x-content-sha256
          local _signed_headers="date (request-target) host content-length content-type x-content-sha256"
          SIGNING_STRING="date: ${DATE}
(request-target): ${REQUEST_TARGET}
host: ${HOST}
content-length: ${_content_len}
content-type: application/json
x-content-sha256: ${BODY_HASH}"

          SIGNATURE="$(printf '%s' "$SIGNING_STRING" | openssl dgst -sha256 -sign "$KEY_FILE" | openssl base64 -A)"

          if [[ -n "$SECURITY_TOKEN" ]]; then
            KEY_ID="ST\$${SECURITY_TOKEN}"
          else
            KEY_ID="${TENANCY}/${USER_OCID}/${FINGERPRINT}"
          fi
          # Same parameter order as oci.signer._PatchedHeaderSigner.HEADER_SIGNER_TEMPLATE
          AUTH='Signature algorithm="rsa-sha256",headers="'"${_signed_headers}"'",keyId="'"${KEY_ID}"'",signature="'"${SIGNATURE}"'",version="1"'

          local _resp_file _http_code _body
          _resp_file="$(mktemp)"
          _http_code="$(curl -s -w '%{http_code}' -o "$_resp_file" \
            -s -X POST \
            "https://${HOST}/20200831/logs/${OCI_LOG_ID}/actions/push" \
            -H "Authorization: ${AUTH}" \
            -H "Date: ${DATE}" \
            -H "Host: ${HOST}" \
            -H "x-content-sha256: ${BODY_HASH}" \
            -H "Content-Type: application/json" \
            -H "Content-Length: ${_content_len}" \
            -d "$BATCH" 2>/dev/null)" || true
          _body="$(cat "$_resp_file" 2>/dev/null || true)"
          rm -f "$_resp_file"
          if [[ "$_http_code" =~ ^2[0-9][0-9]$ ]]; then
            echo "::notice::SLI log entry pushed to OCI Logging (curl)"
          else
            echo "::warning::SLI report failed to push to OCI Logging (non-fatal, HTTP ${_http_code})"
            if [[ -n "${SLI_EMIT_CURL_VERBOSE:-}" ]]; then
              echo "::warning::curl response body: ${_body:0:500}"
            fi
          fi
        fi
      else
        echo "::notice::SLI log push skipped — OCI_LOG_ID not set (EMIT_TARGET=$EMIT_TARGET)"
      fi
    fi

    # ── Metric push (EMIT_TARGET includes "metric") ──
    if [[ "$EMIT_TARGET" == *metric* ]]; then
      sli_emit_metric "$LOG_ENTRY" "$OCI_CONFIG" "$OCI_PROFILE"
    fi

  elif [[ -n "$OCI_CONFIG" && ! -f "$OCI_CONFIG" ]]; then
    echo "::notice::SLI OCI push skipped — oci.config-file not found after ~ expansion: $OCI_CONFIG"
  else
    echo "::notice::SLI OCI push skipped — oci.config-file not set"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  sli_emit_main "$@" || echo "::warning::SLI emit script error (non-fatal)"
  exit 0
fi
