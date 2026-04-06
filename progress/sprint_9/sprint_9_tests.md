# Sprint 9 — Tests

## Test Configuration

- Test: integration
- Regression: unit

## Integration (New-Code Gate)

Script: `tests/integration/test_sli_emit_curl_workflow.sh`

| ID | Section | What it verifies |
|----|---------|------------------|
| IT-1 | T1–T3 | Dispatch success + failure, wait, assert conclusions |
| IT-2 | T4 | Job logs confirm **no OCI CLI install**; profile restore present |
| IT-3 | T5 | Job logs contain curl-specific notice (`pushed to OCI Logging (curl)`) |
| IT-4 | T6 | OCI Logging has ≥2 events with correct `outcome` and `workflow` fields |
| IT-5 | T7 | Failure event carries non-empty `failure_reasons` incl. `STEP_MAIN` key |

**Status:** PENDING (requires live dispatch — operator runs manually or via Phase 4.1)

## Regression (Unit Gate)

Run `tests/run.sh --unit` — all 33 unit tests must pass (0 failures).

## Test Summary

| Suite | Script | Cases | Status |
|-------|--------|-------|--------|
| Integration (new) | `test_sli_emit_curl_workflow.sh` | IT-1..IT-5 | PENDING |
| Regression (unit) | `tests/run.sh --unit` | 33 | PENDING |
