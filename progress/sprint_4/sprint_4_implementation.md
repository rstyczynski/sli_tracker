# Sprint 4 — Implementation Notes

## Implementation Overview

**Sprint Status:** implemented

**Backlog Items:**

- SLI-5: tested

## SLI-5 — Improve workflow tests

Status: tested

### Implementation Summary

Replaced the three hardcoded OCID constants at lines 21–23 of `progress/sprint_3/test_sli_integration.sh` with a dynamic resolution block. No other changes were made to the script.

### Main Features

- `oci_scaffold` vendored in `lib/oci_scaffold.sh` (source: https://github.com/rstyczynski/oci_scaffold)
- New repo variable `SLI_OCI_LOG_URI` = `sli-events/github-actions` (URI-style: log_group_name/log_name)
- `TENANCY` via `_oci_tenancy_ocid()` technique: `oci os ns get-metadata --query 'data."default-s3-compartment-id"'`
- `LOG_GROUP_OCID` via `ensure-log_group.sh` pattern: `oci logging log-group list --display-name`
- `SLI_LOG_OCID` via `ensure-log.sh` pattern: `oci logging log list --display-name`
- Fail-fast with descriptive error messages if any resolution fails

### Design Compliance

Implementation follows the design in `sprint_4_design.md` exactly.

### Code Artifacts

| Artifact | Purpose | Status | Tested |
|----------|---------|--------|--------|
| `progress/sprint_4/test_sli_integration.sh` | New Sprint 4 integration test | New | Yes |
| `oci_scaffold/` | Git submodule from github.com/rstyczynski/oci_scaffold | New | Yes |
| `.gitignore` | Excludes oci_scaffold state files (`state*.json`) | New | Yes |

### Testing Results

**Functional Tests:** 7 / 7
**Overall:** PASS

### Known Issues

None.

### User Documentation

#### Overview

The integration test script no longer requires any hardcoded OCI resource OCIDs. After OCI resource recreation, the operator only needs to update the `SLI_OCI_LOG_ID` GitHub repo variable; the script resolves all other OCIDs automatically.

#### Prerequisites

- `gh` — GitHub CLI, authenticated
- `oci` — OCI CLI with `DEFAULT` profile (for log group discovery and log search)
- `jq` — JSON processor
- `SLI_OCI_LOG_ID` GitHub repo variable set to the custom log OCID

#### Usage

**Run Sprint 4 integration tests (URI-style, no hardcoded OCIDs):**

```bash
cd /path/to/SLI_tracker
bash progress/sprint_4/test_sli_integration.sh
```

Expected startup output (first lines):

```
=== T0: repo tooling prerequisites ===
PASS: gh CLI present
PASS: OCI CLI present
PASS: jq present
```

**Update OCI log/log-group display names after resource recreation:**

```bash
# Set URI: log_group_display_name/log_display_name
gh variable set SLI_OCI_LOG_URI --body "sli-events/github-actions" -R rstyczynski/sli_tracker
```

The script resolves all OCIDs at runtime from these names — no OCIDs to update.

**Error if repo variable not set:**

```
ERROR: SLI_OCI_LOG_ID repo variable not set (gh variable set SLI_OCI_LOG_ID --body <ocid>)
```

#### Special Notes

- Tenancy OCID derivation reads `~/.oci/config` locally (no network).
- Log group discovery iterates all log groups in the tenancy (bounded, ~1–2 s).
- Script still requires a valid OCI CLI session for log group discovery and the T7 OCI Logging query.

---

## Sprint Implementation Summary

### Overall Status

implemented

### Achievements

- Zero hardcoded OCIDs in integration test script
- Script is resilient to OCI resource recreation
- Operator workflow simplified: update one repo variable, re-run tests

### Challenges Encountered

- Initial approach iterated log groups to find container of log OCID; replaced with oci_scaffold URI-style name-based lookup (display-name) which is simpler and more direct
- `oci_scaffold.sh` creates `state.json` in CWD when sourced; resolved by inlining just the three API calls from the scaffold and vendoring the library for reference

### Integration Verification

- `test_sli_integration.sh` still requires Sprint 3 infrastructure (repo variable, secret, model workflows)
- No changes to any other Sprint 3 artifacts

### Documentation Completeness

- Implementation docs: Complete
- Test docs: Complete
- User docs: Complete

### Ready for Production

Yes
