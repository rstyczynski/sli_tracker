# Sprint 19 Setup — SLI-27 + SLI-28 + SLI-29 Source Router

## Contract

Rules understood: YOLO mode, unit tests only for new code, no separate regression gate for this sprint.

**Responsibilities:**
- Add a routing layer in front of the existing JSON transformer.
- Identify source payload type using transport metadata and payload signals.
- Choose the correct mapping and destination metadata from a routing definition.
- Support explicit delivery modes so a message can route either to one selected destination or to multiple configured destinations.
- Validate `routing.json` against a formal schema before any routing or transformation starts.
- Keep the transformer generic; routing policy belongs in route definitions.

**Constraints:**
- No live HTTP, webhook, or OCI dependencies in this sprint.
- Inputs must be testable offline as JSON fixture envelopes.
- Matching signals must stay explicit: headers, endpoint identity, schema marker, required fields, and priority.
- Ambiguous matches and no-match conditions must fail with clear errors.

**Open questions:** None critical. Hard-coded route logic in application code is rejected in favor of declarative routing definitions.

## Analysis

Backlog items SLI-27, SLI-28, and SLI-29 extend Sprint 18 by adding source identification, dispatch, explicit delivery mode semantics, and formal routing-definition validation, not by changing JSONata transformation semantics.

**Feasible design direction:**
- Introduce `tools/json_router.js`.
- Accept an envelope object containing `body` plus optional `headers`, `endpoint`, and `source_meta`.
- Load a routing definition from JSON.
- Validate the routing definition structure before using it.
- Evaluate route matches using explicit declarative criteria.
- Resolve matching routes according to declared delivery mode.
- Load the selected route mappings and call the existing transformer.

**Compatibility:**
- Reuses `tools/json_transformer.js`.
- Keeps mapping strictness in JSONata mappings (`$assert`) and keeps eligibility checks in route definitions.
- Fits unit-only sprint scope.

**Testability:**
- Each router case can be represented as fixture files:
  - `envelope.json`
  - `routing.json`
  - `mapping.jsonata`
  - `expected.json` or `expected_error.txt`
  - batch fixtures may use `source/` and `expected_destinations/` to verify multi-destination routing

**Open questions:** None. The problem is well-bounded for a single sprint.
