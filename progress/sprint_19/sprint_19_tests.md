# Sprint 19 Tests — SLI-27 Source Router

## Gate A2 — Unit (new tests only)

Result: **PASS** — 1 script, 8 checks passed, 0 failed.

Coverage:

- header-based route selection
- endpoint-based route selection
- schema-based route selection
- required-fields route selection
- priority resolution
- no-match failure
- ambiguous-match failure
- transform-time strict-mapping failure after routing

## Gate B2 — Regression Unit

Result: **PASS** — 13 scripts, 13 passed, 0 failed.

Notes:

- `test_install_oci_cli.sh` self-skips when Podman is not available; in this environment it reported `[SKIP] Podman is installed but not reachable.` and exited successfully.

## Artifacts

- `progress/sprint_19/test_run_A2_unit_20260409_100137.log`
- `progress/sprint_19/test_run_B2_unit_20260409_100137.log` — first regression attempt failed due local Podman availability
- `progress/sprint_19/test_run_B2_unit_20260409_100236.log` — passing regression run after environment guard adjustment
