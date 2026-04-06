# Sprint 9 — Failure Summary

**Sprint:** 9 — emit_curl workflow and integration test
**Backlog Item:** SLI-12
**Status:** Failed
**Date:** 2026-04-06

---

## What was accomplished

1. **Workflow created:** `.github/workflows/model-emit-curl.yml` — dispatches via `workflow_dispatch`, uses `oci-profile-setup` with `oci-auth-mode: none` (no OCI CLI), calls `sli-event` with `emit-backend: curl`.
2. **Self-contained OCI profile packing:** `setup_oci_github_access.sh` updated to build a single-profile tarball where session profile `[SLI_TEST]` includes all fields (`tenancy`, `user`, `fingerprint`, `key_file`, `region`, `security_token_file`) copied from `[DEFAULT]` if missing.
3. **Session token support in `emit_curl.sh`:** Added logic to read `security_token_file` and conditionally use it for authentication.
4. **Integration test:** `tests/integration/test_sli_emit_curl_workflow.sh` — 7 test sections (T1–T7) covering dispatch, completion, conclusions, no OCI CLI install, curl notice, OCI event content, and `failure_reasons`.
5. **Partial test pass:** 12 of 18 assertions pass (T1–T4 all green).

## What failed

`emit_curl.sh` cannot successfully push events to OCI Logging when using a **session-token** profile. The curl-based HTTP request signing returns **HTTP 401**.

### Investigation timeline

| Attempt | keyId format | Signing approach | HTTP result | OCI error |
|---------|-------------|-----------------|-------------|-----------|
| 1 | `tenancy/user/fingerprint` | Standard 6-header signing, no security token header | 401 | `INVALID_AUTHENTICATION_INFO` — "Requested resource not found" |
| 2 | `tenancy/user/fingerprint` | 7-header signing with `x-security-token` in signed headers | 401 | `INVALID_AUTHENTICATION_INFO` — "Requested resource not found" |
| 3 | `ST$<token>` | Standard 6-header signing, no security token header | 401 | `SIGNATURE_NOT_VALID` — "Failed to verify the HTTP(S) Signature" |

### Key observations

- Attempt 3 shows progress: the `ST$` keyId is **recognized** (error changes from "resource not found" to "signature not valid"), meaning the token itself is valid and the session exists.
- The signature verification fails, which means either:
  - The signing string construction doesn't match what OCI expects for `ST$` auth
  - The session private key doesn't match what OCI expects for this token
  - There's an encoding/escaping issue with the token or signature in the Authorization header

## Root cause hypothesis

The exact OCI REST API signing protocol for `ST$` session-token authentication is not fully understood. The OCI Python SDK uses `SecurityTokenSigner` which sets `keyId = "ST$" + token` and signs with the session private key, but the exact set of signed headers and signing string format used by the SDK may differ from what we're constructing manually.

## Artifacts

- Diagnostic job logs: runs `24032701815`, `24032805336`, `24032884236`, `24032928194`, `24032970835`, `24033077650`
- Integration test logs: `tests/integration/test_run_curl_20260406_*.log`
- OCI query results: `tests/integration/oci_logs_curl_20260406_*.json`
- Progress copies: `progress/integration_runs/curl_20260406_*`

## Recommended next steps

1. **Study OCI SDK source code:** Trace the exact signing string construction in `oci.signer.SecurityTokenSigner` (Python) to determine the precise header set and ordering for `ST$` auth.
2. **Compare with working `emit_oci.sh`:** Add `--debug` to an `oci logging-ingestion put-logs` call and capture the raw HTTP request headers and signing string for comparison.
3. **Consider API-key auth fallback:** If session-token signing proves too complex for raw curl, the workflow could use a dedicated API key (no session) which has a simpler `tenancy/user/fingerprint` keyId and standard signing.
4. **Test with API-key profile:** Create a non-session OCI profile (static API key) and test `emit_curl.sh` with it — this isolates whether the signing logic itself works and the issue is purely session-token specific.

## Commits made during sprint

- `feat: (emit_curl) add session token support + model-emit-curl workflow`
- `fix: (setup_oci_github_access) build self-contained single-profile config`
- `fix: (emit_curl) revert DEFAULT fallback — expect self-contained profile`
- `fix: (emit_curl) include x-security-token in signing string`
- `fix: (emit_curl) use ST$ keyId for session-token auth`
- `debug: (emit_curl) show HTTP status code on push failure` (diagnostic, to be cleaned up)
- `debug: (emit_curl) remove -f flag so 401 body is captured` (diagnostic, to be cleaned up)

## Current state of `emit_curl.sh`

The file currently contains diagnostic code (response body capture, no `-f` flag). Before the next attempt, this should be cleaned up or the diagnostic mode should be made conditional.
