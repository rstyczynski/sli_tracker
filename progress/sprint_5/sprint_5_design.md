# Sprint 5 — Design

## SLI-8 — Test procedure execution log and OCI log capture

Status: Accepted

### Requirement Summary

Add two auto-created artifacts to `test_sli_integration.sh`:
1. Full execution log (timestamped `.log` file)
2. Raw OCI Logging JSON response (timestamped `.json` file)

### Feasibility Analysis

**API Availability:** No new APIs. Uses `exec` bash built-in + `tee`.
**Technical Constraints:** `exec > >(tee)` requires bash (not sh). Script already uses `#!/usr/bin/env bash`.
**Risk Assessment:**
- Low: `tee` available everywhere.
- Low: process substitution `>( )` is bash-only — already required.

### Design Overview

**Architecture:** Single script modification. No new files except the output artifacts.

**Key Components:**

1. **Execution log setup** — immediately after `REPO_ROOT` and `SCRIPT_DIR` are defined:
   ```bash
   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
   TS="$(date -u '+%Y%m%d_%H%M%S')"
   LOG_FILE="${SCRIPT_DIR}/test_run_${TS}.log"
   OCI_LOG_FILE="${SCRIPT_DIR}/oci_logs_${TS}.json"
   exec > >(tee -a "$LOG_FILE") 2>&1
   echo "# Execution log: $LOG_FILE"
   ```

2. **OCI log capture** — immediately after `EVENTS=$(oci logging-search ...)`:
   ```bash
   printf '%s\n' "$EVENTS" > "$OCI_LOG_FILE"
   echo "# OCI log captured: $OCI_LOG_FILE"
   ```

3. **End-of-run summary** — before the final `exit`:
   ```bash
   echo "# Artifacts:"
   echo "#   execution log : $LOG_FILE"
   echo "#   OCI log       : $OCI_LOG_FILE"
   ```

**Data Flow:** `stdout/stderr → tee → console + LOG_FILE`. OCI JSON → `OCI_LOG_FILE`.

### Technical Specification

**Scripts/Tools:**

| File | Purpose |
|------|---------|
| `progress/sprint_5/test_sli_integration.sh` | New sprint 5 test script (extends sprint 4) |
| `progress/sprint_5/test_run_<ts>.log` | Generated per run — execution log |
| `progress/sprint_5/oci_logs_<ts>.json` | Generated per run — OCI raw log |

**Error Handling:** If OCI query returns empty `$EVENTS`, the JSON file is written as empty string — existing assertions will catch and report FAIL.

### Implementation Approach

1. Copy `progress/sprint_4/test_sli_integration.sh` to `progress/sprint_5/`
2. Update header comment to reference Sprint 5 / SLI-8
3. Add `SCRIPT_DIR`, `TS`, `LOG_FILE`, `OCI_LOG_FILE` variables after `REPO_ROOT`
4. Add `exec > >(tee -a "$LOG_FILE") 2>&1` + header echo
5. Add OCI JSON write after `EVENTS=...` block
6. Add artifact summary before final echo/exit
7. Add `*.log` and `oci_logs_*.json` to `.gitignore` (or leave untracked — YOLO decision below)

### Testing Strategy

**Functional Tests:**
1. Run script; verify `test_run_*.log` exists in `progress/sprint_5/`
2. Run script; verify `oci_logs_*.json` exists and contains `.data.results` key
3. Verify execution log contains all test section headers (T0, T1, ..., T7, Summary)
4. Verify paths printed at end of run

**Success Criteria:** Both files created, log non-empty, JSON valid.

### YOLO Mode Decisions

#### Decision 1: `.gitignore` for generated artifacts
**Context:** Should `test_run_*.log` and `oci_logs_*.json` be gitignored?
**Decision Made:** Not gitignored — committed as proof-of-execution evidence.
**Rationale:** Sprint tests doc already embeds manual results; auto-generated files serve same purpose.
**Risk:** Low — files are small; if unwanted, easy to add to `.gitignore` later.

#### Decision 2: `printf '%s\n'` vs `echo` for OCI JSON
**Context:** `echo` can mangle content with `-e` flag on some systems.
**Decision Made:** Use `printf '%s\n' "$EVENTS"` — safe on all platforms.
**Risk:** Low.

#### Decision 3: `SCRIPT_DIR` derivation
**Context:** Script may be invoked from any working directory.
**Decision Made:** Use `BASH_SOURCE[0]` which resolves to script location regardless of invocation path.
**Risk:** Low — consistent with bash best practices.
