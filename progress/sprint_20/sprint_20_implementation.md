# Sprint 20 Implementation — SLI-30 + SLI-31 + SLI-32 JavaScript Adapter API

## Files Created

- `tools/adapters/file_adapter.js` — example filesystem target adapter for handler-based processing
- `tools/adapters/file_source_adapter.js` — example filesystem source adapter for handler-based processing
- `tests/unit/test_json_router_adapters.sh` — unit suite for handler-based router processing
- `tests/unit/test_file_adapter.sh` — unit suite for the concrete filesystem target adapter
- `tests/unit/test_file_source_adapter.sh` — unit suite for the concrete filesystem source adapter

## Files Updated

- `tools/json_router.js` — added handler-based processing APIs:
  - `processEnvelope(...)`
  - `processEnvelopes(...)`
- `progress/sprint_20/new_tests.manifest` — Sprint 20 unit gate manifest

## Design Decisions

- The new adapter boundary uses plain async JavaScript functions rather than a framework.
- The router core remains responsible for:
  - loading definitions
  - selecting routes
  - transforming envelopes
- External code is now responsible for delivery by injecting handlers:
  - `onRoute`
  - `onDeadLetter`
- `tools/adapters/file_adapter.js` is the first concrete example of such a target adapter.
- `tools/adapters/file_source_adapter.js` is the first concrete example of a source-side adapter that feeds the same processing API.
- The existing filesystem adapter (`routeDirectory`) is preserved for compatibility and remains separate from the new in-memory handler model.

## Processing Semantics

- `processEnvelope(...)`
  - routes one envelope
  - calls `onRoute` once per selected route
  - on failure:
    - calls `onDeadLetter` if provided and returns a dead-letter result
    - otherwise rethrows the error

- `processEnvelopes(...)`
  - accepts arrays, iterables, and async iterables
  - processes envelopes sequentially
  - returns counters plus per-envelope results

## Test Scope Reached

- Fanout delivery through injected route handlers
- Mixed exclusive + fanout delivery through injected route handlers
- No-match dead-letter callback path
- Transform-failure dead-letter callback path
- Batch processing over array input
- Batch processing over async iterable input
- Example filesystem adapter writing routed outputs
- Example filesystem adapter writing dead-letter payloads
- Example filesystem source adapter reading envelopes from a directory in deterministic order
- Example filesystem source adapter failing clearly on malformed JSON
- Example filesystem source adapter feeding `processEnvelopes(...)` directly
