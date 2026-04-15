#!/usr/bin/env bash
# tests/unit/test_json_pipeline_cli.sh
# Unit tests for CLI-to-CLI JSON transform + route pipeline

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TRANSFORM_CLI="${REPO_ROOT}/tools/json_transform_cli.js"
ROUTER_CLI="${REPO_ROOT}/tools/json_router_cli.js"
FX="${REPO_ROOT}/tests/fixtures/pipeline_cli"

PASS=0
FAIL=0

ok()   { echo "[PASS] $1"; PASS=$((PASS+1)); }
fail() { echo "[FAIL] $1"; FAIL=$((FAIL+1)); }

assert_eq() {
    local label="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then ok "$label"; else
        fail "$label"
        echo "       expected: $expected"
        echo "       actual:   $actual"
    fi
}

normalize_json() {
    node -e "process.stdout.write(JSON.stringify(JSON.parse(process.argv[1])))" "$1"
}

assert_json_eq() {
    local label="$1" expected="$2" actual="$3"
    assert_eq "$label" "$(normalize_json "$expected")" "$(normalize_json "$actual")"
}

assert_exit_and_stderr_contains() {
    local label="$1" expected_code="$2" expected_fragment="$3"
    shift 3
    local actual_code=0 stderr_file
    stderr_file=$(mktemp /tmp/sli_pipeline_cli_stderr.XXXXXX)
    "$@" >/dev/null 2>"$stderr_file" || actual_code=$?
    if [[ "$actual_code" -eq "$expected_code" ]] && grep -q "$expected_fragment" "$stderr_file"; then
        ok "$label"
    else
        fail "$label (expected exit $expected_code and stderr containing '$expected_fragment', got exit $actual_code)"
    fi
    rm -f "$stderr_file"
}

tmp_dir=$(mktemp -d /tmp/sli48_pipeline_cli.XXXXXX)
cat > "${tmp_dir}/routing.json" <<EOF
{
  "adapters": {
    "file_system:specific_events": { "directory": "out/specific" },
    "file_system:workflow_status": { "directory": "out/metrics" }
  },
  "routes": [
    {
      "id": "specific_workflow",
      "mode": "exclusive",
      "priority": 200,
      "match": {
        "headers": { "X-GitHub-Event": "workflow_run" },
        "schema": { "path": "schema", "equals": "github.workflow_run" }
      },
      "transform": { "mapping": "${FX}/ut94_transform_then_route_success/mapping_specific.jsonata" },
      "destination": { "type": "file_system", "name": "specific_events" }
    },
    {
      "id": "workflow_metric",
      "mode": "fanout",
      "match": {
        "headers": { "X-GitHub-Event": "workflow_run" }
      },
      "transform": { "mapping": "${FX}/ut94_transform_then_route_success/mapping_metric.jsonata" },
      "destination": { "type": "file_system", "name": "workflow_status" }
    }
  ]
}
EOF

EXPECTED='{"status":"routed","deliveries":[{"route":{"id":"specific_workflow","mode":"exclusive","destination":{"type":"file_system","name":"specific_events"}},"output":{"kind":"specific","repo":"org/app","schema":"github.workflow_run"}},{"route":{"id":"workflow_metric","mode":"fanout","destination":{"type":"file_system","name":"workflow_status"}},"output":{"metric":"workflow_outcome","repo":"org/app","value":1}}]}'

result=$(node "$TRANSFORM_CLI" \
    --mapping "${FX}/ut94_transform_then_route_success/mapping.jsonata" \
    --input "${FX}/ut94_transform_then_route_success/source.json" \
    | node "$ROUTER_CLI" --routing "${tmp_dir}/routing.json")
assert_eq "UT-94 transform CLI output piped to router CLI executes delivery path" "$EXPECTED" "$result"
if [[ -f "${tmp_dir}/out/specific/001_specific_workflow.json" ]]; then
    actual_specific=$(cat "${tmp_dir}/out/specific/001_specific_workflow.json")
    assert_json_eq "UT-94 specific route writes file" '{"kind":"specific","repo":"org/app","schema":"github.workflow_run"}' "$actual_specific"
else
    fail "UT-94 specific route writes file (missing output file)"
fi
if [[ -f "${tmp_dir}/out/metrics/002_workflow_metric.json" ]]; then
    actual_metric=$(cat "${tmp_dir}/out/metrics/002_workflow_metric.json")
    assert_json_eq "UT-94 metric route writes file" '{"metric":"workflow_outcome","repo":"org/app","value":1}' "$actual_metric"
else
    fail "UT-94 metric route writes file (missing output file)"
fi

rm -rf "${tmp_dir}/out"
result=$(cat "${FX}/ut94_transform_then_route_success/source.json" \
    | node "$TRANSFORM_CLI" --mapping "${FX}/ut94_transform_then_route_success/mapping.jsonata" \
    | node "$ROUTER_CLI" --routing "${tmp_dir}/routing.json")
assert_eq "UT-95 stdin transform CLI piped to router CLI executes delivery path" "$EXPECTED" "$result"
if [[ -f "${tmp_dir}/out/specific/001_specific_workflow.json" ]]; then
    actual_specific=$(cat "${tmp_dir}/out/specific/001_specific_workflow.json")
    assert_json_eq "UT-95 specific route writes file" '{"kind":"specific","repo":"org/app","schema":"github.workflow_run"}' "$actual_specific"
else
    fail "UT-95 specific route writes file (missing output file)"
fi
if [[ -f "${tmp_dir}/out/metrics/002_workflow_metric.json" ]]; then
    actual_metric=$(cat "${tmp_dir}/out/metrics/002_workflow_metric.json")
    assert_json_eq "UT-95 metric route writes file" '{"metric":"workflow_outcome","repo":"org/app","value":1}' "$actual_metric"
else
    fail "UT-95 metric route writes file (missing output file)"
fi

STRICT_ERROR=$(tr -d '\n' < "${FX}/ut96_transform_error_stops_pipeline/expected_error.txt")
assert_exit_and_stderr_contains "UT-96 transform CLI failure stops pipeline before router CLI" 1 "$STRICT_ERROR" \
    bash -lc "node '${TRANSFORM_CLI}' --mapping '${FX}/ut96_transform_error_stops_pipeline/mapping.jsonata' --input '${FX}/ut96_transform_error_stops_pipeline/source.json' | node '${ROUTER_CLI}' --routing '${FX}/ut94_transform_then_route_success/routing.json'"

rm -rf "${tmp_dir}"

echo ""
echo "=== json pipeline CLI: $((PASS+FAIL)) tests, $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
