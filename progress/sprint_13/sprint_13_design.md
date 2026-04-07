# Sprint 13 — Design

## SLI-18: Controlled success/failure ratio simulator script

Status: Accepted (YOLO — self-approved)

### Requirement Summary

Add a script that can emit SLI events with a configurable success/failure ratio that changes over time in a controlled way. It must support ramping from baseline to a target failure rate over a configured duration using a selectable curve (linear, exponential, logarithmic, quadratic), holding the achieved level for a configured duration, then tearing down back to baseline using a selectable curve over a configured duration.

### Design Overview

**Operator-facing behavior:**

- Script runs in a timed loop with a configurable tick interval.
- At each tick it computes the current target failure probability \(p_f\) from the configured phase/curve and decides whether this tick emits `SLI_OUTCOME=failure` or `SLI_OUTCOME=success`.
- It invokes `.github/actions/sli-event/emit.sh` (backend selected by existing `EMIT_BACKEND` + context variables supplied by the operator).
- Provide a **dry-run** mode that prints the computed \(p_f\) and chosen outcome but does not call OCI emit, enabling deterministic tests without OCI credentials.

**Curves:**

Let \(x = t / T\) clamped to \([0,1]\). For ramp-up to target \(P\):

- linear: \(P \cdot x\)
- quadratic: \(P \cdot x^2\)
- logarithmic: \(P \cdot \\frac{\\log(1 + a x)}{\\log(1+a)}\)
- exponential: \(P \cdot \\frac{e^{k x} - 1}{e^{k} - 1}\)

For teardown from target \(P\) to 0, use the same curve shapes applied to \(1-x\).

### Technical Constraints

- Script must be usable locally (outside GitHub Actions) and inside CI.
- Tests must not require OCI credentials; they should validate deterministic computation and observable ratios in dry-run mode.

### Testing Strategy

Test: **unit, integration**. Regression: **unit**.

- **Unit**: verify curve computation and phase transitions (ramp/hold/teardown) and that dry-run is deterministic with a fixed seed.
- **Integration**: run the script end-to-end in dry-run mode with short durations and a fixed seed; assert the observed failure ratio over windows tracks the intended curve within tolerance.

## Test Specification

### Unit tests

- **UT-1**: curve functions produce expected monotonic ramp from 0→target and teardown target→0 for each curve type.
- **UT-2**: phase schedule transitions correctly across ramp → hold → teardown given configured durations.
- **UT-3**: with a fixed seed, dry-run produces a stable outcome sequence.

### Integration tests

- **IT-1**: dry-run end-to-end produces an observed failure ratio that increases during ramp and decreases during teardown (trend checks) and stays near target during hold (within tolerance).

### Traceability

|Backlog item|Tests|
|---|---|
|SLI-18|UT-1, UT-2, UT-3, IT-1|
