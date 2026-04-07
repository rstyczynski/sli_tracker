#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOL="${ROOT}/tools/sli_compute_sli_metrics.js"
FIX="${ROOT}/tests/fixtures/sli_compute_metrics_sample.json"

fail() { echo "[FAIL] $*" >&2; exit 1; }

out="$("$TOOL" --input-file "$FIX" --window-days 30 --output text)"

printf '%s\n' "$out" | python3 -c '
import sys
text = sys.stdin.read()
lines = [l.strip().rstrip("\r") for l in text.splitlines() if l.strip()]
need = {"sli=0.900000","success_count=27","total_count=30","window_days=30"}
missing = [x for x in sorted(need) if x not in lines]
if missing:
    raise SystemExit("missing lines: " + ", ".join(missing))
'

echo "[PASS] integration sli_compute_sli_metrics text output"

