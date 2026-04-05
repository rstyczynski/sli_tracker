#!/usr/bin/env bash
# Unit tests for emit.sh helpers. Run: bash tests/test_emit.sh (from repo root: bash .github/actions/sli-event/tests/test_emit.sh)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACTION_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../emit.sh
source "$ACTION_DIR/emit.sh"

passed=0
failed=0

fail() {
  echo "FAIL: $*"
  ((failed += 1)) || true
}

pass() {
  ((passed += 1)) || true
}

assert_eq() {
  local got="$1" want="$2" msg="$3"
  if [[ "$got" == "$want" ]]; then
    pass
  else
    fail "$msg — want '$want', got '$got'"
  fi
}

# jq canonical compare for JSON strings
assert_json_eq() {
  local got="$1" want="$2" msg="$3"
  local g w
  g="$(echo "$got" | jq -c -S . 2>/dev/null)" || { fail "$msg — got is not JSON: $got"; return; }
  w="$(echo "$want" | jq -c -S . 2>/dev/null)" || { fail "$msg — want is not JSON: $want"; return; }
  if [[ "$g" == "$w" ]]; then
    pass
  else
    fail "$msg"
    echo "  got:  $g"
    echo "  want: $w"
  fi
}

echo "== sli_normalize_json_object =="
assert_json_eq "$(sli_normalize_json_object "")" "{}" "empty string -> {}"
assert_json_eq "$(sli_normalize_json_object "null")" "{}" "literal null -> {}"
assert_json_eq "$(sli_normalize_json_object '{"a":1}')" '{"a":1}' "valid object preserved"
assert_json_eq "$(sli_normalize_json_object 'not json')" "{}" "invalid JSON -> {}"

echo "== sli_expand_oci_config_path =="
assert_eq "$(sli_expand_oci_config_path "")" "" "empty path"
assert_eq "$(sli_expand_oci_config_path "/abs/file")" "/abs/file" "absolute unchanged"
# Override HOME in a subshell to test ~ expansion; capture results back to parent shell so
# pass/fail counters are correctly incremented (subshell variables do not propagate).
_orig_home="$HOME"; HOME="/tmp/sli_test_home"
assert_eq "$(sli_expand_oci_config_path "~/.oci/config")" "/tmp/sli_test_home/.oci/config" "~/.oci/config -> \$HOME/.oci/config"
assert_eq "$(sli_expand_oci_config_path "~")" "/tmp/sli_test_home" "bare ~"
HOME="$_orig_home"

echo "== sli_merge_flat_context =="
assert_json_eq \
  "$(sli_merge_flat_context '{"environment":"e1"}' '{"run-type":"apply","oci":{"config-file":"/x","profile":"p"}}')" \
  '{"environment":"e1","run-type":"apply"}' \
  "merge strips oci; context overlays inputs"
assert_json_eq \
  "$(sli_merge_flat_context '{}' '{}')" \
  "{}" "two empties"

echo "== sli_extract_oci_json =="
assert_json_eq \
  "$(sli_extract_oci_json '{"oci":{"config-file":"/c","profile":"P"}}')" \
  '{"config-file":"/c","profile":"P"}' \
  "extract oci"
assert_json_eq "$(sli_extract_oci_json '{}')" "{}" "missing oci -> {}"

echo "== sli_failure_reasons_from_steps_json =="
assert_json_eq \
  "$(sli_failure_reasons_from_steps_json '{"step-main":{"outcome":"failure","outputs":{"x":"y"}}}')" \
  '{"SLI_FAILURE_REASON_STEP_MAIN":"step_id=step-main; outputs={\"x\":\"y\"}"}' \
  "one failed step"
assert_json_eq \
  "$(sli_failure_reasons_from_steps_json '{"a":{"outcome":"success","outputs":{}},"b":{"outcome":"failure","outputs":{}}}')" \
  '{"SLI_FAILURE_REASON_B":"step_id=b; outputs={}"}' \
  "only failure outcome"
assert_json_eq \
  "$(sli_failure_reasons_from_steps_json '{}')" \
  "{}" "empty steps"
assert_json_eq \
  "$(sli_failure_reasons_from_steps_json 'broken')" \
  "{}" "invalid steps json -> normalize to {} then empty reasons"

echo "== sli_merge_failure_reasons =="
assert_json_eq \
  "$(sli_merge_failure_reasons '{"SLI_FAILURE_REASON_A":"a"}' '{"SLI_FAILURE_REASON_A":"override"}')" \
  '{"SLI_FAILURE_REASON_A":"override"}' \
  "env side overrides steps side (second arg wins in jq .[0]*.[1])"

echo "== sli_unescape_json_fields =="
assert_json_eq \
  "$(sli_unescape_json_fields '{"environments":"[\"a\",\"b\"]","other":"x"}')" \
  '{"environments":["a","b"],"other":"x"}' \
  "array string unescaped to native array"
assert_json_eq \
  "$(sli_unescape_json_fields '{"config":"{\"k\":\"v\"}","other":"x"}')" \
  '{"config":{"k":"v"},"other":"x"}' \
  "object string unescaped to native object"
assert_json_eq \
  "$(sli_unescape_json_fields '{"note":"plain string","other":"x"}')" \
  '{"note":"plain string","other":"x"}' \
  "plain string not starting with [ or { left as-is"
assert_json_eq \
  "$(sli_unescape_json_fields '{"environment":"prod"}')" \
  '{"environment":"prod"}' \
  "plain value not touched"
assert_json_eq \
  "$(sli_unescape_json_fields '{"environments":["a","b"]}')" \
  '{"environments":["a","b"]}' \
  "already-native array left unchanged"

echo "== sli_build_log_entry =="
assert_json_eq \
  "$(sli_build_log_entry '{"outcome":"failure"}' '{"environment":"e"}' '{"SLI_FAILURE_REASON_X":"y"}')" \
  '{"outcome":"failure","environment":"e","failure_reasons":{"SLI_FAILURE_REASON_X":"y"}}' \
  "full merge"

echo "== sli_build_base_json (fake GITHUB_*) =="
# Save current env, inject fake values, restore after — avoids subshell so pass/fail counters propagate.
_sli_test_vars=(SLI_OUTCOME SLI_TIMESTAMP GITHUB_RUN_ID GITHUB_RUN_NUMBER GITHUB_RUN_ATTEMPT
  GITHUB_REPOSITORY GITHUB_REPOSITORY_ID GITHUB_REF_NAME GITHUB_REF GITHUB_SHA
  GITHUB_WORKFLOW GITHUB_WORKFLOW_REF GITHUB_JOB GITHUB_EVENT_NAME GITHUB_ACTOR)
declare -A _sli_test_saved
for _v in "${_sli_test_vars[@]}"; do _sli_test_saved[$_v]="${!_v:-}"; done
export SLI_OUTCOME="success" SLI_TIMESTAMP="2026-01-01T00:00:00Z"
export GITHUB_RUN_ID="99" GITHUB_RUN_NUMBER="7" GITHUB_RUN_ATTEMPT="2"
export GITHUB_REPOSITORY="o/r" GITHUB_REPOSITORY_ID="42"
export GITHUB_REF_NAME="main" GITHUB_REF="refs/heads/main" GITHUB_SHA="abc"
export GITHUB_WORKFLOW="wf" GITHUB_WORKFLOW_REF="o/r/.github/workflows/w.yml@refs/heads/main"
export GITHUB_JOB="leaf" GITHUB_EVENT_NAME="push" GITHUB_ACTOR="me"
want='{"source":"github-actions/sli-tracker","outcome":"success","workflow_run_id":"99","workflow_run_number":"7","workflow_run_attempt":"2","repository":"o/r","repository_id":"42","ref":"main","ref_full":"refs/heads/main","sha":"abc","workflow":"wf","workflow_ref":"o/r/.github/workflows/w.yml@refs/heads/main","job":"leaf","event_name":"push","actor":"me","timestamp":"2026-01-01T00:00:00Z"}'
assert_json_eq "$(sli_build_base_json)" "$want" "base json from env"
for _v in "${_sli_test_vars[@]}"; do export "$_v=${_sli_test_saved[$_v]}"; done
unset _sli_test_vars _sli_test_saved _v want

echo "== summary =="
echo "passed: $passed  failed: $failed"
if [[ "$failed" -gt 0 ]]; then
  exit 1
fi
exit 0
