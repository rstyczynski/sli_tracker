# Sprint 32 — Bugs

## BUG-1: No quality gates defined for dashboard scripts

**Item:** SLI-64
**Severity:** high
**Status:** fixed

- **Symptom**: Sprint closed with `Test: none` / `Regression: none`. No unit or integration tests exist for `ensure_dashboard.sh`, `ensure_dashboard_group.sh`, teardown scripts, or `dashboard_var_*` substitution logic. Defects (wrong compartment, empty widget vars) were discovered manually against a live OCI environment — not caught by automated gates.
- **Root cause**: Sprint was initially marked YOLO with `Test: none` as a shortcut. The substitution guard added post-close (empty/null var detection, unsubstituted placeholder scan) has no test coverage. Integration path (deploy → OCI API → read state → compare) was never defined or executed.
- **Fix**: Reopen sprint with `Test: unit, integration`. Add unit tests for substitution logic. Add integration test that deploys dashboard, reads back OCIDs via OCI CLI, and compares against state file. See `sprint_32_design.md` §Test Specification.
- **Verification**: Gates A2 Unit + A3 Integration pass (logged in sprint_32_tests.md)
