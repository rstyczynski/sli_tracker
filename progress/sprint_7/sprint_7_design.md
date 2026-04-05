# Sprint 7 - Design

## SLI-10. Implement test-first quality gates

Status: Proposed

### Requirement Summary

Bootstrap the centralized test infrastructure: create a working `tests/run.sh` runner, migrate four existing test scripts to `tests/`, create initial smoke tests, and validate everything passes.

### Feasibility Analysis

**Technical Constraints:**

- Unit tests (`test_emit.sh`, `test_oci_profile_setup.sh`) use `SCRIPT_DIR` to locate action source files via relative paths. After migration, the relative path changes from `tests/../..` to the action directory. Solution: compute `REPO_ROOT` from `SCRIPT_DIR` and derive `ACTION_DIR` from that.
- `test_install_oci_cli.sh` references `INSTALL_SCRIPT` relative to `SCRIPT_DIR`. Same resolution needed.
- `test_sli_integration.sh` already uses `REPO_ROOT` derivation so it needs minimal path changes. Artifact output (log files, OCI captures) should still write to `progress/sprint_N/` based on the run context, not to `tests/integration/`.
- The `--new-only` manifest filter in `run.sh` operates at script level (run entire scripts listed for a suite). Function-level granularity is deferred.

**Risk Assessment:**

- Low: Path adjustments are mechanical and testable.
- Medium: Integration test requires live infrastructure. If OCI/GitHub access is unavailable during validation, integration tests will fail.

### Design Overview

#### Component 1: Enhanced `tests/run.sh`

The runner skeleton already exists. Enhancements needed:

1. **Manifest filtering**: When `--new-only <manifest>` is given, read the manifest file, extract script names per suite, and only run those scripts instead of all `test_*.sh` in the suite directory.
2. **No other changes**: The existing suite discovery, execution, and reporting logic is correct.

Manifest format (one entry per line, comments and blanks ignored):

```
smoke:test_critical_emit.sh
unit:test_emit.sh
integration:test_sli_integration.sh
```

Filtering logic: for each suite being run, if `--new-only` is active, collect the script names from manifest lines starting with that suite prefix. Only run those scripts instead of all `test_*.sh`.

#### Component 2: Migrated unit tests

Three files migrate to `tests/unit/`:

**`tests/unit/test_emit.sh`** (from `.github/actions/sli-event/tests/test_emit.sh`):

- Change path resolution:
  - Old: `ACTION_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"`
  - New: `REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"` then `ACTION_DIR="$REPO_ROOT/.github/actions/sli-event"`
- Everything else unchanged — it sources `emit.sh` and runs assertions.

**`tests/unit/test_install_oci_cli.sh`** (from `.github/actions/install-oci-cli/tests/test_install_oci_cli.sh`):

- Change path resolution:
  - Old: `INSTALL_SCRIPT="$(cd "$SCRIPT_DIR/.." && pwd)/install_oci_cli.sh"`
  - New: `REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"` then `INSTALL_SCRIPT="$REPO_ROOT/.github/actions/install-oci-cli/install_oci_cli.sh"`

**`tests/unit/test_oci_profile_setup.sh`** (from `.github/actions/oci-profile-setup/tests/test_oci_profile_setup.sh`):

- Change path resolution:
  - Old: `ACTION_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"`
  - New: `REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"` then `ACTION_DIR="$REPO_ROOT/.github/actions/oci-profile-setup"`

#### Component 3: Migrated integration test

**`tests/integration/test_sli_integration.sh`** (from `progress/sprint_6/test_sli_integration.sh`):

- Change `REPO_ROOT` derivation:
  - Old: `REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"`
  - New: `REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"`
- Artifact paths (LOG_FILE, OCI_LOG_FILE) currently write to `SCRIPT_DIR` (which was the sprint directory). After migration, `SCRIPT_DIR` is `tests/integration/`. Design choice: keep artifacts in `SCRIPT_DIR` for now — this means test artifacts land in `tests/integration/`. Alternatively, derive a sprint-specific path. For simplicity and because the integration test is a general-purpose regression test (not sprint-specific), writing artifacts to `tests/integration/` is acceptable.

#### Component 4: Wrapper scripts at old locations

Each old test file is replaced with a one-line wrapper:

```bash
#!/usr/bin/env bash
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../tests/unit/test_emit.sh" "$@"
```

The path in each wrapper is adjusted to the correct relative distance from the old location to the new one.

#### Component 5: Smoke test

**`tests/smoke/test_critical_emit.sh`**: Sources `emit.sh` from the sli-event action, exercises the most critical functions, and verifies valid JSON output. Fast (no OCI, no GitHub API, no containers). Covers:

- `sli_build_base_json` produces valid JSON
- `sli_unescape_json_fields` correctly unescapes JSON arrays/objects
- `sli_normalize_json_object` handles edge cases

### Implementation Approach

**Step 1:** Enhance `tests/run.sh` with manifest-based filtering.

**Step 2:** Copy and adapt unit test files to `tests/unit/`.

**Step 3:** Copy and adapt integration test file to `tests/integration/`.

**Step 4:** Replace old test files with wrapper scripts.

**Step 5:** Create smoke test `tests/smoke/test_critical_emit.sh`.

**Step 6:** Validate: `tests/run.sh --smoke`, `tests/run.sh --unit`, and `tests/run.sh --all`.

### Testing Strategy

#### Recommended Sprint Parameters

- Test: smoke, unit, integration (already set in PLAN.md)
- Regression: none (no prior tests in `tests/` tree to regress against)

#### Unit Test Targets

- **Component:** `.github/actions/sli-event/emit.sh`
  - Functions to test: `sli_normalize_json_object`, `sli_expand_oci_config_path`, `sli_merge_flat_context`, `sli_extract_oci_json`, `sli_failure_reasons_from_steps_json`, `sli_merge_failure_reasons`, `sli_unescape_json_fields`, `sli_build_log_entry`, `sli_build_base_json`
  - Key inputs and edge cases: empty strings, null, invalid JSON, nested objects
  - Isolation: pure function tests, no mocks needed

- **Component:** `.github/actions/install-oci-cli/install_oci_cli.sh`
  - Functions to test: full install in Ubuntu container, rejection on Alpine/Fedora, VENV_PATH expansion
  - Isolation: container-based (podman)

- **Component:** `.github/actions/oci-profile-setup/oci_profile_setup.sh`
  - Functions to test: pack/unpack round-trip, token_based wrapper, empty/malformed payload rejection, help text
  - Isolation: temp directories, no real OCI access

#### Integration Test Scenarios

- **Scenario:** Full SLI pipeline — dispatch workflows, wait for completion, verify OCI events
  - Infrastructure: OCI tenancy, GitHub repo access, oci_scaffold submodule
  - Expected outcome: At least 12 OCI events, correct outcomes, native JSON fields
  - Estimated runtime: 10-15 minutes (workflow execution + OCI ingestion delay)

#### Smoke Test Candidates

- **Candidate:** `test_critical_emit.sh` — verify emit.sh produces valid JSON
  - Why critical: If emit.sh can't produce valid JSON, the entire SLI pipeline is broken
  - Expected runtime: <2 seconds

### Integration Notes

**Compatibility:** Wrapper scripts at old locations ensure any CI workflows or scripts referencing the old paths continue to work.

**Reusability:** The `tests/run.sh` framework is reusable for all future sprints.

### Design Decisions

**Decision 1:** Artifacts from integration tests land in `tests/integration/` (not sprint-specific directory).
**Rationale:** Integration test is a general regression test, not sprint-specific. Sprint-specific artifacts were a convenience for manual browsing. The centralized tree owns the tests now.

**Decision 2:** Script-level filtering for `--new-only` (no function-level granularity).
**Rationale:** Function-level filtering requires parsing bash function names and selectively sourcing/running them, which is complex. Script-level is sufficient for the bootstrap sprint. Deferred to future enhancement.

### Open Design Questions

None.
