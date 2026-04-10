#!/usr/bin/env bash
# Deletes the SLI router + API Gateway + Fn stack provisioned by tools/cycle_apigw_router_passthrough.sh.
#
# Same *role* as cleanup_sli_buckets.sh: run manually when you want to reclaim OCI resources
# (e.g. end of sprint), not after every Fn code test. While iterating on Node handler code, keep
# the stack up and redeploy with fn/router_passthrough/func.yaml version bump + FN_FORCE_DEPLOY=true.
#
# Requires: state file oci_scaffold/state-${NAME_PREFIX}.json from a prior cycle run.
#
# Usage (repository root):
#   ./tests/cleanup_router_apigw_stack.sh
#   NAME_PREFIX=my-prefix ./tests/cleanup_router_apigw_stack.sh
#
# Related:
#   tests/cleanup_sli_buckets.sh — sli-* buckets in /SLI_tracker (optional companion cleanup)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Match default stable prefix from tests/integration/test_fn_apigw_object_storage_passthrough.sh
NAME_PREFIX="${NAME_PREFIX:-${SLI_FN_APIGW_ROUTER_PREFIX:-sli-router-passthrough-dev}}"
export NAME_PREFIX

echo "=== cleanup_router_apigw_stack.sh ==="
echo "NAME_PREFIX : $NAME_PREFIX"
echo "State file  : ${REPO_ROOT}/oci_scaffold/state-${NAME_PREFIX}.json"
echo ""

exec bash "${REPO_ROOT}/tools/teardown_router_apigw_stack.sh"
