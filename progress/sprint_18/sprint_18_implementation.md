# Sprint 18 Implementation — SLI-26 JSON Transformer

## Files Created

- `tools/json_transformer.js` — library: `loadMapping`, `loadMappingFromObject`, `transform`
- `tools/json_transform_cli.js` — CLI wrapper
- `tools/mappings/github_workflow_run_to_oci_log.jsonata` — example mapping
- `tools/mappings/health_to_oci_metric.jsonata` — example mapping

## Dependency Added

`jsonata` added to `package.json` dependencies via `npm install jsonata`.

## Design Decisions

- `loadMappingFromObject` is separate from `loadMapping` so tests can pass inline objects without touching the filesystem.
- `transform` is `async` because JSONata v2+ `evaluate()` returns a Promise.
- CLI reads stdin when `--input` is omitted; writes result to stdout; all errors go to stderr with exit 1.
- Unknown CLI flags cause exit 1 (no silent ignore).
- The engine deliberately stays neutral about required fields; strictness belongs in the mapping via JSONata constructs such as `$exists(...)` and `$assert(...)`.
- Missing-source handling therefore supports both permissive mappings that degrade gracefully and strict mappings that fail fast with explicit messages.

## Mapping File Format

Two formats are supported:

- `.jsonata` files containing a raw JSONata expression
- `.json` files containing `{ "version": "1", "description"?: "...", "expression": "..." }`

```json
{
  "version": "1",
  "description": "Human-readable description (optional)",
  "expression": "<JSONata expression>"
}
```

The `expression` is evaluated with the source document as root context (`$`). Standard JSONata path and function library is available.

## Test Scope Reached

- Library and CLI unit coverage now includes baseline expression handling, malformed mapping/input cases, real-world GitHub and OCI payload mappings, graceful degradation for optional data, and strict required-field validation using `$assert(...)`.
