# Sprint 27 — Bug Fixes

## Status: Fixed

## SLI-44-1 — `workflow_run_log.jsonata` not uploaded; `OCI_LOGGING_LOG_ID` not set in Fn config

**Root cause:** `tools/cycle_apigw_router_passthrough.sh` uploaded `passthrough.jsonata` and `workflow_run_metric.jsonata` but not `workflow_run_log.jsonata`. The Fn therefore failed to load `config/workflow_run_log.jsonata` from Object Storage, making the `github_workflow_run_to_log` fanout route dead on the deployed stack. Additionally, `OCI_LOGGING_LOG_ID` was never merged into the Fn function config, so `applyIngestBucketToRoutingObject` could not replace `"REPLACED_AT_RUNTIME"` with the real log OCID — every `putLogs` call used an invalid OCID and was rejected by the OCI API silently.

**Symptom:** POST of a `workflow_run` event returned `status: dead_letter` with OCI Monitoring timestamp error (the Monitoring route ran first and its failure aborted all remaining fanout deliveries before the Logging route could execute — separate backlog item SLI-45).

**Fix:** In `cycle_apigw_router_passthrough.sh`:
1. Upload `workflow_run_log.jsonata` to `config/workflow_run_log.jsonata` alongside the metric mapping.
2. Read `OCI_LOGGING_LOG_ID` from the operator environment and merge it into the Fn function config (same `jq` merge block as `OCI_MONITORING_COMPARTMENT_ID`).
3. Document `OCI_LOGGING_LOG_ID` in the script usage comment.

**Files:** `tools/cycle_apigw_router_passthrough.sh`

**Verification:** Redeploy with `OCI_LOGGING_LOG_ID=<ocid> NAME_PREFIX=sli-router-passthrough-dev FN_FORCE_DEPLOY=true bash tools/cycle_apigw_router_passthrough.sh`; POST a `workflow_run` with current timestamps; response `status: routed` with three deliveries including `github_workflow_run_to_log`; OCI Logging console shows entry with `action`, `workflow`, `repository` fields. **Live verified 2026-04-12.**

**Status:** Fixed

---

## Fix Summary

| Bug | Description | Files Changed | Status |
|-----|-------------|---------------|--------|
| SLI-44-1 | Log mapping not uploaded; log OCID not set in Fn config → logging delivery never reached OCI | `tools/cycle_apigw_router_passthrough.sh` | Fixed |
