# Sprint 12 — Test Results

Sprint: 12 | Mode: YOLO | Test: integration | Regression: unit

## Gate A3 — Integration (new-code gate)

**Result: PASS** | Retries: 2 (retry 1: HTTP 400 metricData wrapper missing; retry 2: MQL syntax + auth wrapper)

| Test | Result | Notes |
|---|---|---|
| IT-1: EMIT_TARGET=metric — metric-only push | PASS | No log push; OCI Monitoring receives datapoint |
| IT-1b: OCI Monitoring datapoint present | PASS | Found 2 datapoints within 30s poll |
| IT-2: EMIT_TARGET=log,metric — dual push | PASS | Both log and metric success notices |
| IT-2 log push success | PASS | OCI Logging push confirmed |
| IT-2 metric push success | PASS | OCI Monitoring metric confirmed |

**5/5 assertions pass.**

Issues fixed during retries:
- Retry 1: OCI Monitoring API body must be `{"metricData": [...]}` not bare array `[...]`
- Retry 2: OCI MQL query `outcome[5m]{}.mean()` invalid — empty `{}` not allowed; fixed to `outcome[5m].mean()`; also installed token-based wrapper aligned to profile auth type (not hardcoded `--auth security_token`)

## Gate B2 — Unit Regression

**Result: PASS (with pre-existing known failure)** | Retries: 1 (UT-4/5 EMIT_TARGET=log fix)

| Script | Result | Notes |
|---|---|---|
| test_emit.sh | PASS — 54/0 | All Sprint 12 unit stubs + prior tests pass |
| test_oci_profile_setup.sh | PASS | Unrelated to Sprint 12 |
| test_install_oci_cli.sh | FAIL (pre-existing) | OCI CLI VENV_PATH tilde install; unrelated to Sprint 12; last changed Sprint 7 (6cb29db) |

Issue fixed during retry: UT-4 and UT-5 mock curl was capturing metric payload (new default `EMIT_TARGET=log,metric`) instead of log payload — added explicit `EMIT_TARGET=log` to those unit tests.

**Sprint status: `implemented_partially`** — all Sprint 12 code and tests pass; the single regression (`test_install_oci_cli.sh`) is a pre-existing failure predating this sprint.

## Artifacts

| Gate | Log |
|---|---|
| A3 integration (attempt 1) | `progress/sprint_12/test_run_A3_integration_20260407_070432.log` |
| A3 integration (attempt 2) | `progress/sprint_12/test_run_A3_integration_20260407_070835.log` |
| A3 integration (final PASS) | `progress/sprint_12/test_run_A3_integration_20260407_071451.log` |
| B2 unit (attempt 1) | `progress/sprint_12/test_run_B2_unit_20260407_065941.log` |
| B2 unit (final) | `progress/sprint_12/test_run_B2_unit_20260407_071541.log` |
| OCI metric capture | `tests/integration/oci_metric_20260407_071451.json` |

## Deferred

- `test_install_oci_cli.sh` VENV_PATH tilde expansion inside Ubuntu container — pre-existing defect, tracked for a future sprint.

## Post-merge Bugs Fixed

### BUG-S12-1: `STEPS_JSON: unbound variable` in debug print

- **Symptom:** `emit_curl.sh: line 32: STEPS_JSON: unbound variable` when `STEPS_JSON` is not exported (e.g. local quick-start runs)
- **Root cause:** `echo "$STEPS_JSON" | jq .` in both `emit_curl.sh` and `emit_oci.sh` uses bare variable reference; `set -u` fails when `STEPS_JSON` is not set
- **Fix:** Changed to `echo "${STEPS_JSON:-}" | jq .` in both backends (commit 42d9425)

### BUG-S12-2: `compartmentId` hardcoded to `tenancy`; blocked metric push when tenancy absent

- **Symptom:** `SLI metric push failed (non-fatal, HTTP 400)` when session-token profiles don't carry `tenancy` field; or earlier guard blocked push entirely
- **Root cause:** Sprint 12 introduced `compartmentId` derived only from `tenancy` field in OCI profile; no override; guard blocked push when tenancy missing
- **Fix:** Added `SLI_METRIC_COMPARTMENT` env var (defaults to `tenancy` from profile); removed preemptive tenancy guard — OCI 400 is non-fatal warning. `compartmentId` is still required by OCI Monitoring API (confirmed: POST without it returns 400)
- **Commit:** see fix after 42d9425
