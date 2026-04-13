#!/usr/bin/env bash
# Sprint 27 / SLI-44 — RUP bootstrap placeholder (replace when oci_logging fanout is implemented).
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
for f in \
  "$REPO_ROOT/progress/sprint_27/sprint_27_setup.md" \
  "$REPO_ROOT/progress/sprint_27/sprint_27_design.md" \
  "$REPO_ROOT/progress/sprint_27/sprint_27_implementation.md" \
  "$REPO_ROOT/progress/sprint_27/new_tests.manifest"; do
  [[ -f "$f" ]] || { echo "FAIL: missing $f" >&2; exit 1; }
done
grep -q 'SLI-44' "$REPO_ROOT/BACKLOG.md" || { echo "FAIL: BACKLOG.md must mention SLI-44" >&2; exit 1; }
echo "[PASS] Sprint 27 RUP artifacts present; SLI-44 implementation pending (see progress/sprint_27/)"
