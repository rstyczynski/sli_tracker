# Sprint 19 Implementation — SLI-27 + SLI-28 + SLI-29 Source Router

## Files Created

- `tools/json_router.js` — routing-definition loader, route matcher, and transformer dispatcher
- `tools/json_router_cli.js` — CLI wrapper for single-envelope and batch routing
- `tools/schemas/json_router_definition.schema.json` — JSON Schema for `routing.json`
- `tests/unit/test_json_router.sh` — unit suite for routing behavior
- `tests/unit/test_json_router_batch.sh` — unit suite for batch routing behavior
- `tests/unit/test_json_router_schema.sh` — unit suite dedicated to `routing.json` schema validation
- `tests/unit/test_json_router_cli.sh` — unit suite for router CLI behavior
- `tests/unit/test_json_pipeline_cli.sh` — unit suite for transform-CLI to router-CLI piping
- `tests/fixtures/router/ut57_*` through `ut80_*` — routing fixtures covering positive and negative routing cases
- `tests/fixtures/router_batch/ut65_*` through `ut84_*` — batch routing fixtures covering happy paths, dead letters, fanout delivery, and schema-validation failures

## Design Decisions

- The router consumes a normalized envelope with `body` plus optional `headers`, `endpoint`, and `source_meta`.
- Route eligibility is declarative and defined in JSON, not hard-coded in application logic.
- Route delivery mode is declarative and defined per route:
  - `exclusive` selects one winning route among matching exclusive candidates
  - `fanout` selects every matching fanout route
- Route definition structure is validated up front with AJV before any path resolution or matching occurs.
- Route selection uses these explicit signals:
  - header match
  - endpoint match
  - schema marker match
  - required payload fields
  - priority
- Mapping execution is delegated to the existing `tools/json_transformer.js`.
- The router preserves backward compatibility for single-route callers via `routeTransform()` and exposes `routeTransformAll()` for explicit multi-route delivery.
- Public router functions now normalize the router argument so callers can pass a routing file path, a raw routing object, or a preloaded definition variable.
- Raw routing objects are accepted directly when their mapping paths are already absolute; otherwise callers should normalize them first with `loadRoutingDefinitionFromObject(..., { baseDir })`.
- A separate CLI wrapper `tools/json_router_cli.js` provides one-envelope and batch-routing use cases, so operators can validate routing definitions and outputs without writing Node glue code.

## Matching Semantics

- Header names are normalized to lower case before comparison.
- `required_fields` checks payload shape without requiring transform-time `$assert(...)`.
- If no route matches, routing fails explicitly.
- If multiple exclusive routes match at the top priority, routing fails explicitly as ambiguous.
- Matching fanout routes are accumulated and transformed in the same pass.
- Batch routing writes one output file per selected route, so one source file may land in multiple destination trees.
- Schema-invalid routing definitions fail immediately at load time with schema-path-specific errors.

## Test Scope Reached

- Source identification by HTTP header
- Source identification by endpoint path
- Source identification by payload schema marker
- Source identification by required-field signature
- Priority-based route resolution
- Fanout routing to multiple destinations
- Mixed exclusive + fanout routing for one message
- No-match failure
- Ambiguous-match failure
- Invalid route mode rejected at definition load
- Invalid dead-letter schema rejected at definition load
- Downstream strict mapping failure after successful routing
- End-to-end CLI-to-CLI piping from transform output into router input

## Regression Adjustment

`tests/unit/test_install_oci_cli.sh` now self-skips when Podman is unavailable or unreachable. This preserves regression signal for code changes while avoiding false failures from local container-runtime state.
