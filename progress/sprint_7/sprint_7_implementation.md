# Sprint 7 - Implementation Notes

## SLI-10. Implement test-first quality gates

Status: Progress

### Implementation Summary

Bootstrapped the centralized test infrastructure defined in `agent_qualitygate.md`. Created a working test runner, migrated all existing tests to the centralized `tests/` tree, created initial smoke tests, and validated everything passes through the full quality gate pipeline.

### Main Features

- **Centralized test runner** (`tests/run.sh`): Discovers and executes `test_*.sh` scripts in `tests/smoke/`, `tests/unit/`, `tests/integration/`. Supports `--new-only <manifest>` for filtering to sprint-specific tests. Returns nonzero on any failure.
- **Test migration**: Four test scripts moved to `tests/` with backward-compatible wrapper scripts at old locations.
- **Smoke test**: `tests/smoke/test_critical_emit.sh` verifies emit.sh core functions produce valid JSON.

### Code Artifacts

| Artifact | Purpose | Status | Tested |
|----------|---------|--------|--------|
| `tests/run.sh` | Centralized test runner | Enhanced | Yes |
| `tests/smoke/test_critical_emit.sh` | Smoke test for emit.sh | New | Yes |
| `tests/unit/test_emit.sh` | Unit tests for emit.sh | Migrated | Yes |
| `tests/unit/test_install_oci_cli.sh` | Unit tests for install script | Migrated | Yes |
| `tests/unit/test_oci_profile_setup.sh` | Unit tests for profile setup | Migrated | Yes |
| `tests/integration/test_sli_integration.sh` | Integration tests for SLI pipeline | Migrated | Yes |
| `.github/actions/sli-event/tests/test_emit.sh` | Wrapper to new location | Replaced | Yes |
| `.github/actions/install-oci-cli/tests/test_install_oci_cli.sh` | Wrapper to new location | Replaced | Yes |
| `.github/actions/oci-profile-setup/tests/test_oci_profile_setup.sh` | Wrapper to new location | Replaced | Yes |

### Testing Results

**Quality Gates (Phase 4.1):**

| Gate | Suite | Scripts | Assertions | Result |
|------|-------|---------|------------|--------|
| A1 | Smoke | 1 | 7 | PASS |
| A2 | Unit | 3 | 35 | PASS |
| A3 | Integration | 1 | 46 | PASS |

**Regression:** None (migration sprint — no prior tests in `tests/` tree)

**Retries used:** 2 (Gate A3 failed once due to expired OCI session token, passed after token refresh)

### Known Issues

- `test_install_oci_cli.sh` requires podman to be running. If podman machine is not started, the test will fail with a clear error message.
- Integration test requires live OCI tenancy with valid session token and GitHub API access.
- `--new-only` manifest filtering operates at script level, not function level. Function-level granularity is deferred.

### Design Compliance

Implementation follows the approved design from `sprint_7_design.md`:
- Path resolution uses `REPO_ROOT` derived from `SCRIPT_DIR` in all migrated tests
- Wrapper scripts use `exec` for transparent delegation
- Manifest filtering reads suite:script entries and filters accordingly

### User Documentation

#### Usage

**Run all tests:**

```bash
tests/run.sh --all
```

**Run specific suites:**

```bash
tests/run.sh --smoke
tests/run.sh --unit
tests/run.sh --integration
```

**Run only new tests for a sprint (new-code gates):**

```bash
tests/run.sh --smoke --unit --new-only progress/sprint_7/new_tests.manifest
```

**Backward-compatible invocation via old paths:**

```bash
bash .github/actions/sli-event/tests/test_emit.sh
```

#### Prerequisites

- `jq` for JSON processing
- `podman` for install_oci_cli tests (machine must be started)
- OCI CLI with valid session for integration tests
- Authenticated `gh` CLI for integration tests
- `oci_scaffold` submodule for integration tests
