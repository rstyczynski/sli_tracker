# Sprint 9 — Analysis

Status: Complete

## Sprint Overview

Sprint 9 adds a dedicated GitHub Actions workflow that exercises the curl emit backend (`emit-backend: curl`) end-to-end on CI runners **without** installing OCI CLI. An integration test dispatches the workflow, verifies job logs, and queries OCI Logging for received events.

## Backlog Items Analysis

### SLI-12. Dedicated GitHub Actions workflow for `emit_curl.sh` (no OCI CLI install)

**Requirement Summary:**
- New workflow file (`model-emit-curl.yml`) triggered by `workflow_dispatch`.
- Job uses `oci-profile-setup` to unpack `~/.oci` (config + API key) but skips `install-oci-cli`.
- Calls `sli-event` with `emit-backend: curl`; the curl backend signs requests using the API key from the profile.
- New integration test script dispatches the workflow via `gh workflow run`, waits for completion, checks job logs for "SLI log entry pushed to OCI Logging", and queries OCI Logging for the event.

**Technical Approach:**
- Reuse existing `oci-profile-setup` action (unpacks `OCI_CONFIG_PAYLOAD` secret).
- The curl backend reads `tenancy`, `user`, `fingerprint`, `key_file`, `region` from the profile — no OCI CLI binary needed.
- Workflow is minimal: checkout → profile setup → trivial step → sli-event (curl).
- Integration test follows `test_sli_integration.sh` pattern (T6/T7 style).

**Dependencies:**
- Sprint 8 (SLI-11) — `emit_curl.sh` must exist and be functional (Done).
- `OCI_CONFIG_PAYLOAD` secret and `SLI_OCI_LOG_ID` variable must be set on the repo.

**Testing Strategy:**
- Integration: dispatch workflow, verify job logs + OCI Logging query.
- Regression: `tests/run.sh --unit` (existing unit tests).

**Risks/Concerns:**
- `oci-profile-setup` currently calls `oci_profile_setup.sh` which may assume OCI CLI is present for the token_based wrapper; for API-key profiles, this is a no-op so it should be fine. **YOLO assumption**: the setup script unpacks config without requiring the OCI binary; the token_based wrapper is only created if OCI CLI is found.
- Session-based auth (security_token) requires the OCI CLI wrapper; API-key auth via curl signs with the PEM key directly. The workflow should use `oci-auth-mode: api_key` (or confirm that `token_based` wrapper creation degrades gracefully when no OCI CLI is installed).

**Compatibility:** Fully compatible with existing workflows; no changes to them.

## Overall Sprint Assessment

**Feasibility:** High
**Estimated Complexity:** Simple
**Prerequisites Met:** Yes (Sprint 8 complete)

## YOLO Mode Decisions

### Assumption 1: oci-auth-mode for curl workflow
**Issue**: Should the curl workflow use `oci-auth-mode: token_based` or `api_key`?
**Assumption**: Use `api_key` since there is no OCI CLI to create the `--auth security_token` wrapper. The profile setup just unpacks the packed config; `emit_curl.sh` reads fields directly from the config file and signs with the PEM key.
**Rationale**: `emit_curl.sh` does its own signing; it never invokes `oci` binary.
**Risk**: Low — if the packed config only has session tokens and no API key, the push will fail. But the existing `OCI_CONFIG_PAYLOAD` contains an API-key profile alongside the session profile.

## Readiness for Design Phase

Confirmed Ready
