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
  case "$p" in
    "~")    echo "$HOME" ;;
    "~/"*)  echo "${HOME}${p:1}" ;;
    *)      echo "$p" ;;
  esac
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

# Combine base + flat + failure_reasons into final log entry JSON.
sli_build_log_entry() {
  local base flat fr result
  base="${1:?}"
  flat="${2:?}"
  fr="${3:?}"
  result=$(echo "$base" | jq --argjson ctx "$flat" '. + $ctx' | jq --argjson fr "$fr" '. + {failure_reasons: $fr}')
  sli_unescape_json_fields "$result"
}
