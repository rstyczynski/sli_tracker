# Sprint 28 — Design (SLI-47)

## Problem

Regression gates mix unrelated components. No mechanism to say "run only router tests".
Test scripts inherit the caller's CWD so state/temp files appear in project root.

## Design decisions

### 1. Component manifest files — `tests/manifests/component_<name>.manifest`

Same `suite:script` format as existing manifests. Five components:
- `router` — 14 unit + 7 integration scripts (exact match of current sprint regression)
- `emit` — 1 unit + 5 integration scripts
- `oci-setup` — 5 unit + 2 integration scripts
- `sli-metrics` — 3 unit + 3 integration scripts
- `install` — 1 unit script

### 2. `--component NAME` flag in `tests/run.sh`

Resolves to `tests/manifests/component_NAME.manifest`. Multiple `--component` flags are
additive (union into MANIFEST_SCRIPTS). Combinable with `--manifest`. Incompatible with
`--new-only` (both would set MANIFEST_FILE — `--new-only` wins; `--component` errors if
`--new-only` is also specified). Error with non-zero exit if manifest file not found.

Implementation: replace single `MANIFEST_SPEC` string with `MANIFEST_FILES` array; load
all files into one `MANIFEST_SCRIPTS` associative array.

### 3. Working directory enforcement

`run_suite` invokes each script in a subshell with CWD set to `tests/`:
```bash
(cd "$SCRIPT_DIR" && bash "$script") >"$log_file" 2>&1
```
Exports `TESTS_DIR="$SCRIPT_DIR"` for scripts that want the canonical tests path.
Existing scripts compute REPO_ROOT from BASH_SOURCE and are unaffected by the CWD change.

### 4. `Regression scope:` in `rup_manager_simplified.md`

Three targeted edits (lines 14, 111, 189) to document the optional field and Phase B command.

## Test specification

### UT-SLI47-1 — `--component router` runs exactly the 14 router scripts

`bash tests/run.sh --unit --component router` output must list `[run]` or `[skip]` for
unit scripts only from the router component and no others.

### UT-SLI47-2 — `--component nonexistent` exits non-zero with clear error

Exit code must be non-zero; stderr must contain the component name and "not found".

### UT-SLI47-3 — `--component` and `--manifest` combine (union)

Combining `--component install` with `--manifest` pointing to a single extra script runs
both the install component scripts and the extra script.

### UT-SLI47-4 — scripts run with `tests/` as CWD

After a run, no `state-*.json` or other temp files appear in REPO_ROOT. (Structural check:
TESTS_DIR is exported; CWD inside each test script is `tests/`.)
