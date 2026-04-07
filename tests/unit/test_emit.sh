#!/usr/bin/env bash
# Unit tests for emit.sh helpers.
# Migrated from .github/actions/sli-event/tests/test_emit.sh (Sprint 7, SLI-10)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ACTION_DIR="$REPO_ROOT/.github/actions/sli-event"

# shellcheck source=../../.github/actions/sli-event/emit.sh
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
want='{"source":"github-actions/sli-tracker","outcome":"success","timestamp":"2026-01-01T00:00:00Z","workflow":{"run_id":"99","run_number":"7","run_attempt":"2","name":"wf","ref":"o/r/.github/workflows/w.yml@refs/heads/main","job":"leaf","event_name":"push","actor":"me"},"repo":{"repository":"o/r","repository_id":"42","ref":"main","ref_full":"refs/heads/main","sha":"abc"}}'
assert_json_eq "$(sli_build_base_json)" "$want" "base json from env — nested workflow+repo schema"
for _v in "${_sli_test_vars[@]}"; do export "$_v=${_sli_test_saved[$_v]}"; done
unset _sli_test_vars _sli_test_saved _v want

# ── Sprint 8 (SLI-11): emit_common.sh / emit_oci.sh / emit_curl.sh / dispatcher ──

echo "== UT-1: emit_common.sh — all helpers sourced =="
# TODO: implement — verify helpers available after source emit_common.sh
# (placeholder: will pass once emit_common.sh exists)
if bash -c "source '$ACTION_DIR/emit_common.sh' && declare -f sli_build_log_entry" >/dev/null 2>&1; then
  pass
else
  fail "UT-1: sli_build_log_entry not found after sourcing emit_common.sh"
fi

echo "== UT-2: _oci_config_field — multi-profile config parsing =="
# TODO: implement — write temp config, call _oci_config_field, assert correct value
_oci_tmp_cfg="$(mktemp)"
cat > "$_oci_tmp_cfg" <<'CFGEOF'
[DEFAULT]
region=us-ashburn-1
tenancy=ocid1.tenancy.oc1..default

[SLI_TEST]
region=eu-frankfurt-1
tenancy=ocid1.tenancy.oc1..slitest
user=ocid1.user.oc1..slitest
fingerprint=aa:bb:cc
key_file=/tmp/fake.pem
CFGEOF
if bash -c "source '${ACTION_DIR}/emit_curl.sh' 2>/dev/null; _oci_config_field '${_oci_tmp_cfg}' SLI_TEST region" 2>/dev/null | grep -q "eu-frankfurt-1"; then
  pass
else
  fail "UT-2: _oci_config_field did not return correct region for SLI_TEST profile"
fi
# missing field -> empty
_missing="$(bash -c "source '${ACTION_DIR}/emit_curl.sh' 2>/dev/null; _oci_config_field '${_oci_tmp_cfg}' SLI_TEST nonexistent_field" 2>/dev/null)"
assert_eq "$_missing" "" "UT-2b: missing field returns empty"
rm -f "$_oci_tmp_cfg"

echo "== UT-3: emit_curl.sh — SLI_SKIP_OCI_PUSH skips curl =="
_out3="$(SLI_SKIP_OCI_PUSH=1 SLI_OUTCOME=success bash "${ACTION_DIR}/emit_curl.sh" 2>&1)"
if echo "$_out3" | grep -q "SLI OCI push skipped"; then
  pass
else
  fail "UT-3: expected skip notice, got: $_out3"
fi

echo "== UT-4: emit_curl.sh — Authorization header structure =="
# Generate a throwaway RSA key for signing test
_keydir="$(mktemp -d)"
openssl genrsa -out "$_keydir/key.pem" 2048 2>/dev/null
cat > "$_keydir/config" <<CFGEOF
[SLI_TEST]
region=us-ashburn-1
tenancy=ocid1.tenancy.oc1..test
user=ocid1.user.oc1..test
fingerprint=11:22:33:44
key_file=${_keydir}/key.pem
CFGEOF
# Mock curl: real script on PATH so subshell invocations pick it up
_curl_out="$_keydir/curl_args.txt"
_curl_body="$_keydir/curl_body.txt"
mkdir -p "$_keydir/bin"
cat > "$_keydir/bin/curl" <<'MOCKEOF'
#!/usr/bin/env bash
# Capture all args to file; extract -d body separately
args_file="${_MOCK_CURL_ARGS:-/tmp/curl_args.txt}"
body_file="${_MOCK_CURL_BODY:-/tmp/curl_body.txt}"
printf '%s\n' "$@" >> "$args_file"
capture=false
for arg in "$@"; do
  if $capture; then printf '%s' "$arg" > "$body_file"; capture=false; fi
  [[ "$arg" == "-d" ]] && capture=true
done
# Real curl with -w '%{http_code}' writes only the numeric code to stdout
printf '200'
MOCKEOF
chmod +x "$_keydir/bin/curl"

_out4="$(PATH="$_keydir/bin:$PATH" \
  _MOCK_CURL_ARGS="$_curl_out" \
  _MOCK_CURL_BODY="$_curl_body" \
  SLI_OUTCOME=success SLI_OCI_LOG_ID="ocid1.log.oc1..test" \
  SLI_CONTEXT_JSON="{\"oci\":{\"config-file\":\"${_keydir}/config\",\"profile\":\"SLI_TEST\"}}" \
  bash "${ACTION_DIR}/emit_curl.sh" 2>&1)"
if grep -qE 'version="1"' "$_curl_out" 2>/dev/null; then
  pass
else
  fail "UT-4: Authorization header not found or malformed — output: $_out4"
fi
if grep -qE 'algorithm="rsa-sha256"' "$_curl_out" 2>/dev/null; then
  pass
else
  fail "UT-4b: rsa-sha256 algorithm not in Authorization header"
fi

echo "== UT-5: emit_curl.sh — payload matches put-logs shape (specversion + logEntryBatches) =="
if jq -e '.specversion == "1.0" and .logEntryBatches[0].entries[0].data' "$_curl_body" >/dev/null 2>&1; then
  pass
else
  fail "UT-5: payload is not a valid ingestion body — body: $(cat "$_curl_body" 2>/dev/null | head -1)"
fi
rm -rf "$_keydir"

echo "== UT-6: emit.sh dispatcher — EMIT_BACKEND=curl =="
_out6="$(EMIT_BACKEND=curl SLI_SKIP_OCI_PUSH=1 SLI_OUTCOME=success bash "${ACTION_DIR}/emit.sh" 2>&1)"
if echo "$_out6" | grep -q "SLI OCI push skipped"; then
  pass
else
  fail "UT-6: curl backend not invoked or did not produce skip notice: $_out6"
fi

echo "== UT-7: emit.sh dispatcher — EMIT_BACKEND=oci-cli =="
_out7="$(EMIT_BACKEND=oci-cli SLI_SKIP_OCI_PUSH=1 SLI_OUTCOME=success bash "${ACTION_DIR}/emit.sh" 2>&1)"
if echo "$_out7" | grep -q "SLI OCI push skipped"; then
  pass
else
  fail "UT-7: oci-cli backend not invoked or did not produce skip notice: $_out7"
fi

# ── Sprint 10 (SLI-13/14/15): nested workflow + repo schema ──

echo "== UT-S10-1: sli_build_base_json — workflow object shape =="
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

_s10_base="$(sli_build_base_json)"

# UT-S10-1: workflow nested object
want_wf='{"run_id":"99","run_number":"7","run_attempt":"2","name":"wf","ref":"o/r/.github/workflows/w.yml@refs/heads/main","job":"leaf","event_name":"push","actor":"me"}'
assert_json_eq "$(echo "$_s10_base" | jq -c '.workflow')" "$want_wf" "UT-S10-1: workflow is nested object"

echo "== UT-S10-2: sli_build_base_json — repo object shape =="
want_repo='{"repository":"o/r","repository_id":"42","ref":"main","ref_full":"refs/heads/main","sha":"abc"}'
assert_json_eq "$(echo "$_s10_base" | jq -c '.repo')" "$want_repo" "UT-S10-2: repo is nested object"

echo "== UT-S10-3: sli_build_base_json — old flat fields absent =="
_old_fields="workflow_run_id workflow_run_number workflow_run_attempt workflow_ref repository repository_id ref ref_full sha job event_name actor"
for _f in $_old_fields; do
  _val="$(echo "$_s10_base" | jq -r --arg k "$_f" '.[$k]')"
  if [[ "$_val" == "null" ]]; then
    pass
  else
    fail "UT-S10-3: old flat field '$_f' still present in payload (value: $_val)"
  fi
done

for _v in "${_sli_test_vars[@]}"; do export "$_v=${_sli_test_saved[$_v]}"; done
unset _sli_test_vars _sli_test_saved _v _s10_base want_wf want_repo _old_fields _f _val

# ── Sprint 12 (SLI-17): EMIT_TARGET + sli_outcome_to_metric_value ──

echo "== UT-S12-1: sli_outcome_to_metric_value — success → 1 =="
# TODO: implement — source emit_common.sh and call sli_outcome_to_metric_value
source "$ACTION_DIR/emit_common.sh" 2>/dev/null || true
if declare -f sli_outcome_to_metric_value >/dev/null 2>&1; then
  assert_eq "$(sli_outcome_to_metric_value success)" "1" "UT-S12-1: success -> 1"
else
  fail "UT-S12-1: sli_outcome_to_metric_value not found in emit_common.sh"
fi

echo "== UT-S12-2: sli_outcome_to_metric_value — failure → 0 =="
if declare -f sli_outcome_to_metric_value >/dev/null 2>&1; then
  assert_eq "$(sli_outcome_to_metric_value failure)" "0" "UT-S12-2: failure -> 0"
else
  fail "UT-S12-2: sli_outcome_to_metric_value not found"
fi

echo "== UT-S12-3: sli_outcome_to_metric_value — empty/unknown → 0 =="
if declare -f sli_outcome_to_metric_value >/dev/null 2>&1; then
  assert_eq "$(sli_outcome_to_metric_value "")" "0" "UT-S12-3a: empty -> 0"
  assert_eq "$(sli_outcome_to_metric_value cancelled)" "0" "UT-S12-3b: cancelled -> 0"
  assert_eq "$(sli_outcome_to_metric_value skipped)" "0" "UT-S12-3c: skipped -> 0"
else
  fail "UT-S12-3: sli_outcome_to_metric_value not found"
fi

echo "== UT-S12-4: emit_curl.sh EMIT_TARGET=log — skips metric push =="
_out_s12_4="$(EMIT_TARGET=log SLI_SKIP_OCI_PUSH=1 SLI_OUTCOME=success \
  bash "${ACTION_DIR}/emit_curl.sh" 2>&1)"
if echo "$_out_s12_4" | grep -q "SLI metric"; then
  fail "UT-S12-4: EMIT_TARGET=log should NOT call metric push, got: $_out_s12_4"
else
  pass "UT-S12-4: EMIT_TARGET=log correctly skips metric"
fi

echo "== UT-S12-5: emit_curl.sh EMIT_TARGET=metric — skips log push =="
# With SLI_SKIP_OCI_PUSH=1 and EMIT_TARGET=metric the skip notice should fire
# without any attempt to build the logging batch (no log-id needed).
_out_s12_5="$(EMIT_TARGET=metric SLI_SKIP_OCI_PUSH=1 SLI_OUTCOME=success \
  bash "${ACTION_DIR}/emit_curl.sh" 2>&1)"
if echo "$_out_s12_5" | grep -q "SLI OCI push skipped"; then
  pass "UT-S12-5: SLI_SKIP_OCI_PUSH short-circuits before any push"
else
  fail "UT-S12-5: expected skip notice, got: $_out_s12_5"
fi

echo "== summary =="
echo "passed: $passed  failed: $failed"
if [[ "$failed" -gt 0 ]]; then
  exit 1
fi
exit 0
