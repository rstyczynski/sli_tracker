# Sprint 13 — Implementation

Sprint: 13 | Mode: YOLO | Backlog: SLI-18

## SLI-18: Controlled success/failure ratio simulator script

Status: implemented

### Summary

Added a standalone simulator script that can generate a controlled failure ratio over time (ramp-up → hold → teardown) using selectable curve shapes. The script supports a dry-run mode for deterministic testing without OCI credentials, and can call the existing `.github/actions/sli-event/emit.sh` for live emission when configured by the operator.

### Code Artifacts

|File|Change|
|---|---|
|`tools/sli_ratio_simulator.sh`|New simulator script with dry-run and curve-based scheduling|
|`tests/unit/test_sli_ratio_simulator.sh`|Unit coverage for curve computation + determinism|
|`tests/integration/test_sli_ratio_simulator.sh`|Dry-run end-to-end trend checks|

### Operator usage (how to run the simulator)

The simulator is `tools/sli_ratio_simulator.sh`.

To see all options:

```bash
tools/sli_ratio_simulator.sh --help
```

#### Dry-run (recommended first)

Dry-run prints one JSON line per tick with the current phase, computed failure probability, RNG draw, and chosen outcome. It does **not** call OCI.

```bash
tools/sli_ratio_simulator.sh \
  --target-failure-rate 0.10 \
  --ramp-seconds 900 \
  --hold-seconds 300 \
  --teardown-seconds 900 \
  --interval-seconds 5 \
  --ramp-curve linear \
  --teardown-curve quadratic \
  --seed 1 \
  --dry-run
```

#### Live emission (calls `sli-event` `emit.sh` each tick)

Set the same environment variables you use for a normal local `emit.sh` run, then run the simulator **without** `--dry-run`.

Minimum recommended env (example):

```bash
export EMIT_BACKEND=curl
export EMIT_TARGET=log,metric
export SLI_OCI_LOG_ID="<log-ocid>"
export SLI_METRIC_COMPARTMENT="<compartment-ocid>"
export SLI_CONTEXT_JSON='{"oci":{"config-file":"~/.oci/config","profile":"SLI_TEST"}}'

tools/sli_ratio_simulator.sh \
  --target-failure-rate 0.10 \
  --ramp-seconds 900 \
  --hold-seconds 300 \
  --teardown-seconds 900 \
  --interval-seconds 5 \
  --ramp-curve exponential \
  --teardown-curve logarithmic \
  --seed 42
```

Notes:

- The simulator sets `SLI_OUTCOME` internally per tick and then invokes `.github/actions/sli-event/emit.sh`.
- Keep `--interval-seconds` reasonably small (e.g. 5–30s) so the curve is observable.

### Bugs

See `progress/sprint_13/sprint_13_bugs.md`.
