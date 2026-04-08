#!/usr/bin/env bash
set -euo pipefail

# Integration gate for scheduled workflow wiring (no live OCI calls).

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
bash "${REPO_ROOT}/tests/unit/test_sli_scheduled_workflows.sh"

echo "[PASS] integration scheduled workflow wiring"

