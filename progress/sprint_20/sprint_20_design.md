# Sprint 20 Design — SLI-30 + SLI-31 + SLI-32 JavaScript Adapter API

## Components

### `tools/json_router.js`

New public API additions:

```text
processEnvelope(envelope, definition, handlers)   -> { status, deliveries?, error? }
processEnvelopes(envelopes, definition, handlers) -> { processed, routed, dead_lettered, results }
```

### `tools/adapters/file_adapter.js`

Example concrete target adapter:

```text
createFileAdapter({ rootDir, deadLetterDir? }) -> { onRoute, onDeadLetter, getState }
```

- writes routed outputs into destination-derived directories
- writes dead-letter payloads into a dead-letter directory
- uses deterministic incrementing file names for testability

### `tools/adapters/file_source_adapter.js`

Example concrete source adapter:

```text
createFileSourceAdapter({ sourceDir, extension? }) -> { readEnvelopes, getState }
```

- reads JSON files from a source directory in lexical order
- exposes envelopes as an async iterable for `processEnvelopes(...)`
- stops with a critical error on malformed JSON

### Handler contract

Handlers are plain async JavaScript functions:

```js
{
  onRoute: async ({ route, output, envelope }) => {},
  onDeadLetter: async ({ error, envelope }) => {}
}
```

- `onRoute` is called once per selected route.
- `onDeadLetter` is called when routing or transformation fails for an envelope.
- Both handlers are optional.

### Processing semantics

- `processEnvelope(...)`
  - routes and transforms one envelope
  - invokes `onRoute` for each selected route
  - if processing fails and `onDeadLetter` exists, invokes it and returns a dead-letter result instead of throwing
  - if processing fails and no `onDeadLetter` exists, throws

- `processEnvelopes(...)`
  - accepts an array, iterable, or async iterable of envelopes
  - processes them sequentially
  - returns aggregate counters and per-envelope results
  - delegates success and dead-letter behavior to the same handler contract

### Design constraints

- No framework or plugin loader is introduced.
- No queue SDK or OCI SDK integration is introduced here.
- The filesystem adapter remains available for compatibility, but it is not the core abstraction.

## Testing Strategy

**Scope:** unit only.

**Test categories:**

1. **Single-envelope adapter success**
   - one selected route calls `onRoute`
   - multiple selected routes call `onRoute` multiple times

2. **Dead-letter adapter behavior**
   - no-match invokes `onDeadLetter`
   - transform failure invokes `onDeadLetter`
   - if no dead-letter handler exists, error is thrown

3. **Batch adapter behavior**
   - array input is processed with aggregate summary
   - async iterable input is processed with aggregate summary
   - mixed outcomes count routed and dead-lettered envelopes correctly

4. **Concrete target adapter behavior**
   - file adapter writes routed outputs into destination paths
   - file adapter writes dead-letter payloads into dead-letter path
   - file adapter works with mixed batch results

5. **Concrete source adapter behavior**
   - file source adapter reads JSON files in lexical order
   - file source adapter can feed `processEnvelopes(...)`
   - file source adapter stops with a clear error on malformed JSON

## Test Specification

### Unit tests — UT-97 through UT-108

| ID     | Suite | Script                         | Function / scenario |
|--------|-------|--------------------------------|---------------------|
| UT-97  | unit  | test_json_router_adapters.sh   | `processEnvelope()` calls `onRoute` for fanout deliveries |
| UT-98  | unit  | test_json_router_adapters.sh   | `processEnvelope()` routes mixed exclusive + fanout deliveries to `onRoute` |
| UT-99  | unit  | test_json_router_adapters.sh   | `processEnvelope()` sends no-match to `onDeadLetter` |
| UT-100 | unit  | test_json_router_adapters.sh   | `processEnvelope()` sends transform failure to `onDeadLetter` |
| UT-101 | unit  | test_json_router_adapters.sh   | `processEnvelopes()` processes array input with mixed routed and dead-letter results |
| UT-102 | unit  | test_json_router_adapters.sh   | `processEnvelopes()` processes async iterable input |
| UT-103 | unit  | test_file_adapter.sh           | file adapter writes fanout deliveries into destination paths |
| UT-104 | unit  | test_file_adapter.sh           | file adapter writes dead-letter payload into dead-letter path |
| UT-105 | unit  | test_file_adapter.sh           | file adapter handles mixed batch results |
| UT-106 | unit  | test_file_source_adapter.sh    | file source adapter reads JSON files in lexical order |
| UT-107 | unit  | test_file_source_adapter.sh    | file source adapter feeds `processEnvelopes()` with mixed batch input |
| UT-108 | unit  | test_file_source_adapter.sh    | file source adapter stops on malformed source JSON |

### Test-level boundaries

- `test_json_router_adapters.sh` is a unit suite for the new JavaScript adapter API.
- `test_file_adapter.sh` is a unit suite for the example concrete filesystem target adapter.
- `test_file_source_adapter.sh` is a unit suite for the example concrete filesystem source adapter.
- It validates handler injection and in-memory processing only.
- The example adapter remains local-only and does not cover live queue, HTTP, or OCI adapters, which remain future work.
