# Sprint 26 — Bug Fixes

## Status: Fixed

## SLI-41-1 — Router Fn integration test did not exercise `workflow_run` → OCI Monitoring

**Root cause:** `tests/integration/test_fn_apigw_object_storage_passthrough.sh` only POSTed generic and `ping` payloads and asserted Object Storage keys, so Sprint 26 could pass integration while the deployed path never sent a completed `workflow_run` or proved `postMetricData` succeeded.

**Fix:** After the existing bucket checks, POST a fixture-shaped completed `workflow_run` with a unique `workflow_run.name`, verify `ingest/github/workflow_run/<object>`, then poll `tools/sli_compute_sli_metrics.js` (namespace `github_actions`, metric `workflow_run_result`, dimension `workflow=<marker>`) until `total_count >= 1` or attempts exhausted. Optional skip via `SLI_SKIP_FN_WORKFLOW_RUN_METRICS=1` for environments without metric ingest latency tolerance.

**Files:** `tests/integration/test_fn_apigw_object_storage_passthrough.sh`, `PLAN.md`, `PROGRESS_BOARD.md`

**Verification:** `tests/run.sh --all` (PASS); `bash -n` on touched scripts. **SLI-41-1 follow-up:** integration POST uses **current UTC** `created_at` / `updated_at` so OCI Monitoring accepts datapoints (fixture times were >2h old). **emit_metric IT-2:** reject tenancy OCID mistaken for log OCID. **emit_curl workflow T6/T7:** poll OCI Logging with wider window and case-insensitive `emit_curl` match.

**Status:** Fixed

---

## SLI-41-2 — `SLI_PASSTHROUGH_OBJECT` forced every mapping to load `passthrough.jsonata`

**Root cause:** `buildLoadMappingFromRef` used `(process.env.SLI_PASSTHROUGH_OBJECT || config/${base})` for **all** basenames. Fn is configured with `SLI_PASSTHROUGH_OBJECT=config/passthrough.jsonata`, so routes such as `workflow_run_metric.jsonata` still fetched passthrough (`$` → raw GitHub body). The Monitoring adapter then received webhook-shaped JSON without top-level `name`, producing dead-letter errors like “metric name can not be null, empty or blank”.

**Fix:** Apply `SLI_PASSTHROUGH_OBJECT` only when the mapping basename is `passthrough.jsonata`; all other mappings load `config/<basename>`.

**Files:** `fn/router_passthrough/router_core.js`, `fn/router_passthrough/func.yaml` (version bump), `tests/unit/test_fn_passthrough_router.sh` (SLI-41-2 assertions)

**Verification:** `bash tests/unit/test_fn_passthrough_router.sh` and `bash tests/integration/test_fn_apigw_object_storage_passthrough.sh` (SLI-41-1 Monitoring poll); optional `./tools/list_monitoring_metrics.sh` with `SLI_OCI_STATE_FILE` (see `progress/sprint_26/sprint_26_tests.md`).

**Status:** Fixed

---

## Fix Summary

| Bug | Description | Files Changed | Status |
|-----|-------------|---------------|--------|
| SLI-41-1 | APIGW integration did not validate `workflow_run` metrics end-to-end | `test_fn_apigw_object_storage_passthrough.sh`, `PLAN.md`, `PROGRESS_BOARD.md` | Fixed |
| SLI-41-2 | Passthrough object path overrode all mapping loads → raw payload to Monitoring | `fn/router_passthrough/router_core.js`, `fn/router_passthrough/func.yaml` | Fixed |
