#!/usr/bin/env bash
# SLI event payload builder + optional OCI Logging push.
# Reads GitHub default env (GITHUB_*) plus SLI_* inputs. Always exits 0 (ghost step).

set -euo pipefail

# --- pure helpers (testable) ---

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
      source:               "github-actions/sli-tracker",
      outcome:              $outcome,
      workflow_run_id:      $run_id,
      workflow_run_number:  $run_num,
      workflow_run_attempt: $run_att,
      repository:           $repo,
      repository_id:        $repo_id,
      ref:                  $ref,
      ref_full:             $ref_full,
      sha:                  $sha,
      workflow:             $wf,
      workflow_ref:         $wf_ref,
      job:                  $job_id,
      event_name:           $ev,
      actor:                $actor,
      timestamp:            $ts
    }'
}

# Merge inputs-json + context-json; strip oci from flat merge (oci used only for CLI).
sli_merge_flat_context() {
  local ij ctx
  ij="$(sli_normalize_json_object "${1:-}")"
  ctx="$(sli_normalize_json_object "${2:-}")"
  jq -n --argjson i "$ij" --argjson c "$ctx" '$i * ($c | del(.oci))'
}

# Extract .oci from context for OCI CLI.
sli_extract_oci_json() {
  local ctx
  ctx="$(sli_normalize_json_object "${1:-}")"
  echo "$ctx" | jq -c '.oci // {}'
}

# Paths from workflow outputs are literal strings: ~/.oci/config does not auto-expand (unlike typing in a shell).
# Note: avoid using ~/* as an unquoted case pattern — bash expands it as a filesystem glob before matching,
# so ~/.hidden paths never match. Use "~/"* (quoted ~/) and ${p:1} for safe tilde substitution.
sli_expand_oci_config_path() {
  local p="${1:-}"
  [[ -z "$p" ]] && { echo ""; return; }
  case "$p" in
    "~")    echo "$HOME" ;;
    "~/"*)  echo "${HOME}${p:1}" ;;
    *)      echo "$p" ;;
  esac
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

# SLI_FAILURE_REASON_* from current process environment (jq env object).
sli_failure_reasons_from_env() {
  jq -n 'env | with_entries(select(.key | startswith("SLI_FAILURE_REASON_")))'
}

# Unescape any top-level field whose key ends with "-json" and whose value is a
# JSON-encoded string. GitHub Actions outputs are always strings, so array/object
# inputs arrive double-encoded; this restores them to native JSON values.
# Fields that are already non-string or whose string value is not valid JSON are
# left unchanged.
sli_unescape_json_fields() {
  local payload="${1:?}"
  echo "$payload" | jq -c '
    with_entries(
      if (.key | endswith("-json")) and (.value | type) == "string"
      then .value |= (. as $orig | try fromjson catch $orig)
      else . end
    )'
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

# --- main (CI) ---

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

    OCI_CONFIG_FILE="$OCI_CONFIG" \
    oci logging-ingestion put-logs \
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
