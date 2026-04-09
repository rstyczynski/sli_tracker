# Sprint 20 Setup — SLI-30 + SLI-31 + SLI-32 JavaScript Adapter API

## Contract

Rules understood: YOLO mode, unit tests only for new code, no separate regression gate for this sprint.

**Responsibilities:**
- Expose the router as a transport-agnostic JavaScript processing API.
- Keep routing and transformation logic separate from IO concerns.
- Support injected async handlers for routed outputs and dead-letter cases.
- Add one concrete example filesystem target adapter built on the handler API.
- Add one concrete example filesystem source adapter that exposes envelopes as an async iterable.
- Preserve the existing file/dir adapters and CLI behavior.

**Constraints:**
- No framework or container-based adapter system.
- No live queue, HTTP, or OCI integration in this sprint.
- New APIs must stay lightweight and idiomatic for plain Node.js usage.
- Filesystem-based routing remains one adapter, not the core processing model.

**Open questions:** None critical. The in-sprint scope is library-level adapter hooks, not production queue drivers.

## Analysis

Backlog items SLI-30, SLI-31, and SLI-32 extend the router from file-oriented orchestration to handler-oriented orchestration plus concrete example adapters on both target and source sides. The current router core already knows how to select routes and transform envelopes; what is missing is a stable callback boundary for external JavaScript code plus small modules showing how ingestion and delivery adapters should be structured.

**Feasible design direction:**
- Add one-envelope processing with injected handlers.
- Add batch processing over sync/async iterables of envelopes.
- Return processing summaries while also invoking injected callbacks.
- Keep `routeDirectory()` as a filesystem adapter built on top of the same routing core.
- Add `tools/adapters/file_adapter.js` as a deterministic example target adapter.
- Add `tools/adapters/file_source_adapter.js` as a deterministic example source adapter.

**Compatibility:**
- Reuses the existing routing definition loader and transformation logic.
- Does not require changes to JSONata mappings or routing.json schema.
- Fits unit-only sprint scope and can be validated with in-memory fixtures.

**Testability:**
- Unit tests can inject arrays and async callbacks and assert collected results.
- Dead-letter behavior can be verified without touching the filesystem.
- Source ingestion order and malformed JSON behavior can be verified offline with fixture directories.
- Existing router tests remain the compatibility safety net.

**Open questions:** None. The problem is well-bounded for a single sprint.
