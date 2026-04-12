# Sprint 28 — Setup (SLI-47)

## Status: DONE

## Sprint parameters

| Field | Value |
|-------|-------|
| Sprint | 28 |
| Mode | YOLO |
| Test | unit |
| Regression | unit |
| Regression scope | router |
| Backlog item | SLI-47 |

## Problem statement

Regression gates run the full test suite regardless of sprint scope, mixing unrelated
components (router, emit, OCI setup, install). No mechanism exists to say "run only
router regression". Additionally, tests run from an arbitrary working directory, leaving
state files and temp artifacts in the project root.

## Artefacts from previous work

- `tests/run.sh` — supports `--manifest` and `--new-only`; no `--component` flag
- `rup_manager_simplified.md` — defines `Regression:` level but not component scope
- 14-script regression manifest in sprint 25–27 = exactly the `router` component

## Goals

1. `tests/manifests/component_<name>.manifest` — stable per-component manifest files
2. `tests/run.sh --component <name>` — new flag resolving to the manifest above
3. `Regression scope:` field in PLAN.md sprint entries, documented in `rup_manager_simplified.md`
4. All tests invoked with `tests/` as working directory via `TESTS_DIR` env or runner `cd`

## References

- `PLAN.md` Sprint 28
- `BACKLOG.md` SLI-47
- `rup_manager_simplified.md` lines 14, 111, 189
