#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOL="${ROOT}/tools/sli_compute_sli_metrics.js"
FIX="${ROOT}/tests/fixtures/sli_compute_metrics_sample.json"

fail() { echo "[FAIL] $*" >&2; exit 1; }

out="$("$TOOL" \
  --input-file "$FIX" \
  --window-days 7 \
  --namespace sli_tracker \
  --metric-name outcome \
  --dimension repo_repository=example/repo \
  --dimension workflow_job=build \
  --output json)"

sli="$(echo "$out" | jq -r '.sli')"
success="$(echo "$out" | jq -r '.success_count')"
total="$(echo "$out" | jq -r '.total_count')"
wd="$(echo "$out" | jq -r '.window_days')"
d_repo="$(echo "$out" | jq -r '.dimensions.repo_repository')"
d_job="$(echo "$out" | jq -r '.dimensions.workflow_job')"

[[ "$success" == "27" ]] || fail "expected success_count=27, got $success"
[[ "$total" == "30" ]] || fail "expected total_count=30, got $total"
[[ "$wd" == "7" ]] || fail "expected window_days=7, got $wd"
[[ "$d_repo" == "example/repo" ]] || fail "expected dimension repo_repository, got $d_repo"
[[ "$d_job" == "build" ]] || fail "expected dimension workflow_job, got $d_job"

python3 - "$sli" <<'PY'
import sys
v=float(sys.argv[1])
assert abs(v - 0.9) < 1e-12, f"expected sli=0.9, got {v}"
PY

echo "[PASS] unit sli_compute_sli_metrics fixture computation"

