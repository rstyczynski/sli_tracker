# Sprint 20 Tests — SLI-30 + SLI-31 + SLI-32 JavaScript Adapter API

## Gate A2 — Unit (new tests only)

Result: **PASS** — 3 scripts, 12 checks passed, 0 failed.

Coverage:

- `processEnvelope(...)` route-handler callbacks for fanout deliveries
- `processEnvelope(...)` route-handler callbacks for mixed exclusive + fanout deliveries
- `processEnvelope(...)` dead-letter callback for no-match
- `processEnvelope(...)` dead-letter callback for transform failure
- `processEnvelopes(...)` mixed array processing with routed and dead-letter outcomes
- `processEnvelopes(...)` async iterable processing
- example file adapter writing routed outputs
- example file adapter writing dead-letter payloads
- example file adapter handling mixed batch results
- example file source adapter reading files in deterministic order
- example file source adapter feeding `processEnvelopes(...)`
- example file source adapter stopping on malformed JSON

Scope clarification:

- Sprint 20 has **unit coverage only**.
- The tests validate handler injection plus one example filesystem source adapter and one example filesystem target adapter.
- No live queue, HTTP, or OCI adapter integration is included in this sprint.

## Gaps

- Missing integration gate for real queue or HTTP adapter wiring.
- Missing concrete OCI Logging / Monitoring adapter modules.
- No separate regression gate is defined for this sprint.

## Artifacts

- `progress/sprint_20/test_run_A2_unit_20260409_171500.log`
- `progress/sprint_20/test_run_A2_unit_20260409_184500.log`
- `progress/sprint_20/test_run_A2_unit_20260409_192430.log`

## Notes

- The current Sprint 20 suite on disk contains 12 checks:
  - `tests/unit/test_json_router_adapters.sh` → 6 checks
  - `tests/unit/test_file_adapter.sh` → 3 checks
  - `tests/unit/test_file_source_adapter.sh` → 3 checks
