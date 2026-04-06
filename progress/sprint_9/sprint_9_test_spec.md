# Sprint 9 — Test Specification

## Sprint Test Configuration

- Test: integration
- Mode: YOLO

## Integration Tests

### IT-1: Dispatch + completion + conclusions (basic E2E)

**Script:** `tests/integration/test_sli_emit_curl_workflow.sh` (sections T1–T3)

**Steps:**
1. Dispatch `model-emit-curl.yml` with `simulate-failure=false`
2. Dispatch `model-emit-curl.yml` with `simulate-failure=true`
3. Wait for both runs to complete
4. Assert success run → conclusion `success`
5. Assert failure run → conclusion `failure`

**Pass criteria:** Both workflows complete with expected conclusions.

### IT-2: No OCI CLI install step ran

**Script:** `tests/integration/test_sli_emit_curl_workflow.sh` (section T4)

**Steps:**
1. For each run, fetch job logs via `gh api`
2. Assert logs do NOT contain `install-oci-cli` or `OCI CLI installed` markers
3. Assert logs DO contain `oci-profile-setup` / `OCI profile restored` (profile still needed)

**Pass criteria:** Zero evidence of OCI CLI installation in any job log. Profile restore confirmed.

### IT-3: Curl backend confirmation in job logs

**Script:** `tests/integration/test_sli_emit_curl_workflow.sh` (section T5)

**Steps:**
1. For the success run, fetch job logs
2. Assert logs contain curl-specific notice: `SLI log entry pushed to OCI Logging (curl)`
3. For the failure run, also confirm curl notice is present (SLI report still runs on failure)

**Pass criteria:** Both runs show the curl-specific push confirmation.

### IT-4: OCI events received with correct content

**Script:** `tests/integration/test_sli_emit_curl_workflow.sh` (section T6)

**Steps:**
1. Query OCI Logging for events in last 15 minutes
2. Assert at least 2 events total
3. Assert at least 1 event with `outcome=success`
4. Assert at least 1 event with `outcome=failure`
5. Assert events carry the correct `workflow` field (matching `MODEL — emit_curl (no OCI CLI)`)

**Pass criteria:** OCI has events from both runs with correct outcome and workflow values.

### IT-5: Failure run carries `failure_reasons`

**Script:** `tests/integration/test_sli_emit_curl_workflow.sh` (section T7)

**Steps:**
1. From the OCI events, select those with `outcome=failure`
2. Assert `failure_reasons` object is non-empty (has at least 1 key)
3. Assert a key like `SLI_FAILURE_REASON_STEP_MAIN` exists (the failed step)

**Pass criteria:** Failure event in OCI contains meaningful `failure_reasons`.

## Regression

Run `tests/run.sh --unit` — all 33 unit tests must pass (0 failures).

## Traceability

| Backlog Item | Integration Tests |
|--------------|-------------------|
| SLI-12       | IT-1, IT-2, IT-3, IT-4, IT-5 |
