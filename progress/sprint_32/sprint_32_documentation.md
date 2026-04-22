# Sprint 32 - Documentation Summary

## Documentation Validation

**Validation Date:** 2026-04-22
**Sprint Status:** implemented

### Documentation Files Reviewed

- [x] sprint_32_setup.md
- [x] sprint_32_design.md
- [x] sprint_32_elaboration.md
- [x] sprint_32_implementation.md
- [x] sprint_32_tests.md

### Compliance Verification

- [x] All sections complete
- [x] Code snippets copy-paste-able (verified working end-to-end)
- [x] No prohibited commands (exit, etc.)
- [x] Prerequisites listed
- [x] Test: none / Regression: none — gates correctly skipped and documented
- [x] Design status: Accepted

### Consistency Check

- [x] Backlog item names consistent across documents
- [x] Status values match PROGRESS_BOARD.md
- [x] File paths correct
- [x] MANUAL.md §7.4 matches implementation
- [x] State key table in MANUAL.md matches script output (`.dashboard_group.*`, `.dashboard.*`)
- [x] Deploy block in MANUAL.md verified working against live OCI environment

### README Update

- [x] README.md updated with Sprint 32 section
- [x] Recent Updates section added

### Backlog Traceability

- `progress/backlog/SLI-64/` — symlinks to all sprint_32 docs
- `progress/backlog/SLI-65/` — symlinks to all sprint_32 docs

### YOLO Mode Decisions

#### Decision 1: Single documentation phase for two tightly coupled items

**Context:** SLI-64 and SLI-65 are implementation + documentation of the same feature.
**Decision Made:** Single sprint, single set of phase documents.
**Rationale:** Items are inseparable; splitting would add ceremony without value.
**Risk:** Low.

### Post-Implementation Bugs Fixed (recorded here for traceability)

#### Bug 1: Dashboard group created in tenancy root

**Symptom:** Dashboard group landed in tenancy root compartment instead of project compartment.
**Root cause:** `ensure_dashboard_group.sh` reads from `.inputs.oci_compartment`; this key was not set in state. Script fell through to OCI default (tenancy).
**Fix:** MANUAL.md deploy block now explicitly sets `.inputs.oci_compartment` from `.compartment.ocid`.
**Commit:** fix(SLI-65): §7.4 fix dashboard deploy — set oci_compartment, read log OCIDs from gh variables

#### Bug 2: Dashboard widgets deployed with empty placeholder values

**Symptom:** All widgets rendered empty; metrics charts missing required parameters.
**Root cause:** `.log_group.ocid` and `.log.ocid` do not exist in the state file — log resources are managed via GitHub Actions repo variables, not via oci_scaffold state. Values substituted as empty strings.
**Fix:** MANUAL.md deploy block reads `SLI_OCI_LOG_ID` and `SLI_OCI_LOG_GROUP_ID` from `gh variable get`; derives region from log OCID via `cut -d. -f4`.
**Commit:** fix(SLI-65): §7.4 fix dashboard deploy — set oci_compartment, read log OCIDs from gh variables

## Status

Documentation phase complete — all documents updated, bugs recorded, end-to-end deploy verified working.
