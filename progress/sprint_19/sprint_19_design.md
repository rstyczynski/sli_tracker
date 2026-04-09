# Sprint 19 Design — SLI-27 + SLI-28 + SLI-29 Source Router

## Components

### `tools/json_router.js`

Public API (CommonJS):

```text
loadRoutingDefinition(filePath)        -> routing definition with resolved mapping paths
loadRoutingDefinitionFromObject(obj)   -> validated routing definition object
normalizeRoutingDefinition(router)     -> accepts path string or routing object
selectRoutes(envelope, definition)     -> matched route list
selectRoute(envelope, definition)      -> matched route when exactly one route is selected
routeTransformAll(envelope, definition)-> { routes: [{ id, mode, destination, output }] }
routeTransform(envelope, definition)   -> { route, output }
```

All router functions that take a routing definition accept the router argument as:
- a file path string
- a raw `routing.json` object
- a preloaded normalized routing definition object

For raw routing objects passed directly, relative `transform.mapping` paths are not meaningful unless the caller has already resolved them. Callers should either:
- provide absolute mapping paths in the object variable, or
- pre-normalize the object with `loadRoutingDefinitionFromObject(obj, { baseDir })`

### CLI

`tools/json_router_cli.js` exposes the router CLI:

```text
node tools/json_router_cli.js --routing <routing.json> --input <envelope.json> [--pretty]
node tools/json_router_cli.js --routing <routing.json> --source-dir <dir> --output-dir <dir> [--pretty]
cat envelope.json | node tools/json_router_cli.js --routing <routing.json>
```

- single mode prints the `routeTransformAll()` JSON result
- single mode can read from stdin when `--input` is omitted
- batch mode writes routed outputs to the destination tree and prints a processing summary
- malformed `routing.json`, bad input JSON, and invalid argument combinations fail with exit code `1`

### Routing definition schema

- `routing.json` is validated by the router library before use.
- Validation is implemented with `ajv` against a checked-in JSON Schema.
- Schema validation covers:
  - top-level `routes`
  - route object shape
  - `mode` enum
  - `match` structure
  - `transform.mapping`
  - destination and `dead_letter` structure
- Semantic checks that are simpler outside JSON Schema remain in code:
  - duplicate route IDs

### Envelope format

The router accepts a normalized envelope:

```json
{
  "headers": { "X-GitHub-Event": "workflow_run" },
  "endpoint": "/webhooks/github",
  "source_meta": { "transport": "http" },
  "body": { "...": "payload" }
}
```

Only `body` is required. `headers`, `endpoint`, and `source_meta` are optional.

### Routing definition format

```json
{
  "routes": [
    {
      "id": "github_workflow_run_to_oci_log",
      "mode": "exclusive",
      "priority": 100,
      "match": {
        "headers": { "X-GitHub-Event": "workflow_run" },
        "endpoint": "/webhooks/github",
        "schema": { "path": "schema", "equals": "github.workflow_run" },
        "required_fields": [
          "workflow_run.conclusion",
          "repository.full_name"
        ]
      },
      "transform": {
        "mapping": "./mapping.jsonata"
      },
      "destination": {
        "type": "oci_log",
        "name": "default"
      }
    },
    {
      "id": "github_workflow_run_to_oci_metric",
      "mode": "fanout",
      "match": {
        "headers": { "X-GitHub-Event": "workflow_run" }
      },
      "transform": {
        "mapping": "./metric_mapping.jsonata"
      },
      "destination": {
        "type": "oci_metric",
        "name": "workflow_status"
      }
    }
  ]
}
```

### Matching rules

- Header names are matched case-insensitively.
- `endpoint` must match exactly when present in a route.
- `schema` is an optional payload marker expressed as `{ path, equals }`.
- `required_fields` is an array of payload paths that must exist in `body`.
- `mode` controls delivery semantics:
  - `exclusive` means at most one matching exclusive route may be selected
  - `fanout` means every matching fanout route is selected
- A route matches only when all declared match criteria pass.
- If no routes match, routing fails.
- Matching exclusive routes are resolved by priority:
  - highest `priority` wins
  - if multiple exclusive matches share top priority, routing fails as ambiguous
- Matching fanout routes are accumulated.
- A final selection may therefore contain:
  - one exclusive route
  - zero or more fanout routes
- `routeTransform()` remains a single-route helper and fails if multiple routes are selected.

### Output contract

`routeTransform()` returns:

```json
{
  "route": {
    "id": "github_workflow_run_to_oci_log",
    "destination": { "type": "oci_log", "name": "default" }
  },
  "output": { "... transformed JSON ..." }
}
```

`routeTransformAll()` returns:

```json
{
  "routes": [
    {
      "id": "github_workflow_run_to_oci_log",
      "mode": "exclusive",
      "destination": { "type": "oci_log", "name": "default" },
      "output": { "... transformed JSON ..." }
    },
    {
      "id": "github_workflow_run_to_oci_metric",
      "mode": "fanout",
      "destination": { "type": "oci_metric", "name": "workflow_status" },
      "output": { "... transformed JSON ..." }
    }
  ]
}
```

## Testing Strategy

**Scope:** unit only.

**Test categories:**

1. **Header-based routing**
   - Header identifies GitHub event type.

2. **Endpoint-based routing**
   - Known receiver endpoint selects a route.

3. **Schema-based routing**
   - Payload marker field selects a route.

4. **Required-field-based routing**
   - Route selected from payload signature when transport metadata is absent.

5. **Priority, mode, and ambiguity**
   - Higher-priority exclusive route wins.
   - Same-priority exclusive multi-match fails.
   - Matching fanout routes all execute.
   - Exclusive winner and fanout routes may coexist for one message.

6. **Failure handling**
   - No route matched.
   - Invalid routing definition.
   - Route matched but transform fails.
   - Invalid routing schema fails before routing starts.

## Test Specification

### Unit tests — UT-57 through UT-96

| ID    | Suite | Script                       | Function / scenario                              |
|-------|-------|------------------------------|--------------------------------------------------|
| UT-57 | unit  | test_json_router.sh          | header-based route selection                     |
| UT-58 | unit  | test_json_router.sh          | endpoint-based route selection                   |
| UT-59 | unit  | test_json_router.sh          | schema-based route selection                     |
| UT-60 | unit  | test_json_router.sh          | required-fields route selection                  |
| UT-61 | unit  | test_json_router.sh          | highest-priority route wins                      |
| UT-62 | unit  | test_json_router.sh          | no route matched → error                         |
| UT-63 | unit  | test_json_router.sh          | ambiguous top-priority routes → error            |
| UT-64 | unit  | test_json_router.sh          | route matched but strict mapping fails → error   |
| UT-65 | unit  | test_json_router_batch.sh    | consolidated bulk happy-path batch covers header, endpoint, schema, required-fields, and priority routing |
| UT-66 | unit  | test_json_router_batch.sh    | bulk routing reports unroutable file by name     |
| UT-67 | unit  | test_json_router_batch.sh    | consolidated bulk dead-letter batch covers unknown route, transform failure, and invalid JSON |
| UT-72 | unit  | test_json_router_batch.sh    | bulk ambiguous top-priority routes fail with filename |
| UT-74 | unit  | test_json_router_batch.sh    | invalid routing definition fails before processing |
| UT-75 | unit  | test_json_router.sh          | invalid schema matcher rejected at definition load |
| UT-76 | unit  | test_json_router.sh          | non-object body does not crash and reports no route |
| UT-77 | unit  | test_json_router_batch.sh    | one omnibus batch covers happy paths and dead letters together |
| UT-78 | unit  | test_json_router.sh          | fanout routes produce multiple outputs             |
| UT-79 | unit  | test_json_router.sh          | exclusive winner and fanout route both selected    |
| UT-80 | unit  | test_json_router.sh          | invalid route mode rejected at definition load     |
| UT-81 | unit  | test_json_router_batch.sh    | one source file fans out to multiple destinations  |
| UT-82 | unit  | test_json_router_batch.sh    | one source file resolves only the winning exclusive destination |
| UT-83 | unit  | test_json_router_batch.sh    | mixed batch covers multi-destination, single-destination, and dead-letter outcomes |
| UT-84 | unit  | test_json_router_batch.sh    | invalid dead-letter schema fails before processing |
| UT-85 | unit  | test_json_router_schema.sh   | `routing.json` schema accepts a valid routing definition |
| UT-86 | unit  | test_json_router_schema.sh   | `routing.json` schema rejects an invalid route definition before router use |
| UT-87 | unit  | test_json_router_schema.sh   | `routing.json` schema rejects an invalid dead-letter definition before router use |
| UT-88 | unit  | test_json_router_cli.sh      | router CLI routes one envelope and prints JSON result |
| UT-89 | unit  | test_json_router_cli.sh      | router CLI batch mode writes expected destinations and prints processing summary |
| UT-90 | unit  | test_json_router_cli.sh      | router CLI rejects missing `--routing` |
| UT-91 | unit  | test_json_router_cli.sh      | router CLI rejects incomplete batch arguments |
| UT-92 | unit  | test_json_router_cli.sh      | router CLI rejects incomplete batch arguments |
| UT-93 | unit  | test_json_router_cli.sh      | router CLI rejects malformed envelope JSON |
| UT-94 | unit  | test_json_pipeline_cli.sh    | `json_transform_cli.js` output pipes into `json_router_cli.js` successfully |
| UT-95 | unit  | test_json_pipeline_cli.sh    | stdin into `json_transform_cli.js` pipes into `json_router_cli.js` successfully |
| UT-96 | unit  | test_json_pipeline_cli.sh    | transform CLI failure stops the CLI pipeline before routing |

### Test-level boundaries

- `test_json_router.sh`, `test_json_router_batch.sh`, `test_json_router_schema.sh`, `test_json_router_cli.sh`, and `test_json_pipeline_cli.sh` are unit suites.
- The batch fixture model simulates queue-like input and destination trees, but it still exercises the router library directly rather than a production integration runner.
- `test_json_router_schema.sh` exists specifically to validate the `routing.json` document contract with no envelope-routing behavior mixed in.
- `test_json_pipeline_cli.sh` exists specifically to exercise the shipped CLI executables together rather than only their underlying libraries.
- Integration and regression definitions for a future router runtime should be specified separately once that runtime exists.
