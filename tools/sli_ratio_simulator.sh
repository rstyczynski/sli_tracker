#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: tools/sli_ratio_simulator.sh [OPTIONS]

Emit (or dry-run) SLI events with a controlled failure ratio over time:
  ramp_up (0 -> target) -> hold (target) -> teardown (target -> 0)

Options:
  --target-failure-rate P     Target failure rate in [0,1] (required)
  --ramp-seconds N            Ramp-up duration seconds (default: 0)
  --hold-seconds N            Hold duration seconds (default: 0)
  --teardown-seconds N        Teardown duration seconds (default: 0)
  --interval-seconds N        Tick interval seconds (default: 5)

  --ramp-curve TYPE           linear|exponential|logarithmic|quadratic (default: linear)
  --teardown-curve TYPE       linear|exponential|logarithmic|quadratic (default: linear)

  --seed N                    RNG seed (default: 1)
  --dry-run                   Do not call emit.sh; print schedule/outcomes

Environment for live emission (when not --dry-run):
  - Set EMIT_BACKEND / EMIT_TARGET / SLI_CONTEXT_JSON / SLI_OCI_LOG_ID etc as usual for .github/actions/sli-event/emit.sh

EOF
}

TARGET=""
RAMP_S=0
HOLD_S=0
TEARDOWN_S=0
INTERVAL_S=5
RAMP_CURVE="linear"
TEARDOWN_CURVE="linear"
SEED=1
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target-failure-rate) shift; TARGET="${1:-}";;
    --ramp-seconds)        shift; RAMP_S="${1:-0}";;
    --hold-seconds)        shift; HOLD_S="${1:-0}";;
    --teardown-seconds)    shift; TEARDOWN_S="${1:-0}";;
    --interval-seconds)    shift; INTERVAL_S="${1:-5}";;
    --ramp-curve)          shift; RAMP_CURVE="${1:-linear}";;
    --teardown-curve)      shift; TEARDOWN_CURVE="${1:-linear}";;
    --seed)                shift; SEED="${1:-1}";;
    --dry-run)             DRY_RUN=1;;
    --help|-h)             usage; exit 0;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2;;
  esac
  shift
done

[[ -z "$TARGET" ]] && { echo "Missing --target-failure-rate" >&2; usage; exit 2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EMIT_SH="${SCRIPT_DIR}/.github/actions/sli-event/emit.sh"

python3 - "$TARGET" "$RAMP_S" "$HOLD_S" "$TEARDOWN_S" "$INTERVAL_S" "$RAMP_CURVE" "$TEARDOWN_CURVE" "$SEED" "$DRY_RUN" "$EMIT_SH" <<'PY'
import json, math, os, random, subprocess, sys, time

target = float(sys.argv[1])
ramp_s = int(sys.argv[2])
hold_s = int(sys.argv[3])
tdown_s = int(sys.argv[4])
interval_s = int(sys.argv[5])
ramp_curve = sys.argv[6]
tdown_curve = sys.argv[7]
seed = int(sys.argv[8])
dry_run = int(sys.argv[9]) == 1
emit_sh = sys.argv[10]

def clamp01(x: float) -> float:
  return 0.0 if x < 0.0 else (1.0 if x > 1.0 else x)

def curve_value(curve: str, x: float, k: float = 5.0, a: float = 9.0) -> float:
  x = clamp01(x)
  if curve == "linear":
    return x
  if curve == "quadratic":
    return x * x
  if curve == "logarithmic":
    # normalized log(1+a*x)/log(1+a)
    return math.log(1.0 + a * x) / math.log(1.0 + a)
  if curve == "exponential":
    # normalized (e^{k x}-1)/(e^{k}-1)
    return (math.exp(k * x) - 1.0) / (math.exp(k) - 1.0)
  raise ValueError(f"unknown curve: {curve}")

def pf_at(t: int) -> tuple[str, float]:
  # returns (phase, p_failure)
  if ramp_s > 0 and t < ramp_s:
    x = t / ramp_s
    return ("ramp", target * curve_value(ramp_curve, x))
  t2 = t - ramp_s
  if hold_s > 0 and t2 < hold_s:
    return ("hold", target)
  t3 = t2 - hold_s
  if tdown_s > 0 and t3 < tdown_s:
    x = t3 / tdown_s
    # teardown: target -> 0
    return ("teardown", target * curve_value(tdown_curve, 1.0 - x))
  return ("done", 0.0)

if interval_s <= 0:
  raise SystemExit("interval-seconds must be > 0")
if not (0.0 <= target <= 1.0):
  raise SystemExit("target-failure-rate must be in [0,1]")

random.seed(seed)

total_duration = ramp_s + hold_s + tdown_s
t = 0
emitted = 0
failures = 0

print(json.dumps({
  "target_failure_rate": target,
  "ramp_seconds": ramp_s,
  "hold_seconds": hold_s,
  "teardown_seconds": tdown_s,
  "interval_seconds": interval_s,
  "ramp_curve": ramp_curve,
  "teardown_curve": tdown_curve,
  "seed": seed,
  "dry_run": dry_run,
}, sort_keys=True))

while t <= total_duration:
  phase, pf = pf_at(t)
  if phase == "done":
    break
  r = random.random()
  outcome = "failure" if r < pf else "success"
  emitted += 1
  failures += (1 if outcome == "failure" else 0)

  rec = {"t": t, "phase": phase, "p_failure": round(pf, 6), "rand": round(r, 6), "outcome": outcome}
  print(json.dumps(rec))

  if not dry_run:
    tick_start = time.monotonic()
    env = os.environ.copy()
    env["SLI_OUTCOME"] = outcome
    # Let caller select backend/targets; default behavior is controlled externally.
    subprocess.run(["bash", emit_sh], env=env, check=False)
    elapsed = time.monotonic() - tick_start
    sleep_s = interval_s - elapsed
    if sleep_s > 0:
      print(f"[info] sleep {sleep_s:.3f}s (interval={interval_s}s, emit_elapsed={elapsed:.3f}s)", file=sys.stderr)
      time.sleep(sleep_s)
  t += interval_s

summary = {
  "emitted": emitted,
  "failures": failures,
  "observed_failure_rate": (failures / emitted) if emitted else 0.0,
}
print(json.dumps({"summary": summary}))
PY

