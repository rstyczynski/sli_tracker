# Sprint 7 - Test Specification

## Sprint Test Configuration

- Test: smoke, unit, integration
- Mode: managed
- Regression: none

## Smoke Tests

Smoke tests verify the most critical functionality quickly (seconds, not minutes).

### SM-1: emit.sh produces valid JSON from core functions

- **What it verifies:** `sli_build_base_json` and `sli_unescape_json_fields` produce valid JSON output
- **Pass criteria:** All function outputs parse as valid JSON via `jq`; unescape correctly converts escaped JSON strings to native types
- **Why it's smoke:** If emit.sh can't produce valid JSON, the entire SLI pipeline is broken — no event can be pushed to OCI
- **Target file:** `tests/smoke/test_critical_emit.sh`

## Unit Tests

Unit tests are migrated from their original locations. No new unit test functions are created in this sprint — the migration itself is the deliverable.

### UT-1: emit.sh helper functions (migrated)

- **Input:** Various JSON strings, environment variables
- **Expected Output:** Correct JSON transformations, path expansions, context merges
- **Edge Cases:** Empty strings, null, invalid JSON, nested objects, tilde expansion
- **Isolation:** Pure function tests (source `emit.sh` directly), no mocks needed
- **Target file:** `tests/unit/test_emit.sh` (migrated from `.github/actions/sli-event/tests/test_emit.sh`)

### UT-2: install_oci_cli.sh container tests (migrated)

- **Input:** Ubuntu, Alpine, Fedora containers
- **Expected Output:** Install succeeds on Ubuntu, fails on unsupported OS
- **Edge Cases:** VENV_PATH with tilde, pinned version
- **Isolation:** Container-based via podman
- **Target file:** `tests/unit/test_install_oci_cli.sh` (migrated from `.github/actions/install-oci-cli/tests/test_install_oci_cli.sh`)

### UT-3: oci_profile_setup.sh round-trip tests (migrated)

- **Input:** Synthetic OCI config payloads
- **Expected Output:** Pack/unpack fidelity, wrapper creation, error rejection
- **Edge Cases:** Empty payload, malformed base64, missing config
- **Isolation:** Temp directories, no real OCI access
- **Target file:** `tests/unit/test_oci_profile_setup.sh` (migrated from `.github/actions/oci-profile-setup/tests/test_oci_profile_setup.sh`)

## Integration Tests

### IT-1: Full SLI pipeline (migrated)

- **Preconditions:** Authenticated `gh` CLI, OCI CLI with DEFAULT profile, `jq`, `oci_scaffold` submodule
- **Steps:** Dispatch model-call and model-push workflows, wait for completion, query OCI logs
- **Expected Outcome:** At least 12 OCI events, correct success/failure outcomes, native JSON arrays
- **Verification:** Assert event counts, outcome types, field types via `jq`
- **Target file:** `tests/integration/test_sli_integration.sh` (migrated from `progress/sprint_6/test_sli_integration.sh`)

## Traceability

| Backlog Item | Smoke | Unit Tests | Integration Tests |
|---|---|---|---|
| SLI-10 | SM-1 | UT-1, UT-2, UT-3 | IT-1 |

Note: UT-1/UT-2/UT-3 and IT-1 are migrations of existing tests. SM-1 is new.
