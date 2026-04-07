## Contract

Sprint 12 — YOLO mode. Contracting rules carried from Sprint 7 (on file).

**Scope constraint:** Changes limited to emit scripts only — `emit_common.sh`, `emit_curl.sh`, `emit_oci.sh`. No workflow YAML files touched. No new actions.

**Responsibilities:**
- Add `sli_emit_metric()` helper to `emit_common.sh`
- Call it from both backends based on `EMIT_TARGET`
- Add unit tests to `tests/unit/test_emit.sh`
- Add integration test `tests/integration/test_sli_emit_metric.sh`
- Commit per phase; push after each commit

**Open Questions:** None.

---

## Analysis

### SLI-17: emit.sh dual-target — OCI Logging and/or OCI Monitoring metric

**Requirement Summary:**
Add `EMIT_TARGET` env var (values: `log`, `metric`, `log,metric`; default `log,metric`) to control whether each backend pushes to OCI Logging, posts to OCI Monitoring, or both.

**OCI Monitoring API for custom metrics:**
- Endpoint: `POST https://telemetry-ingestion.{region}.oraclecloud.com/20180401/metrics`
- Auth: same OCI request signing as Logging (RSA-SHA256 with same profile fields)
- Payload (MetricData array):
  ```json
  [{"namespace":"sli_tracker","name":"outcome","compartmentId":"<compartment>",
    "dimensions":{"workflow_name":"...","workflow_job":"...","repo_repository":"...","repo_ref":"..."},
    "datapoints":[{"timestamp":"<ISO8601>","value":1}]}]
  ```
- `value`: 1 for `success`, 0 for everything else (`failure`, `cancelled`, `skipped`)
- `namespace`: `SLI_METRIC_NAMESPACE` env var, default `sli_tracker`
- `compartmentId`: needs the tenancy OCID (from OCI config profile `tenancy` field) — OCI Monitoring requires this

**Implementation plan:**
1. Add `sli_outcome_to_metric_value()` to `emit_common.sh` — maps outcome string → 0/1
2. Add `sli_emit_metric()` to `emit_common.sh` — builds metric payload, signs and POSTs via curl (same signing logic, different host/path)
3. Both `emit_curl.sh` and `emit_oci.sh`: after assembling `LOG_ENTRY`, check `EMIT_TARGET`:
   - contains `log` → push logging (current code)
   - contains `metric` → call `sli_emit_metric()`

**YOLO Decisions:**
1. `emit_oci.sh` uses OCI CLI for logging but curl for metrics (OCI CLI has no direct custom metric command without Python SDK). Acceptable: signing code already proven in emit_curl.sh.
2. Compartment OCID: use the `tenancy` field from the OCI config profile (same compartment as root). This is simplest; a dedicated `SLI_METRIC_COMPARTMENT` override can be added later.
3. `EMIT_TARGET` format: comma-separated string (`log,metric`) — simple bash substring match (`[[ "$EMIT_TARGET" == *log* ]]`).

**Compatibility:** No changes to existing log emit paths. `EMIT_TARGET` defaults to `log,metric` — existing callers that don't set it will now also post metrics (additive, non-breaking for log consumers).

### Bug (discovered during Sprint 12 testing): local `emit.sh` metric push HTTP 400

**Symptom:** Running `emit.sh` locally (outside GitHub Actions) produced HTTP 400 from OCI Monitoring metric ingestion.

**Root cause:** Local shell runs have empty `workflow.*` / `repo.*` fields, which led to invalid metric `dimensions`
(empty-string values, or an empty object after filtering).

**Fix:** Filter out empty dimension values and ensure `dimensions` is never empty (fallback `emit_env=local`).

**Verification:** Local re-run with `SLI_EMIT_CURL_VERBOSE=1` returned HTTP 2xx and printed
`::notice::SLI metric pushed to OCI Monitoring ...`.
