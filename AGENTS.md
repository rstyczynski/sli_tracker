# AGENTS.md

This file is the entry point for all AI agents working in this repository.

## Mandatory Reading Order

1. **This file** — discovery index
2. **PLAN.md** — find active sprint (Status: Progress), extract Mode/Test/Regression
3. **rup_manager_simplified.md** — execute the 5-phase RUP cycle

## Quick Reference

| Task | Start Here |
|------|------------|
| Define backlog item | `PLAN.md` → add to Backlog section |
| Open a sprint | `PLAN.md` → set Status: Progress, Mode, Test, Regression |
| Execute sprint | `rup_manager_simplified.md` → follow phases 0-5 |
| Test definitions | `agent_qualitygate.md` §1-4 |
| Test execution | `tests/run.sh --help` |

## Key Files

| File | Purpose |
|------|---------|
| `PLAN.md` | Backlog items + sprint definitions |
| `PROGRESS_BOARD.md` | Current state tracking (item/sprint status) |
| `rup_manager_simplified.md` | Sprint execution process (5 phases) |
| `agent_qualitygate.md` | Test-first quality gates (smoke/unit/integration) |
| `tests/run.sh` | Test runner entry point |

## Sprint Execution Summary

```
Step 0: Detect Mode + Test params from PLAN.md → display banner
Phase 1: Setup (contract + analysis) → sprint_N_setup.md
Phase 2: Design + test spec + skeletons → sprint_N_design.md
Phase 3: Construction (fill TODO stubs) → sprint_N_implementation.md
Phase 4: Quality gates (Phase A + B) → log files + sprint_N_tests.md
Phase 5: Wrap-up (README + backlog traceability) → commit, push
Step 6: Final Summary (MANDATORY)
```

## Test Modes

| Mode | Directory | Purpose |
|------|-----------|---------|
| smoke | `tests/smoke/` | Quick critical check — "is build testable?" |
| unit | `tests/unit/` | Isolated logic tests with mocks |
| integration | `tests/integration/` | End-to-end with real infrastructure |

## Quality Gates

- **Phase A** (new-code): A1 smoke → A2 unit → A3 integration (`--new-only`)
- **Phase B** (regression): B1 smoke → B2 unit → B3 integration (full or `--component`)

All gates produce mandatory timestamped logs in `progress/sprint_N/`.

## Component Manifests

Tests are organized by component for scoped regression:

| Component | Manifest |
|-----------|----------|
| router | `tests/manifests/component_router.manifest` |
| emit | `tests/manifests/component_emit.manifest` |
| oci-setup | `tests/manifests/component_oci_setup.manifest` |
| sli-metrics | `tests/manifests/component_sli_metrics.manifest` |
| install | `tests/manifests/component_install.manifest` |

Usage: `tests/run.sh --unit --component router`
