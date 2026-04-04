# Sprint 4 — Analysis

Status: Complete

## Sprint Overview

Replace hardcoded OCI resource OCIDs in the Sprint 3 integration test script with values resolved at runtime from the GitHub repo variable `SLI_OCI_LOG_ID` and derived OCI CLI queries.

## Backlog Items Analysis

### SLI-5 — Improve workflow tests

**Requirement Summary:**

`progress/sprint_3/test_sli_integration.sh` contains three hardcoded OCIDs:

- `SLI_LOG_OCID` — the custom log OCID
- `LOG_GROUP_OCID` — the log group OCID
- `TENANCY` — the tenancy OCID

These must be replaced with runtime-resolved values so the script works without modification after OCI resource recreation.

**Technical Approach:**

- `SLI_LOG_OCID`: read from `gh variable get SLI_OCI_LOG_ID -R <repo> --json value -q .value`
- `LOG_GROUP_OCID`: derived from `oci logging log get --log-id $SLI_LOG_OCID` which returns the log group OCID in the response
- `TENANCY`: derived from `oci iam compartment list --include-root` filtering for the root entry (parent-compartment-id is null)

All three values can be resolved with existing tools (gh + oci CLI) already required as prerequisites.

**Dependencies:**

- Existing `SLI_OCI_LOG_ID` repo variable (set in Sprint 3)
- OCI CLI with DEFAULT profile (already a prerequisite)
- gh CLI (already a prerequisite)

**Testing Strategy:**

- Run the updated script; assert it resolves OCIDs without hardcoded values
- Verify T7 OCI Logging query still works correctly

**Acceptance Criteria:**

- No hardcoded OCIDs remain in the script
- Script resolves all three OCIDs dynamically at startup
- Script exits with clear error if `SLI_OCI_LOG_ID` variable is not set
- All 41 existing integration assertions continue to pass

**Compatibility Notes:**

`test_sli_integration.sh` is a Sprint 3 artifact; this change is a targeted improvement, not a replacement. The file will be updated in-place.

## YOLO Mode Decisions

### Assumption 1: File to modify

**Issue:** The backlog says "improve workflow tests" broadly; the specific file is not named.
**Assumption Made:** Target is `progress/sprint_3/test_sli_integration.sh` — the only integration test script.
**Risk:** Low — no other integration test files exist.

## Overall Sprint Assessment

**Feasibility:** High — straightforward variable substitution using existing CLI tools.
**Estimated Complexity:** Simple
**Prerequisites Met:** Yes
**Open Questions:** None

## Readiness for Design Phase

Confirmed Ready
