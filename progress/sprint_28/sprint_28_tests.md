# Sprint 28 — Quality Gates (SLI-47)

## Status: PASS

## Gates executed

| Gate | Command | Result | Retries |
| ---- | ------- | ------ | ------- |
| A2 Unit | `tests/run.sh --unit --new-only progress/sprint_28/new_tests.manifest` | PASS (1/1) | 0 |
| B2 Unit | `tests/run.sh --unit --component router` | PASS (14/14) | 0 |

A3 integration and B3 integration not applicable (sprint `Test: unit`, `Regression: unit`).

## Gate details

### A2 — New-code unit gate

Filtered to `new_tests.manifest` (1 script: `test_run_sh_component.sh`).
All 8 assertions passed: component resolution, nonexistent component error, union with `--manifest`,
CWD enforcement (no `state-*.json` in project root), `--new-only` + `--component` incompatibility.

### B2 — Router regression gate

`--component router` resolved to `tests/manifests/component_router.manifest` (14 unit scripts).
Non-router scripts (`test_emit.sh`, `test_install_oci_cli.sh`, `test_oci_profile_setup.sh`, etc.)
were correctly skipped. All 14 router scripts passed.

## Artifacts

- `progress/sprint_28/test_run_A2_unit_20260412_212331.log`
- `progress/sprint_28/test_run_B2_unit_20260413_082410.log`
