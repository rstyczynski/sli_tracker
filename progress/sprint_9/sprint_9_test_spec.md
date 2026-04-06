# Sprint 9 — Test Specification

## Sprint Test Configuration

- Test: integration
- Mode: YOLO

## Integration Tests

### IT-1: emit_curl workflow end-to-end

**Script:** `tests/integration/test_sli_emit_curl_workflow.sh`

**Preconditions:**
- `gh` CLI authenticated
- OCI profile for `logging-search` (same as `test_sli_integration.sh`)
- `SLI_OCI_LOG_ID` repo variable set
- `OCI_CONFIG_PAYLOAD` repo secret set (includes session profile)

**Steps:**
1. Auth gate: verify OCI profile works (`oci iam region list`)
2. Resolve OCI log/log-group via oci_scaffold (reuse same URI as existing tests)
3. Dispatch `model-emit-curl.yml` with `simulate-failure=false` → expect `success`
4. Dispatch `model-emit-curl.yml` with `simulate-failure=true` → expect `failure`
5. Wait for both runs to complete (poll via `gh run view`)
6. Assert conclusions match expectations
7. Check job logs for "SLI log entry pushed to OCI Logging" (success run)
8. Query OCI Logging for events in last 15 min; assert at least 2 events from this workflow

**Pass criteria:**
- Both workflows complete with expected conclusions
- Success run logs show "SLI log entry pushed to OCI Logging"
- OCI Logging returns at least 1 success + 1 failure event

## Traceability

| Backlog Item | Integration Tests |
|--------------|-------------------|
| SLI-12       | IT-1              |
