# Sprint 13 — Bugs

Sprint: 13 | Mode: YOLO | Backlog: SLI-18

## SLI-18: Controlled success/failure ratio simulator script

### Bug: `--interval-seconds` did not account for API call duration

**Symptom:** With live emission, the effective tick period was longer than `--interval-seconds` because the simulator slept for the full interval *after* spending time on the emit API call.

**Root cause:** The simulator treated `--interval-seconds` as “sleep this long after emitting” instead of a fixed tick period.

**Fix:** Measure per-tick elapsed time and sleep only the remaining time (\(max(0, interval - elapsed)\)) so ticks are aligned to a fixed cadence.

**Verification:** Re-ran Sprint 13 unit + integration tests; both passed. Live runs now keep a consistent tick cadence under steady emit latency.
