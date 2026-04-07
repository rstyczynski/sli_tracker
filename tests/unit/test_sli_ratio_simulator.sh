#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SIM="${ROOT}/tools/sli_ratio_simulator.sh"

fail() { echo "[FAIL] $*" >&2; exit 1; }

out="$("$SIM" \
  --target-failure-rate 0.4 \
  --ramp-seconds 10 \
  --hold-seconds 10 \
  --teardown-seconds 10 \
  --interval-seconds 5 \
  --ramp-curve linear \
  --teardown-curve quadratic \
  --seed 123 \
  --dry-run)"

echo "$out" | jq -e 'type=="string"' >/dev/null 2>&1 && fail "unexpected output type"

# Extract p_failure values by phase.
p_ramp_0="$(echo "$out" | jq -r 'select(.phase=="ramp" and .t==0) | .p_failure')"
p_ramp_5="$(echo "$out" | jq -r 'select(.phase=="ramp" and .t==5) | .p_failure')"
p_hold_10="$(echo "$out" | jq -r 'select(.phase=="hold" and .t==10) | .p_failure')"
p_hold_15="$(echo "$out" | jq -r 'select(.phase=="hold" and .t==15) | .p_failure')"
p_teardown_20="$(echo "$out" | jq -r 'select(.phase=="teardown" and .t==20) | .p_failure')"
p_teardown_25="$(echo "$out" | jq -r 'select(.phase=="teardown" and .t==25) | .p_failure')"

[[ "$p_ramp_0" == "0" || "$p_ramp_0" == "0.0" ]] || fail "ramp t=0 should be 0, got $p_ramp_0"

# ramp linear: target 0.4, t=5 of 10 => 0.2
[[ "$p_ramp_5" == "0.2" ]] || fail "ramp t=5 should be 0.2, got $p_ramp_5"

[[ "$p_hold_10" == "0.4" ]] || fail "hold t=10 should be 0.4, got $p_hold_10"
[[ "$p_hold_15" == "0.4" ]] || fail "hold t=15 should be 0.4, got $p_hold_15"

# teardown quadratic should decrease: t=20 (start of teardown) == target; later should be smaller.
[[ "$p_teardown_20" == "0.4" ]] || fail "teardown start should be 0.4, got $p_teardown_20"

python3 - "$p_teardown_25" <<'PY'
import sys
v=float(sys.argv[1])
assert v < 0.4, f"expected teardown to decrease below 0.4, got {v}"
PY

# Determinism: same seed/config yields identical output.
out2="$("$SIM" \
  --target-failure-rate 0.4 \
  --ramp-seconds 10 \
  --hold-seconds 10 \
  --teardown-seconds 10 \
  --interval-seconds 5 \
  --ramp-curve linear \
  --teardown-curve quadratic \
  --seed 123 \
  --dry-run)"

[[ "$out" == "$out2" ]] || fail "dry-run output is not deterministic for a fixed seed"

echo "[PASS] unit sli_ratio_simulator dry-run curve + determinism"

