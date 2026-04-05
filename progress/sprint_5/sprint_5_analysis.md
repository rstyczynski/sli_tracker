# Sprint 5 — Analysis

Status: Complete

## Sprint Overview

Add two durable artifacts to the integration test script:
1. Execution log (timestamped file capturing full test stdout/stderr)
2. OCI raw log capture (JSON from OCI Logging query in T7)

## Backlog Items Analysis

### SLI-8 — Test procedure execution log and OCI log capture

**Requirement Summary:**

- Every test run auto-creates a timestamped execution log (`test_run_<ts>.log`) — proof of execution.
- The raw OCI Logging JSON response from T7 is saved to a timestamped file (`oci_logs_<ts>.json`) — proof of work.
- Paths of both files printed at end of run.

**Technical Approach:**

- `exec > >(tee -a "$LOG_FILE") 2>&1` at top of script — all subsequent output goes to console + log file.
- After `EVENTS=$(oci logging-search ...)`, write `printf '%s\n' "$EVENTS" > "$OCI_LOG_FILE"`.
- Both files stored alongside the script in `progress/sprint_5/`.
- New test script at `progress/sprint_5/test_sli_integration.sh` — sprint_4 script untouched.

**Dependencies:** Sprint 4 test script (copy-and-extend, no modifications to sprint_4).

**Testing Strategy:** Run the script; verify two artifact files appear; check log captures all test output; check OCI JSON has `.data.results`.

**Compatibility Notes:** Bash `exec > >(tee)` is portable across macOS (bash 3.2+) and Linux (bash 4+). `date -u` flags differ by OS — same workaround already present in sprint_4.

## Overall Sprint Assessment

**Feasibility:** High — purely additive bash changes.
**Estimated Complexity:** Simple.
**Prerequisites Met:** Yes.
**Open Questions:** None.

## Recommended Design Focus Areas

- Placement of `exec > >(tee)` (must be after `REPO_ROOT` and artifact path computation)
- Artifact directory must exist before redirect

## Readiness for Design Phase

Confirmed Ready

## YOLO Mode Decisions

### Assumption 1: Artifact storage location
**Issue:** Where to store logs — sprint dir, `/tmp`, or separate `runs/` subdirectory?
**Assumption Made:** Same directory as the script (`progress/sprint_5/`).
**Rationale:** Keeps artifacts with the sprint they belong to; easy git-ignore or commit.
**Risk:** Low — directory always exists when script runs.
