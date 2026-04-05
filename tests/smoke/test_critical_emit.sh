#!/usr/bin/env bash
# SM-1: Smoke test — verify emit.sh produces valid JSON from core functions.
# This is the most critical path: if emit.sh can't produce valid JSON,
# no SLI event can be pushed to OCI.
#
# Sprint 7 — Phase 3.1 skeleton. Stubs marked with # TODO: implement.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ACTION_DIR="$REPO_ROOT/.github/actions/sli-event"

# shellcheck source=../../.github/actions/sli-event/emit.sh
source "$ACTION_DIR/emit.sh"

passed=0
failed=0

pass() { ((passed += 1)) || true; }
fail() { echo "FAIL: $*"; ((failed += 1)) || true; }

assert_valid_json() {
    local output="$1" msg="$2"
    if echo "$output" | jq -e . >/dev/null 2>&1; then
        pass
    else
        fail "$msg — output is not valid JSON: $output"
    fi
}

# TODO: implement — fill in test body after Construction implements code
# Test 1: sli_build_base_json produces valid JSON
echo "== SM-1a: sli_build_base_json produces valid JSON =="
_sli_test_vars=(SLI_OUTCOME SLI_TIMESTAMP GITHUB_RUN_ID GITHUB_RUN_NUMBER GITHUB_RUN_ATTEMPT
  GITHUB_REPOSITORY GITHUB_REPOSITORY_ID GITHUB_REF_NAME GITHUB_REF GITHUB_SHA
  GITHUB_WORKFLOW GITHUB_WORKFLOW_REF GITHUB_JOB GITHUB_EVENT_NAME GITHUB_ACTOR)
declare -A _sli_test_saved
for _v in "${_sli_test_vars[@]}"; do _sli_test_saved[$_v]="${!_v:-}"; done
export SLI_OUTCOME="success" SLI_TIMESTAMP="2026-01-01T00:00:00Z"
export GITHUB_RUN_ID="1" GITHUB_RUN_NUMBER="1" GITHUB_RUN_ATTEMPT="1"
export GITHUB_REPOSITORY="test/repo" GITHUB_REPOSITORY_ID="1"
export GITHUB_REF_NAME="main" GITHUB_REF="refs/heads/main" GITHUB_SHA="abc123"
export GITHUB_WORKFLOW="test" GITHUB_WORKFLOW_REF="test/repo/.github/workflows/test.yml@refs/heads/main"
export GITHUB_JOB="test" GITHUB_EVENT_NAME="push" GITHUB_ACTOR="tester"

base_json="$(sli_build_base_json)"
assert_valid_json "$base_json" "sli_build_base_json output"

for _v in "${_sli_test_vars[@]}"; do export "$_v=${_sli_test_saved[$_v]}"; done
unset _sli_test_vars _sli_test_saved _v base_json

# Test 2: sli_unescape_json_fields correctly handles escaped arrays
echo "== SM-1b: sli_unescape_json_fields handles escaped JSON =="
result="$(sli_unescape_json_fields '{"envs":"[\"a\",\"b\"]","plain":"x"}')"
assert_valid_json "$result" "unescape output"
envs_type="$(echo "$result" | jq -r '.envs | type')"
if [[ "$envs_type" == "array" ]]; then
    pass
else
    fail "unescape: envs should be array, got $envs_type"
fi

# Test 3: sli_normalize_json_object edge cases
echo "== SM-1c: sli_normalize_json_object edge cases =="
assert_valid_json "$(sli_normalize_json_object '')" "empty string"
assert_valid_json "$(sli_normalize_json_object 'null')" "literal null"
assert_valid_json "$(sli_normalize_json_object 'not json')" "invalid JSON"
assert_valid_json "$(sli_normalize_json_object '{"a":1}')" "valid object"

echo "== summary =="
echo "passed: $passed  failed: $failed"
[[ "$failed" -gt 0 ]] && exit 1
exit 0
