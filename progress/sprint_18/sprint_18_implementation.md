# Sprint 18 Implementation — SLI-26 JSON Transformer

## Files Created

- `tools/json_transformer.js` — library: `loadMapping`, `loadMappingFromObject`, `transform`
- `tools/json_transform_cli.js` — CLI wrapper
- `tools/mappings/github_workflow_run_to_oci_log.json` — example mapping
- `tools/mappings/health_to_oci_metric.json` — example mapping

## Dependency Added

`jsonata` added to `package.json` dependencies via `npm install jsonata`.

## Design Decisions

- `loadMappingFromObject` is separate from `loadMapping` so tests can pass inline objects without touching the filesystem.
- `transform` is `async` because JSONata v2+ `evaluate()` returns a Promise.
- CLI reads stdin when `--input` is omitted; writes result to stdout; all errors go to stderr with exit 1.
- Unknown CLI flags cause exit 1 (no silent ignore).

## Mapping File Format

```json
{
  "version": "1",
  "description": "Human-readable description (optional)",
  "expression": "<JSONata expression>"
}
```

The `expression` is evaluated with the source document as root context (`$`). Standard JSONata path and function library is available.
