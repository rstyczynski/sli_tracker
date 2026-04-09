# Sprint 18 Tests — SLI-26 JSON Transformer

## Gate A2 — Unit (new tests only)

Result at sprint closeout: **PASS** — 2 scripts, 48 checks passed, 0 failed.

Result after requirements reconciliation: **PASS** — 2 scripts, 54 checks passed, 0 failed.

Coverage now includes:

- baseline transformer behavior and mapping-file validation
- real-world GitHub webhook, `/health`, and OCI event transformation fixtures
- graceful degradation for permissive mappings with missing optional source fields
- strict required-field validation through JSONata `$assert($exists(...), "...")`
- CLI propagation of transform-time assertion failures

### Artifacts

- `progress/sprint_18/test_run_A2_unit_20260409_074646.log` — first attempt (CLI test failed, mktemp fix applied)
- `progress/sprint_18/test_run_A2_unit_20260409_074725.log` — passing run
- `progress/sprint_18/test_run_A2_unit_20260409_082812.log` — passing run after strict required-field validation cases were added

## Gate B2 — Regression

`Regression: none` — this is an independent new module; no existing tests depend on it.
