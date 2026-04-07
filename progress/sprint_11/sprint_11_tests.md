# Sprint 11 — Test execution results

**Test:** integration (per `PLAN.md`)  
**Regression:** none

## Phase A — New-code gates

### Gate A3 — Integration

**Command:** `tests/run.sh --integration --new-only progress/sprint_11/new_tests.manifest`

**Log:** `tests/integration/test_run_js_20260407_021941.log`

**Result:** PASS — `test_sli_emit_js_workflow.sh` (14 assertions, 0 failures)

- T1–T4: Dispatch, wait, conclusions, no OCI CLI install — PASS  
- T5: OCI profile restore notice in GitHub job logs — PASS (explicit `oci-profile-setup` step)  
- T6–T7: OCI Logging events and `workflow.name` — PASS  

**OCI log capture:** `tests/integration/oci_logs_js_20260407_021941.json`  
**Progress copy:** `progress/integration_runs/js_20260407_021941/`

## Phase B — Regression

Not run (`Regression: none` in `PLAN.md`).

## Summary

| Gate | Type        | Result | Retries |
|------|-------------|--------|---------|
| A3   | Integration | PASS   | 0       |

**Flaky tests deferred:** None

## Artifacts (committed)

**Canonical PASS (gate A3):**

- `tests/integration/test_run_js_20260407_021941.log`
- `tests/integration/oci_logs_js_20260407_021941.json`
- `progress/integration_runs/js_20260407_021941/integration_test_run.log`
- `progress/integration_runs/js_20260407_021941/oci_logs.json`

**Earlier integration attempts / diagnostics (same suite, pre-fix or exploratory):**

- `tests/integration/test_run_js_20260407_015657.log` — auth / early attempt  
- `tests/integration/oci_logs_js_20260407_015657.json`  
- `tests/integration/test_run_js_20260407_020001.log`  
- `tests/integration/oci_logs_js_20260407_020001.json`  
- `progress/sprint_11/test_run_A3_integration_20260407_020001.log`  
- `progress/integration_runs/js_20260407_020001/integration_test_run.log`  
- `progress/integration_runs/js_20260407_020001/oci_logs.json`  
- `tests/integration/test_run_js_20260407_020556.log`  
- `progress/sprint_11/test_run_A3_integration_20260407_020556.log`  
- `tests/integration/test_run_js_20260407_020656.log`  
- `tests/integration/oci_logs_js_20260407_020656.json`  
- `progress/sprint_11/test_run_A3_integration_20260407_020656.log`  
- `progress/integration_runs/js_20260407_020656/integration_test_run.log`  
- `progress/integration_runs/js_20260407_020656/oci_logs.json`  
- `tests/integration/test_run_js_20260407_021620.log` — run before push (remote workflow not updated)
