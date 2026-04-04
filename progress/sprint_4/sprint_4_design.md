# Sprint 4 — Design

## SLI-5 — Improve workflow tests

Status: Accepted

### Requirement Summary

Remove three hardcoded OCIDs from `progress/sprint_3/test_sli_integration.sh` by integrating `oci_scaffold` techniques and using URI-style resource identification.

### Feasibility Analysis

**API Availability:**

All resolution methods verified working:

- `gh variable get SLI_OCI_LOG_URI` — URI (`log_group_name/log_name`) from repo variable
- `oci os ns get-metadata` — tenancy OCID via object-storage namespace metadata (`_oci_tenancy_ocid()` technique from `oci_scaffold`)
- `oci logging log-group list --display-name` — log group OCID by name (`ensure-log_group.sh` pattern)
- `oci logging log list --display-name` — log OCID by name (`ensure-log.sh` pattern)

**Technical Constraints:**

- OCI CLI must be authenticated with DEFAULT profile (already a prerequisite)
- `gh` must be authenticated (already a prerequisite)
- Three OCI API calls at startup (~2–3 s), no iteration needed

**Risk Assessment:**

- Low: all tools already required by existing script
- Low: `SLI_OCI_LOG_URI` names (`sli-events/github-actions`) are stable display names

### Design Overview

Integration: https://github.com/rstyczynski/oci_scaffold (vendored in `lib/oci_scaffold.sh`)

New repo variable: `SLI_OCI_LOG_URI` = `log_group_name/log_name` (URI-style, e.g. `sli-events/github-actions`)

**Startup Block (replaces 3 hardcoded OCID lines):**

```bash
# URI-style resolution using oci_scaffold techniques
SLI_OCI_LOG_URI=$(gh variable get SLI_OCI_LOG_URI -R "$REPO" --json value -q .value)
LOG_GROUP_NAME="${SLI_OCI_LOG_URI%%/*}"
LOG_NAME="${SLI_OCI_LOG_URI#*/}"

# _oci_tenancy_ocid() technique from oci_scaffold
TENANCY=$(oci os ns get-metadata \
  --query 'data."default-s3-compartment-id"' --raw-output --profile DEFAULT)

# ensure-log_group.sh technique: lookup by compartment + display-name
LOG_GROUP_OCID=$(oci logging log-group list \
  --compartment-id "$TENANCY" --display-name "$LOG_GROUP_NAME" \
  --query 'data[0].id' --raw-output --profile DEFAULT)

# ensure-log.sh technique: lookup by log-group + display-name
SLI_LOG_OCID=$(oci logging log list \
  --log-group-id "$LOG_GROUP_OCID" --display-name "$LOG_NAME" \
  --query 'data[0].id' --raw-output --profile DEFAULT)
```

### Testing Strategy

**Functional Tests:**

1. T0: tooling prerequisites present
2. T_resolve: URI parsed and all three OCIDs resolved (well-formed `ocid1.*`)
3. T_no_hardcoded: zero `ocid1.*` literals in script source
4. T_error_no_var: fail-fast when `SLI_OCI_LOG_URI` unset

**Success Criteria:**

- No `ocid1.*` literals in script source
- Script exits with clear error when `SLI_OCI_LOG_URI` variable is unset

### YOLO Mode Decisions

**Decision 1: Use URI variable `SLI_OCI_LOG_URI` over existing `SLI_OCI_LOG_ID`**

- Context: `SLI_OCI_LOG_ID` holds an OCID; oci_scaffold favors name-based URI
- Decision: add `SLI_OCI_LOG_URI = sli-events/github-actions` as new repo variable
- Rationale: display names survive recreation; only one variable needed for both log group and log
- Risk: Low — `SLI_OCI_LOG_ID` is kept for emit.sh backward compatibility

**Decision 2: Inline oci_scaffold techniques rather than source full library**

- Context: sourcing `oci_scaffold.sh` creates `state.json` in CWD (by design for full scaffold use)
- Decision: vendor `lib/oci_scaffold.sh` for reference; inline just the three API calls in test script
- Rationale: test script needs only discovery, not the full idempotent resource management
- Risk: Low — techniques are stable single OCI CLI calls
