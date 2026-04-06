# Sprint 10 - Test Execution Results

## Phase A: New-Code Gates

### Gate A2 — Unit (Test: unit)

**Command:** `tests/run.sh --unit`
**Log:** `progress/sprint_10/test_run_A2_unit_20260406_153416.log` (approx)
**Result:** PASS — 3/3 scripts, 47+4+7 = 58 tests passed, 0 failed
- UT-S10-1: workflow nested object — PASS
- UT-S10-2: repo nested object — PASS
- UT-S10-3: old flat fields absent — PASS (14 field checks)

### Gate A3 — Integration (Test: integration)

**Command:** `tests/run.sh --integration`
**Log:** `progress/sprint_10/test_run_A3_integration_20260406_153416.log`
**Result:** PASS (after 1 retry — stale hardcoded unit count 33→47 fixed)
- test_sli_emit_curl_local.sh: 2/2 PASS — new `.workflow.name` filter verified in live OCI
- test_sli_emit_curl_workflow.sh: 18/18 PASS — `.workflow.name` filter passes in GitHub Actions
- test_sli_integration.sh: 46/47 → 47/47 PASS (T1 count fixed)

**Retry 1:** Fixed `assert_eq "emit.sh unit tests: passed count" "33"` → `"47"` (stale assertion, not a production bug).

---

## Phase B: Regression Gates

### Gate B2 — Unit Regression (Regression: unit)

**Command:** `tests/run.sh --unit`
**Log:** `progress/sprint_10/test_run_B2_unit_20260406_154456.log` (approx)
**Result:** PASS — 3/3 scripts, 58 tests, 0 failures

### Gate B3 — Integration Regression (Regression: integration)

**Command:** `tests/run.sh --integration`
**Log:** `progress/sprint_10/test_run_B3_integration_20260406_154456.log`
**Result:** PASS — 3/3 scripts, 0 failures
- test_sli_emit_curl_local.sh: 2/2 PASS
- test_sli_emit_curl_workflow.sh: 18/18 PASS
- test_sli_integration.sh: 47/47 PASS

---

## Summary

| Gate | Type | Result | Retries |
|---|---|---|---|
| A2 | Unit new-code | PASS | 0 |
| A3 | Integration new-code | PASS | 1 (stale count) |
| B2 | Unit regression | PASS | 0 |
| B3 | Integration regression | PASS | 0 |

**Flaky tests deferred:** None

## Artifacts

- `progress/sprint_10/test_run_A2_unit_*.log`
- `progress/sprint_10/test_run_A3_integration_20260406_153416.log`
- `progress/sprint_10/test_run_B2_unit_*.log`
- `progress/sprint_10/test_run_B3_integration_20260406_154456.log`
- OCI log captures: `tests/integration/oci_logs_*.json`
