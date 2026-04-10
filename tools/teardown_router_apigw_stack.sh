#!/usr/bin/env bash
# teardown_router_apigw_stack.sh — delete SLI router+APIGW stack (sprint-end / manual cleanup)
#
# Same *role* as tests/cleanup_sli_buckets.sh: sprint-end / manual cleanup only — not after every
# Fn test. While iterating, keep the stack; bump fn/router_passthrough/func.yaml + FN_FORCE_DEPLOY.
# Prefer from repo root: ./tests/cleanup_router_apigw_stack.sh (wraps this script).
#
# Usage (repository root):
#   ./tests/cleanup_router_apigw_stack.sh
#   NAME_PREFIX=sli-router-passthrough-dev ./tools/teardown_router_apigw_stack.sh
#
# Requires: NAME_PREFIX matching the stack; oci_scaffold/state-${NAME_PREFIX}.json must exist.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCAFFOLD="$REPO_ROOT/oci_scaffold"

: "${NAME_PREFIX:?NAME_PREFIX must match the stack you provisioned (e.g. sli-router-passthrough-dev)}"

STATE_JSON="${SCAFFOLD}/state-${NAME_PREFIX}.json"
if [[ ! -f "$STATE_JSON" ]]; then
  echo "ERROR: state file not found: $STATE_JSON" >&2
  exit 1
fi

export NAME_PREFIX
bash "${REPO_ROOT}/tools/teardown_fn_resource_principal_os_policy.sh"
cd "$SCAFFOLD"
export PATH="${SCAFFOLD}/do:${SCAFFOLD}/resource:${PATH}"
NAME_PREFIX="$NAME_PREFIX" bash "${SCAFFOLD}/do/teardown.sh"

echo "  [INFO] Stack $NAME_PREFIX torn down (state archived by do/teardown.sh)."
