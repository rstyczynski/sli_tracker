#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SIM="${ROOT}/tools/sli_ratio_simulator.sh"

fail() { echo "[FAIL] $*" >&2; exit 1; }

# End-to-end dry-run: ensure ramp increases and teardown decreases (trend checks),
# and hold stays at target probability.
out="$("$SIM" \
  --target-failure-rate 0.3 \
  --ramp-seconds 20 \
  --hold-seconds 10 \
  --teardown-seconds 20 \
  --interval-seconds 5 \
  --ramp-curve exponential \
  --teardown-curve logarithmic \
  --seed 7 \
  --dry-run)"

p_ramp_0="$(echo "$out" | jq -r 'select(.phase=="ramp" and .t==0) | .p_failure')"
p_ramp_15="$(echo "$out" | jq -r 'select(.phase=="ramp" and .t==15) | .p_failure')"
p_hold_20="$(echo "$out" | jq -r 'select(.phase=="hold" and .t==20) | .p_failure')"
p_hold_25="$(echo "$out" | jq -r 'select(.phase=="hold" and .t==25) | .p_failure')"
p_teardown_30="$(echo "$out" | jq -r 'select(.phase=="teardown" and .t==30) | .p_failure')"
p_teardown_45="$(echo "$out" | jq -r 'select(.phase=="teardown" and .t==45) | .p_failure')"

python3 - "$p_ramp_0" "$p_ramp_15" "$p_hold_20" "$p_hold_25" "$p_teardown_30" "$p_teardown_45" <<'PY'
import sys
p_r0=float(sys.argv[1]); p_r15=float(sys.argv[2]); p_h20=float(sys.argv[3]); p_h25=float(sys.argv[4]); p_t30=float(sys.argv[5]); p_t45=float(sys.argv[6])
assert abs(p_r0 - 0.0) < 1e-9, f"ramp t=0 should be 0, got {p_r0}"
assert p_r15 > p_r0, f"ramp should increase (t=15), got {p_r15}"
assert abs(p_h20 - 0.3) < 1e-9, f"hold should equal target (t=20), got {p_h20}"
assert abs(p_h25 - 0.3) < 1e-9, f"hold should equal target (t=25), got {p_h25}"
assert p_t45 < p_t30, f"teardown should decrease (t=45 < t=30), got {p_t30} -> {p_t45}"
PY

summary_rate="$(echo "$out" | jq -r 'select(.summary) | .summary.observed_failure_rate')"
python3 - "$summary_rate" <<'PY'
import sys
r=float(sys.argv[1])
assert 0.0 <= r <= 1.0, f"observed_failure_rate out of range: {r}"
PY

echo "[PASS] integration sli_ratio_simulator dry-run end-to-end trend checks"

