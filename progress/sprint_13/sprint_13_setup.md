# Sprint 13 — Setup

## Contract

Sprint 13 — YOLO mode.

**Scope constraint:** Implement SLI-18 only. Keep changes minimal and script-focused.

**Responsibilities:**

- Define the SLI-18 simulator behavior and success signal
- Identify required test level per `PLAN.md` (unit + integration) and constraints

**Open Questions:** None.

---

## Analysis

### SLI-18: Controlled success/failure ratio simulator script

Backlog item requires a script that emits SLI events with a configurable success/failure ratio over time (ramp-up → hold → teardown) with selectable curve types.

**Feasibility:** Implementable as a standalone script that repeatedly invokes `.github/actions/sli-event/emit.sh` with `SLI_OUTCOME` set to success/failure based on a time-varying probability function. Provide a dry-run mode for deterministic unit/integration tests without OCI dependencies.

**Compatibility:** No changes to existing emit scripts are required. Simulator can be added as a new tool under repo root (e.g. `tools/`) and is opt-in for operators.

**Risks:** Probability-based simulation can be noisy on short time windows; tests should validate the computed target failure probability curve (and/or aggregate outcome ratio over enough samples) rather than expecting exact percentages per second.
