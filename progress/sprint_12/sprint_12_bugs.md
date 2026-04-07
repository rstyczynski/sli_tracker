# Sprint 12 — Bugs

Sprint: 12 | Mode: YOLO | Backlog: SLI-17

## SLI-17: OCI Monitoring metric output

### Bug: Local runs failed with HTTP 400 from OCI Monitoring

**Symptom:** Running `emit.sh` locally (outside GitHub Actions) with `EMIT_TARGET=metric` or `EMIT_TARGET=log,metric`
returned HTTP 400 from OCI Monitoring:

- `InvalidParameter ... dimensions.value cannot be empty or null`
- after filtering empty values: `InvalidParameter ... dimensions can not be null or empty`

**Root cause:** In a local shell, the GitHub Actions environment variables are not set, so `workflow.*` and `repo.*`
fields are empty. The metric payload was emitting dimensions with empty strings (invalid) and after filtering, an empty
dimensions object (also invalid).

**Fix:** In `sli_emit_metric()` (in `emit_common.sh`), drop dimensions whose values are empty and ensure `dimensions` is
never empty by falling back to `{"emit_env":"local"}`.

**Verification:** Re-ran locally with verbose response logging and observed successful metric ingestion:
`EMIT_BACKEND=curl EMIT_TARGET=metric SLI_EMIT_CURL_VERBOSE=1 ... bash .github/actions/sli-event/emit.sh`
→ `::notice::SLI metric pushed to OCI Monitoring (namespace: sli_tracker, outcome: success, value: 1)`.

