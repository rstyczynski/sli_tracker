#!/usr/bin/env bash
# SLI event emitter — curl + openssl backend (zero install).
# Sources emit_common.sh for payload assembly; pushes via OCI API-key request signing.
# Requires: curl, openssl, jq (all pre-installed on ubuntu-latest).

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/emit_common.sh"

# Read a field value from an OCI config file for a given profile.
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

  echo "::group::SLI Report payload"
  echo "$LOG_ENTRY" | jq .
  echo "::endgroup::"

  local OCI_LOG_ID OCI_CONFIG OCI_PROFILE
  OCI_LOG_ID="${SLI_OCI_LOG_ID:-}"
  OCI_LOG_ID="${OCI_LOG_ID:-$(echo "$OCI_JSON" | jq -r '."log-id" // empty')}"
  OCI_CONFIG="$(echo "$OCI_JSON" | jq -r '."config-file" // empty')"
  OCI_CONFIG="$(sli_expand_oci_config_path "$OCI_CONFIG")"
  OCI_PROFILE="$(echo "$OCI_JSON" | jq -r '."profile" // "DEFAULT"')"

  if [[ -n "${SLI_SKIP_OCI_PUSH:-}" ]]; then
    echo "::notice::SLI OCI push skipped (SLI_SKIP_OCI_PUSH set)"
    return 0
  fi

  if [[ -n "$OCI_LOG_ID" && -n "$OCI_CONFIG" && -f "$OCI_CONFIG" ]]; then
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

    if [[ -z "$TENANCY" || -z "$USER_OCID" || -z "$FINGERPRINT" || -z "$KEY_FILE" || -z "$REGION" ]]; then
      echo "::warning::SLI curl push failed — missing fields in profile $OCI_PROFILE (need tenancy/user/fingerprint/key_file/region)"
      return 0
    fi
    if [[ ! -f "$KEY_FILE" ]]; then
      echo "::warning::SLI curl push failed — key_file not found: $KEY_FILE"
      return 0
    fi

    BATCH=$(jq -nc \
      --arg ts "$TIMESTAMP" \
      --argjson entry "$LOG_ENTRY" \
      '[{
        "defaultlogentrytime": $ts,
        "source": "github-actions/sli-tracker",
        "type":   "sli-event",
        "entries": [{ "data": ($entry | tostring), "id": ($ts + "-sli"), "time": $ts }]
      }]')

    local HOST DATE BODY_HASH REQUEST_TARGET SIGNING_STRING SIGNATURE KEY_ID AUTH
    HOST="ingestion.logging.${REGION}.oci.${API_DOMAIN}"
    DATE="$(date -u "+%a, %d %b %Y %H:%M:%S GMT")"
    BODY_HASH="$(printf '%s' "$BATCH" | openssl dgst -binary -sha256 | openssl base64 -A)"
    REQUEST_TARGET="put /20200831/logs/${OCI_LOG_ID}/actions/push"

    SIGNING_STRING="(request-target): ${REQUEST_TARGET}
date: ${DATE}
host: ${HOST}
x-content-sha256: ${BODY_HASH}
content-type: application/json
content-length: ${#BATCH}"

    SIGNATURE="$(printf '%s' "$SIGNING_STRING" | openssl dgst -sha256 -sign "$KEY_FILE" | openssl base64 -A)"
    KEY_ID="${TENANCY}/${USER_OCID}/${FINGERPRINT}"
    AUTH='Signature version="1",keyId="'"${KEY_ID}"'",algorithm="rsa-sha256",headers="(request-target) date host x-content-sha256 content-type content-length",signature="'"${SIGNATURE}"'"'

    curl -s -f -X PUT \
      "https://${HOST}/20200831/logs/${OCI_LOG_ID}/actions/push" \
      -H "Authorization: ${AUTH}" \
      -H "Date: ${DATE}" \
      -H "Host: ${HOST}" \
      -H "x-content-sha256: ${BODY_HASH}" \
      -H "Content-Type: application/json" \
      -H "Content-Length: ${#BATCH}" \
      -d "$BATCH" \
    && echo "::notice::SLI log entry pushed to OCI Logging" \
    || echo "::warning::SLI report failed to push to OCI Logging (non-fatal)"

  elif [[ -n "$OCI_LOG_ID" && -n "$(echo "$OCI_JSON" | jq -r '."config-file" // empty')" && ! -f "$OCI_CONFIG" ]]; then
    echo "::notice::SLI OCI push skipped — oci.config-file not found after ~ expansion: $OCI_CONFIG"
  else
    echo "::notice::SLI OCI push skipped — oci.log-id or oci.config-file not set"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  sli_emit_main "$@" || echo "::warning::SLI emit script error (non-fatal)"
  exit 0
fi
