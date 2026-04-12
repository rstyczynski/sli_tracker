# Sprint 23 — Tests (YOLO)

Sprint mode: **YOLO**. `Test: unit, integration`. `Regression: unit` (component-scoped manifest).

## Phase A — New-code gates

| Gate | Result |
| --- | --- |
| A2 Unit (`--new-only progress/sprint_23/new_tests.manifest`) | PASS |
| A3 Integration (`--new-only progress/sprint_23/new_tests.manifest`) | PASS |

## Phase B — Regression

| Gate | Result |
| --- | --- |
| B2 Unit (`--manifest progress/sprint_23/regression_tests.manifest`) | PASS |

## Artifacts

- `progress/sprint_23/test_run_A2_unit_20260412_020003.log`
- `progress/sprint_23/test_run_A3_integration_20260412_020011.log`
- `progress/sprint_23/test_run_B2_unit_20260412_020240.log`

Additional tee copies may exist under `./logs/` with the same timestamp prefix as each run.

## Bug-fix re-run (2026-04-12) — post BUG-1/2/3/4 fixes

Fn redeployed as image `0.0.25` after fixing BUG-1 (`x-github-event` hardcode), BUG-2
(`passthrough.jsonata` guard), BUG-3 (`raw_ingest` key requirement), and BUG-4 (symlinks replacing
duplicate library copies). New tests added: UT-111, BUG-2 inline, BUG-3 inline.

| Gate | Scope | Scripts | Result |
| --- | --- | --- | --- |
| B2 Unit re-run | `--manifest progress/sprint_23/regression_tests.manifest` | 14/14 | PASS |
| A3 Integration re-run | `--manifest progress/sprint_23/new_tests.manifest` | 1/1 | PASS |

- `progress/sprint_23/test_run_B2_unit_20260412_054919.log`
- `progress/sprint_23/test_run_A3_integration_20260412_054949.log`

## Post-critical incident re-deploy (2026-04-12)

`sli-router-passthrough-dev-bucket` destroyed by integration pre-cleanup (BUG-5). Stack
redeployed as image `0.0.27`. API GW smoke check passed immediately after redeploy.
`run.sh` patched: pre-cleanup is now opt-in via `SLI_INTEGRATION_PRECLEAN=1`.

## Flaky / deferred

- None for this sprint.
