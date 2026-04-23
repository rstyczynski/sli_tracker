# Sprint 32 — Bugs

## BUG-1: No quality gates defined for dashboard scripts

**Item:** SLI-64
**Severity:** high
**Status:** fixed

- **Symptom**: Sprint closed with `Test: none` / `Regression: none`. No unit or integration tests exist for `ensure_dashboard.sh`, `ensure_dashboard_group.sh`, teardown scripts, or `dashboard_var_*` substitution logic. Defects (wrong compartment, empty widget vars) were discovered manually against a live OCI environment — not caught by automated gates.
- **Root cause**: Sprint was initially marked YOLO with `Test: none` as a shortcut. The substitution guard added post-close (empty/null var detection, unsubstituted placeholder scan) has no test coverage. Integration path (deploy → OCI API → read state → compare) was never defined or executed.
- **Fix**: Reopen sprint with `Test: unit, integration`. Add unit tests for substitution logic. Add integration test that deploys dashboard, reads back OCIDs via OCI CLI, and compares against state file. See `sprint_32_design.md` §Test Specification.
- **Verification**: Gates A2 Unit + A3 Integration pass (logged in sprint_32_tests.md)

## BUG-2: ensure_dashboard_group.sh Path C not idempotent — creates duplicate groups

**Item:** SLI-64
**Severity:** high
**Status:** fixed

- **Symptom**: Running `bash tools/ensure_dashboard_group.sh` more than once (or from a fresh state file) creates a new dashboard group each time, resulting in multiple groups with the same display name in the compartment.
- **Root cause**: Path C (name_prefix fallback) generates the group name (`{name_prefix}-group`) but never performs a lookup — it falls straight through to creation. Additionally, the MANUAL.md §7.4 deploy block did not set `.inputs.dashboard_group_name`, so Path B (which does do a lookup) was never reached.
- **Fix**: Added a lookup step at the end of Path C in `tools/ensure_dashboard_group.sh` so an existing group is adopted before attempting creation. Added `_state_set '.inputs.dashboard_group_name'` and `_state_set '.inputs.dashboard_name'` to the MANUAL.md §7.4 deploy block so Path B fires on subsequent runs.
- **Verification**: Re-running the deploy block against OCI prints `[EXISTING] Dashboard group:` instead of `[DONE] Dashboard group created:`; no duplicate groups appear.
