# Sprint 9 — Implementation Notes

## SLI-12. Dedicated GitHub Actions workflow for `emit_curl.sh` (no OCI CLI install)

Status: tested

### Implementation Summary

Three deliverables implemented:

| Artifact | Purpose | Status |
|----------|---------|--------|
| `.github/workflows/model-emit-curl.yml` | Workflow using curl backend, no OCI CLI | Complete |
| `.github/actions/sli-event/emit_curl.sh` | OCI HTTP signing (API key + session token) | Complete |
| `tests/integration/test_sli_emit_curl_workflow.sh` | Integration test for the above | Complete |

### Main Features

- **Workflow `model-emit-curl.yml`**: `workflow_dispatch` with `simulate-failure` input. Uses `oci-profile-setup` with `oci-auth-mode: none` (skips OCI CLI wrapper). Calls `sli-event` with `emit-backend: curl`.
- **Session token support**: `emit_curl.sh` reads `security_token_file` from the profile and uses `keyId="ST$<token>"` for `SecurityTokenSigner`-compatible authentication. Backward-compatible with API-key-only profiles.
- **Integration test**: dispatches 2 runs (success + failure), validates conclusions, checks job logs for "SLI log entry pushed to OCI Logging (curl)", queries OCI Logging for events.

### Design Compliance

Implementation follows the approved design. `oci-auth-mode: none` bypasses the token_based exit-on-missing-oci in `oci_profile_setup.sh` (line 58–63 guard). Session-token auth is detected by `security_token_file` and uses the session key + `ST$` `keyId` (same as `oci-python-sdk`).

### Test Results (2026-04-06)

- Integration (new-code gate): `bash tests/run.sh --integration --new-only progress/sprint_9/new_tests.manifest` — PASS (18 assertions)
- Regression (unit gate): `bash tests/run.sh --unit` — PASS (3 scripts)

### YOLO Mode Decisions

#### Decision 1: `oci-auth-mode` value
**Context**: The input accepts free text; `none` is not a documented value.
**Decision**: Used `none` — the setup script only branches on `token_based`; any other value skips the wrapper.
**Risk**: Low — if a future version adds `none` handling, it would logically mean "skip wrapper" anyway.

#### Decision 2: Curl args array
**Context**: Adding a conditional `-H` to curl required restructuring the call.
**Decision**: Used a bash array (`_curl_args`) for clean conditional header insertion.
**Risk**: None — this is idiomatic bash and avoids quoting issues with `${VAR:+...}` in a multiline curl.
