#!/usr/bin/env bash
# SLI event emitter — OCI CLI backend.
# Sources emit_common.sh for payload assembly; pushes via oci logging-ingestion put-logs.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/emit_common.sh"

sli_emit_main() {
  local TIMESTAMP BASE IJ CTX OCI_JSON FLAT LOG_ENTRY FAILURE_REASONS_ENV FAILURE_REASONS_STEPS FAILURE_REASONS BATCH

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
  OCI_CONFIG=$(echo "$OCI_JSON" | jq -r '."config-file" // empty')
  OCI_CONFIG="$(sli_expand_oci_config_path "$OCI_CONFIG")"
  OCI_PROFILE=$(echo "$OCI_JSON" | jq -r '."profile" // "DEFAULT"')

  if [[ -n "${SLI_SKIP_OCI_PUSH:-}" ]]; then
    echo "::notice::SLI OCI push skipped (SLI_SKIP_OCI_PUSH set)"
    return 0
  fi

  if [[ -n "$OCI_LOG_ID" && -n "$OCI_CONFIG" && -f "$OCI_CONFIG" ]]; then
    BATCH=$(jq -nc \
      --arg ts "$TIMESTAMP" \
      --argjson entry "$LOG_ENTRY" \
      '[{
        "defaultlogentrytime": $ts,
        "source": "github-actions/sli-tracker",
        "type":   "sli-event",
        "entries": [{ "data": ($entry | tostring), "id": ($ts + "-sli"), "time": $ts }]
      }]')

    local _stf OCI_CLI_AUTH=()
    _stf="$(_oci_config_field "$OCI_CONFIG" "$OCI_PROFILE" security_token_file)"
    _stf="$(sli_expand_oci_config_path "$_stf")"
    if [[ -n "$_stf" ]]; then
      OCI_CLI_AUTH=(--auth security_token)
    fi

    OCI_CONFIG_FILE="$OCI_CONFIG" \
    oci logging-ingestion put-logs \
      "${OCI_CLI_AUTH[@]}" \
      --log-id "$OCI_LOG_ID" \
      --log-entry-batches "$BATCH" \
      --specversion "1.0" \
      --profile "$OCI_PROFILE" \
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
