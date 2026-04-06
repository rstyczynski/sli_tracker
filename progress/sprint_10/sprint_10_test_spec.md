# Sprint 10 - Test Specification

## Sprint Test Configuration
- Test: unit, integration
- Mode: YOLO

## Unit Tests (Test: includes unit)

### UT-S10-1: sli_build_base_json — nested workflow object shape
- **Input:** fake GITHUB_* env vars (same as existing test)
- **Expected Output:** `workflow` key is an object with fields: `run_id`, `run_number`, `run_attempt`, `name`, `ref`, `job`, `event_name`, `actor`
- **Edge Cases:** all values present; empty values produce empty strings inside nested objects (not null)
- **Isolation:** no mocks; jq available
- **Target file:** tests/unit/test_emit.sh (update existing `sli_build_base_json` test + add new focused assertion)

### UT-S10-2: sli_build_base_json — nested repo object shape
- **Input:** fake GITHUB_* env vars
- **Expected Output:** `repo` key is an object with fields: `repository`, `repository_id`, `ref`, `ref_full`, `sha`
- **Edge Cases:** none beyond existing
- **Isolation:** same as UT-S10-1
- **Target file:** tests/unit/test_emit.sh (same test block as UT-S10-1)

### UT-S10-3: sli_build_base_json — old flat fields absent
- **Input:** fake GITHUB_* env vars
- **Expected Output:** top-level keys `workflow_run_id`, `workflow_run_number`, `workflow_run_attempt`, `workflow_ref`, `repository`, `repository_id`, `ref`, `ref_full`, `sha`, `job`, `event_name`, `actor` must NOT exist
- **Target file:** tests/unit/test_emit.sh

## Integration Tests (Test: includes integration)

### IT-S10-1: emit_oci workflow — events land with nested schema
- **Preconditions:** OCI credentials in secrets, `gh` CLI authenticated
- **Steps:** dispatch main SLI workflow, wait for completion, query OCI Logging with new jq path `.workflow.name`
- **Expected Outcome:** events found using `.workflow.name` filter; `.workflow.run_id`, `.repo.repository` present
- **Verification:** `test_sli_integration.sh` updated jq filters pass
- **Target file:** tests/integration/test_sli_integration.sh (update existing jq filters)

### IT-S10-2: emit_curl local — events land with nested schema
- **Preconditions:** OCI credentials, local machine
- **Steps:** run `test_sli_emit_curl_local.sh`, query OCI, assert `.workflow.name` matches
- **Expected Outcome:** event found via `.workflow.name | test("LOCAL")`
- **Target file:** tests/integration/test_sli_emit_curl_local.sh (update existing jq filter)

### IT-S10-3: emit_curl workflow — events land with nested schema
- **Preconditions:** OCI credentials in GitHub secrets, `gh` CLI authenticated
- **Steps:** dispatch curl workflow, wait, query OCI via `.workflow.name`
- **Expected Outcome:** event found via `.workflow.name | test("emit_curl")`
- **Target file:** tests/integration/test_sli_emit_curl_workflow.sh (update existing jq filter)

## Traceability

| Backlog Item | Unit Tests             | Integration Tests          |
|---|---|---|
| SLI-13 | UT-S10-1, UT-S10-3 | IT-S10-1, IT-S10-2, IT-S10-3 |
| SLI-14 | UT-S10-2, UT-S10-3 | IT-S10-1, IT-S10-2, IT-S10-3 |
| SLI-15 | UT-S10-1, UT-S10-2, UT-S10-3 | IT-S10-1, IT-S10-2, IT-S10-3 |
