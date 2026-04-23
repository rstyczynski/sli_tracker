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

## BUG-3: ensure_dashboard.sh Path D not idempotent — creates duplicate dashboards

**Item:** SLI-64
**Severity:** high
**Status:** fixed

- **Symptom**: Running `bash tools/ensure_dashboard.sh` from a state file that has no `.inputs.dashboard_name` creates a new dashboard on every run, producing duplicates with the same display name inside the group.
- **Root cause**: Path D (name_prefix fallback) generates `{name_prefix}-dashboard` but, like the group script's Path C before BUG-2, falls straight through to creation without performing a lookup.
- **Fix**: Added a lookup step after Path D name assignment in `tools/ensure_dashboard.sh` — mirrors the same fix applied to `ensure_dashboard_group.sh` in BUG-2. The MANUAL.md §7.4 deploy block already sets `.inputs.dashboard_name` (added during BUG-2 fix), so Path C fires on re-runs regardless.
- **Verification**: Re-running the deploy block prints `[EXISTING] Dashboard:` instead of `[DONE] Dashboard created:`; no duplicate dashboards appear.

## BUG-4: ensure_dashboard.sh updates widgets on adopted dashboards

**Item:** SLI-64
**Severity:** high
**Status:** fixed

- **Symptom**: `bash tools/ensure_dashboard.sh` on an already-existing dashboard prints `[EXISTING] Dashboard: ...` followed by `[DONE] Dashboard widgets deployed: ...` — it overwrites widgets on a dashboard it does not own.
- **Root cause**: The `else` branch (adopted path, `created=false`) ran `update-dashboard-v1` whenever a tiles file was present. Adoption is not ownership — the `created` flag in state is the authority; only dashboards we created should have their widgets managed.
- **Fix**: Removed the widget update block from the adopted (`else`) branch. Adopted dashboards now record `deployed=false` and exit cleanly without touching OCI. Widget deployment only happens during creation.
- **Verification**: Re-running `ensure_dashboard.sh` against an existing dashboard prints `[EXISTING] Dashboard: ...` only, with no `[DONE]` update line. `.dashboard.deployed` is `false`.
