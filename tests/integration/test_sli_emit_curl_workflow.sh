#!/usr/bin/env bash
# Integration test — emit_curl workflow (Sprint 9, SLI-12)
# Dispatches model-emit-curl.yml and verifies OCI Logging receives events.
#
# Prerequisites: same as test_sli_integration.sh (gh, oci, jq, OCI profile)
# Usage: bash tests/integration/test_sli_emit_curl_workflow.sh

set -euo pipefail

REPO="rstyczynski/sli_tracker"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OCI_INT_PROFILE="${SLI_INTEGRATION_OCI_PROFILE:-SLI_TEST}"
export OCI_INT_PROFILE
export OCI_CLI_PROFILE="$OCI_INT_PROFILE"

TS="$(date -u '+%Y%m%d_%H%M%S')"
LOG_FILE="${SCRIPT_DIR}/test_run_curl_${TS}.log"
OCI_LOG_FILE="${SCRIPT_DIR}/oci_logs_curl_${TS}.json"

exec > >(tee -a "$LOG_FILE") 2>&1

echo "# emit_curl workflow integration test — $(date -u)"
echo "# Log: $LOG_FILE"

# TODO: implement — auth gate (same pattern as test_sli_integration.sh)
echo "FAIL: skeleton test — not yet implemented"
exit 1
