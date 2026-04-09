# Sprint 19 Design — SLI-27 Source Router

## Components

### `tools/json_router.js`

Public API (CommonJS):

```text
loadRoutingDefinition(filePath)        -> routing definition with resolved mapping paths
loadRoutingDefinitionFromObject(obj)   -> validated routing definition object
selectRoute(envelope, definition)      -> matched route
routeTransform(envelope, definition)   -> { route, output }
```

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
    }
  ]
}
```

### Matching rules

- Header names are matched case-insensitively.
- `endpoint` must match exactly when present in a route.
- `schema` is an optional payload marker expressed as `{ path, equals }`.
- `required_fields` is an array of payload paths that must exist in `body`.
- A route matches only when all declared match criteria pass.
- If no routes match, routing fails.
- If multiple routes match:
  - highest `priority` wins
  - if multiple matches share top priority, routing fails as ambiguous

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

5. **Priority and ambiguity**
   - Higher-priority route wins.
   - Same-priority multi-match fails.

6. **Failure handling**
   - No route matched.
   - Invalid routing definition.
   - Route matched but transform fails.

## Test Specification

### Unit tests — UT-57 through UT-64

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
