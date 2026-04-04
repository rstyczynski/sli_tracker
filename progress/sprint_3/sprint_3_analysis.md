# Sprint 3 — Analysis

## Items

| Item | Ask |
|------|-----|
| SLI-3 | Review `model-*.yml` for clarity, naming, alignment with sli-event |
| SLI-4 | Review `sli-event` (inputs, emit path, errors, tests) |

## YOLO Mode Decisions

1. **Review = doc + smoke test.** Assumption: no workflow YAML changes unless a defect is found; `test_emit.sh` is the acceptance bar for SLI-4.
2. **Model workflows** represent Terrateam-style patterns; comments in YAML are the spec.
3. **Risk:** Low — read-only review; CI not re-run on GitHub in this session.

## Feasibility

High. Dependencies: SLI-1/2 delivered (OCI install + profile).

## Readiness

Ready for design.
