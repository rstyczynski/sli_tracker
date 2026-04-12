# Sprint 26 — Bug Fixes

## Status: Fixed

## SLI-41-1 — Router Fn integration test did not exercise `workflow_run` → OCI Monitoring

**Root cause:** `tests/integration/test_fn_apigw_object_storage_passthrough.sh` only POSTed generic and `ping` payloads and asserted Object Storage keys, so Sprint 26 could pass integration while the deployed path never sent a completed `workflow_run` or proved `postMetricData` succeeded.

**Fix:** After the existing bucket checks, POST a fixture-shaped completed `workflow_run` with a unique `workflow_run.name`, verify `ingest/github/workflow_run/<object>`, then poll `tools/sli_compute_sli_metrics.js` (namespace `github_actions`, metric `workflow_run_result`, dimension `workflow=<marker>`) until `total_count >= 1` or attempts exhausted. Optional skip via `SLI_SKIP_FN_WORKFLOW_RUN_METRICS=1` for environments without metric ingest latency tolerance.

**Files:** `tests/integration/test_fn_apigw_object_storage_passthrough.sh`, `PLAN.md`, `PROGRESS_BOARD.md`

**Verification:** `bash tests/integration/test_fn_apigw_object_storage_passthrough.sh` (with live OCI); `bash -n` on script.

**Status:** Fixed

---

## Fix Summary

| Bug | Description | Files Changed | Status |
|-----|-------------|---------------|--------|
| SLI-41-1 | APIGW integration did not validate `workflow_run` metrics end-to-end | `test_fn_apigw_object_storage_passthrough.sh`, `PLAN.md`, `PROGRESS_BOARD.md` | Fixed |
