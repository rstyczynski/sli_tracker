# Sprint 28 — Implementation (SLI-47)

**`PLAN.md`:** **`Test: unit`** · **`Regression: unit`** · **`Regression scope: router`**.

## Status: DONE

## Summary

Sprint 28 tracks **SLI-47**: component-scoped test manifests and working-directory enforcement.
The deliverable is a polished **`rup_manager_simplified.md`** that fully documents the new
testing protocol, backed by infrastructure that makes it possible: component manifest files,
a `--component` flag in `tests/run.sh`, and CWD enforcement so tests never leave artefacts
in the project root.

---

## Work packages

### WP-1 — Component manifest files (`tests/manifests/`)

Created five stable, per-domain manifest files. These replace the hand-crafted per-sprint
`regression_tests.manifest` files for Phase B regression.

| Manifest | Scripts |
| -------- | ------- |
| `component_router.manifest` | 14 unit + 7 integration (json_transformer, json_router, adapters, Fn passthrough) |
| `component_emit.manifest` | 1 unit + 5 integration |
| `component_oci_setup.manifest` | 5 unit + 2 integration |
| `component_sli_metrics.manifest` | 3 unit + 3 integration |
| `component_install.manifest` | 1 unit |

### WP-2 — `--component NAME` flag in `tests/run.sh`

- Replaced single `MANIFEST_SPEC` string with `MANIFEST_FILES=()` array — supports multiple manifests in one run.
- Added `COMPONENT_NAMES=()` array; `--component NAME` resolves to `tests/manifests/component_NAME.manifest` and errors with a clear message if the file is absent.
- Multiple `--component` flags are additive (union). `--manifest` and `--component` combine. `--new-only` and `--component` are mutually exclusive (exits non-zero with "incompatible" message).

### WP-3 — Working-directory enforcement

Every test script is now invoked inside a subshell with CWD set to `tests/`:

```bash
(cd "$SCRIPT_DIR" && bash "$script") >"$log_file" 2>&1
```

`TESTS_DIR="$SCRIPT_DIR"` is exported for scripts that need the canonical tests path.
Existing scripts compute `REPO_ROOT` from `BASH_SOURCE` and are unaffected.

### WP-4 — `rup_manager_simplified.md` documentation (primary deliverable)

Three edits made across two sprints; Sprint 28 adds two more targeted updates:

| Location | Change |
| -------- | ------ |
| Step 0 line 14 | Added `Regression scope:` to field extraction list |
| Phase 2 step 3 | Added component manifest registry table (5 components) + extension rule |
| Phase 4 Phase B | Expanded: concrete `--component` command, union/combination rules, `--new-only` exclusion |
| Phase 4 Phase B (Sprint 27) | "Full suite unless `Regression scope:` set" clause |
| Sprint header template | Added `Regression scope: [component or omit]` optional field |

### WP-5 — PLAN.md and backlog

- Sprint 27 retroactively got `Regression scope: router` (the 14-script manifest is exactly the router component).
- Sprint 28 entry created with `Mode: YOLO`, `Test: unit`, `Regression: unit`, `Regression scope: router`.
- `BACKLOG.md` SLI-47 item added.

### WP-6 — Unit test (`test_run_sh_component.sh`)

Eight assertions covering all new behaviour (see `sprint_28_design.md ## Test Specification`).
All 8 pass.
