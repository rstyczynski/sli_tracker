# Sprint 15 — Bugs

Sprint: 15 | Mode: YOLO | Backlog: SLI-22, SLI-23

## Bugs

### BUG-15-1 — Scheduled workflows fail at `oci-profile-setup` (`oci not found in PATH`)

- **Symptom**: `SLI-23 — scheduled synthetic emitter (hourly)` fails immediately with `oci not found in PATH`.
- **Impact**: both SLI-22 and SLI-23 cannot restore `SLI_TEST` token-based profile, so scheduled execution is broken.
- **Root cause**: workflows invoked `./.github/actions/oci-profile-setup` without first running `./.github/actions/install-oci-cli` (a documented prerequisite).
- **Fix**: add `Install OCI CLI` step before `oci-profile-setup` in both workflows.
- **Resolution**: fixed on `main` in commit `652fe5f`.
- **Traceability**: SLI-22, SLI-23

### BUG-15-2 — Local emitter log push skipped due to wrong env var name (`OCI_LOG_ID` vs `SLI_OCI_LOG_ID`)

- **Symptom**: emitter prints `SLI log push skipped — OCI_LOG_ID not set` even though the user exported `OCI_LOG_ID`.
- **Impact**: local/manual runs push metrics but skip log ingestion unexpectedly.
- **Root cause**: emitter backend reads log OCID from `SLI_OCI_LOG_ID` (or `SLI_CONTEXT_JSON`), not from `OCI_LOG_ID`.
- **Fix**: update operator usage to export `SLI_OCI_LOG_ID` and avoid the misleading `OCI_LOG_ID` variable.
- **Resolution**: documented in `README.md` in commit `e76819d`.
- **Traceability**: SLI-23 (operator verification)

