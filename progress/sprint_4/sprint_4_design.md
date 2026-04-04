# Sprint 4 — Design

## SLI-5 — Improve workflow tests

Status: Accepted

### Requirement Summary

Remove three hardcoded OCIDs from `progress/sprint_3/test_sli_integration.sh`; resolve all three dynamically at script startup.

### Feasibility Analysis

**API Availability:**

All derivation methods verified working:

- `gh variable get` — resolves `SLI_OCI_LOG_ID` from repo variable
- `awk` on `~/.oci/config` — extracts tenancy OCID without any API call
- `oci logging log-group list` + `oci logging log list` — finds the log group containing our log

**Technical Constraints:**

- OCI CLI must be authenticated with DEFAULT profile (already a prerequisite)
- `gh` must be authenticated (already a prerequisite)
- Iteration over log groups adds ~1–2 seconds to startup

**Risk Assessment:**

- Low: all tools already required by existing script
- Low: tenancy OCID derivation is a pure local file read (no network)
- Low: log group iteration is bounded (current tenancy has 4 log groups)

### Design Overview

**Startup Block (replaces 3 hardcoded lines):**

```bash
# Resolve OCIDs dynamically — no hardcoded values
SLI_LOG_OCID=$(gh variable get SLI_OCI_LOG_ID -R "$REPO" --json value -q .value 2>/dev/null)
[[ -z "$SLI_LOG_OCID" ]] && { echo "ERROR: SLI_OCI_LOG_ID repo variable not set"; false; }

TENANCY=$(awk -F'=' '/^\[DEFAULT\]/{f=1} f && /^tenancy/{gsub(/ /,"",$2); print $2; f=0}' ~/.oci/config)
[[ -z "$TENANCY" ]] && { echo "ERROR: tenancy not found in ~/.oci/config [DEFAULT]"; false; }

LOG_GROUP_OCID=""
for _lg in $(oci logging log-group list --compartment-id "$TENANCY" --profile DEFAULT 2>/dev/null | jq -r '.data[] | .id'); do
  _found=$(oci logging log list --log-group-id "$_lg" --profile DEFAULT 2>/dev/null | jq -r --arg id "$SLI_LOG_OCID" '.data[] | select(.id == $id) | .id')
  if [[ -n "$_found" ]]; then
    LOG_GROUP_OCID="$_lg"
    break
  fi
done
[[ -z "$LOG_GROUP_OCID" ]] && { echo "ERROR: log group containing $SLI_LOG_OCID not found in tenancy"; false; }
```

### Testing Strategy

**Functional Tests:**

1. T0-prereqs: script still reports prereqs present
2. T_resolve: all three OCIDs resolved (non-empty, well-formed `ocid1.*`)
3. T7 full: OCI search query uses resolved values and returns events

**Success Criteria:**

- No `ocid1.*` literals in script source (grep check)
- Script exits with error message when `SLI_OCI_LOG_ID` variable is unset

### YOLO Mode Decisions

**Decision 1: Derive LOG_GROUP_OCID via OCI CLI iteration (not a new repo variable)**

- Context: LOG_GROUP_OCID must be eliminated; options are (a) new repo variable or (b) derive at runtime
- Decision: derive via `log-group list` + `log list` iteration — no new repo variable needed
- Rationale: operator sets only `SLI_OCI_LOG_ID`; script is self-contained
- Risk: Low — bounded iteration, ~1s overhead
