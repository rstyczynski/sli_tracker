# Sprint 7 - Analysis

Status: Complete

## Sprint Overview

Bootstrap the centralized test infrastructure defined in `agent_qualitygate.md`. This is the first sprint using the patched RUP process with Phase 3.1 (Test Specification) and Phase 4.1 (Test Execution).

## Backlog Items Analysis

### SLI-10. Implement test-first quality gates

**Requirement Summary:**

Four deliverables:

1. **Centralized test runner** (`tests/run.sh`): Already exists as a skeleton from the previous conversation. Needs enhancement to support `--new-only <manifest>` at script level (function-level filtering is future work). Must discover and execute `test_*.sh` scripts in subdirectories, return nonzero on any failure.

2. **Test migration**: Move four existing test files to centralized tree:
   - `.github/actions/sli-event/tests/test_emit.sh` → `tests/unit/test_emit.sh`
   - `.github/actions/install-oci-cli/tests/test_install_oci_cli.sh` → `tests/unit/test_install_oci_cli.sh`
   - `.github/actions/oci-profile-setup/tests/test_oci_profile_setup.sh` → `tests/unit/test_oci_profile_setup.sh`
   - `progress/sprint_6/test_sli_integration.sh` → `tests/integration/test_sli_integration.sh`
   - Replace originals with one-line wrappers.

3. **Initial smoke tests**: At least one smoke test in `tests/smoke/` covering the most critical path (emit.sh valid JSON).

4. **Validation**: `tests/run.sh --all` passes; `tests/run.sh --smoke` passes.

**Technical Approach:**

- The `tests/run.sh` skeleton already handles `--smoke`, `--unit`, `--integration`, `--all`. The `--new-only` flag needs proper manifest filtering (script-level).
- Test migration requires adjusting source paths (`SCRIPT_DIR`, `ACTION_DIR`) in copied scripts since they reference relative paths to their parent action directories.
- Wrapper scripts use `exec` to delegate to the new location.
- Smoke test: create `tests/smoke/test_critical_emit.sh` that sources `emit.sh` and verifies basic JSON output from key functions.

**Dependencies:**

- Existing test infrastructure from Sprints 1-6
- `jq` for JSON manipulation (already available)
- `oci_scaffold` submodule (for integration tests)
- `podman` (for install-oci-cli tests)

**Testing Strategy:**

- **Smoke**: Verify emit.sh produces valid JSON (fast, no infrastructure)
- **Unit**: Run all migrated unit tests from new locations
- **Integration**: Run migrated integration test from new location
- Regression: none (this is the migration sprint, no prior tests in `tests/`)

**Risks/Concerns:**

- **Path resolution in migrated scripts**: Unit tests use `SCRIPT_DIR` and relative paths to find their action's source files. After migration to `tests/unit/`, these paths must be adjusted.
- **Integration test infrastructure**: Requires live OCI tenancy and GitHub access. May fail if infrastructure is unavailable.
- **Podman dependency**: `test_install_oci_cli.sh` requires podman. If podman is not available, this test will fail.

**Compatibility Notes:**

- Wrapper scripts at old locations preserve backward compatibility for CI or other scripts referencing old paths.
- `tests/run.sh` already exists and is functional for basic suite running.

## Overall Sprint Assessment

**Feasibility:** High — all components are straightforward file operations and path adjustments.

**Estimated Complexity:** Moderate — path resolution in migrated tests needs careful handling.

**Prerequisites Met:** Yes — existing tests work at current locations.

**Open Questions:** None.

## Recommended Design Focus Areas

1. Path resolution strategy for migrated unit tests (they source action code via relative paths)
2. Manifest-based filtering in `run.sh`
3. Smoke test selection criteria

## Readiness for Design Phase

Confirmed Ready
