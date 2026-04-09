# Sprint 19 Tests — SLI-27 + SLI-28 + SLI-29 Source Router

## Gate A2 — Unit (new tests only)

Result: **PASS** — 5 scripts, 36 checks passed, 0 failed.

Coverage:

- single-envelope routing:
  - header-based route selection
  - endpoint-based route selection
  - schema-based route selection
  - required-fields route selection
  - priority resolution
  - fanout route selection
  - mixed exclusive + fanout selection
  - no-match failure
  - ambiguous-match failure
  - transform-time strict-mapping failure after routing
  - invalid schema matcher rejected at definition load
  - invalid route mode rejected at definition load
  - non-object body handled without crash
- dedicated `routing.json` schema validation:
  - valid routing definition accepted
  - invalid route definition rejected critically before router use
  - invalid dead-letter definition rejected critically before router use
- router CLI:
  - single-envelope routing prints JSON result
  - single-envelope routing can read from stdin
  - batch routing writes destination tree and prints summary
  - invalid arguments fail fast
  - malformed envelope JSON fails fast
- CLI-to-CLI pipeline:
  - transform CLI output can be piped directly into router CLI
  - stdin through transform CLI can continue into router CLI
  - transform-time failure stops the CLI pipeline before routing
- batch routing:
  - consolidated happy-path batch covering header, endpoint, schema, required-fields, and priority matching
  - dedicated batch fanout delivery to multiple destinations from one source file
  - dedicated batch exclusive-only winner selection
  - dedicated mixed batch covering multi-destination, single-destination, and dead-letter outcomes
  - fail-fast no-match with source filename in error
  - dead-letter batch covering unknown route, transform failure, and invalid JSON input
  - omnibus batch covering happy paths and dead letters together
  - ambiguous top-priority batch failure with source filename
  - invalid routing definition failure before processing
  - invalid dead-letter schema failure before processing
  - all routing definitions are schema-validated by AJV before router use

Scope clarification:

- Sprint 19 currently has **unit coverage only** for the router.
- The batch tests are still unit tests because they call the router library directly against fixture directories.
- This sprint does **not** yet include a separate end-to-end integration suite around a production runner/CLI entrypoint for routing.

## Gaps

- Missing integration gate for the router flow:
  - queue/source directory
  - routing definition document
  - destination directories
  - real runner entrypoint instead of direct library invocation
- No separate regression gate is defined for this sprint.

## Artifacts and Current Evidence

- `progress/sprint_19/test_run_A2_unit_20260409_133900.log` — latest recorded A2 run before CLI-to-CLI pipeline suite
- `progress/sprint_19/test_run_A2_unit_20260409_133457.log` — A2 run after adding dedicated `routing.json` schema-validation suite
- `progress/sprint_19/test_run_A2_unit_20260409_132818.log` — A2 run after AJV-backed routing schema validation inside router suites
- `progress/sprint_19/test_run_A2_unit_20260409_131601.log` — A2 run after explicit exclusive/fanout routing mode support
- `progress/sprint_19/test_run_A2_unit_20260409_100137.log` — original A2 run before later unit expansion

Note:

- The current router unit suite on disk contains 36 checks:
  - `tests/unit/test_json_router.sh` → 13 checks
  - `tests/unit/test_json_router_batch.sh` → 10 checks
  - `tests/unit/test_json_router_schema.sh` → 3 checks
  - `tests/unit/test_json_router_cli.sh` → 7 checks
  - `tests/unit/test_json_pipeline_cli.sh` → 3 checks
- The document above reflects the current suite composition. Record a fresh A2 artifact if you want the log list to include the new CLI-to-CLI pipeline suite explicitly.
