# Sprint 24 — Setup (YOLO)

## Contract

RUP simplified manager: YOLO mode — self-approve design, no blocking waits.
`Test: unit, integration`. `Regression: unit` (component-scoped manifest).

Deliver SLI-41: fan-out `workflow_run` webhooks to OCI Monitoring metric in addition to
the existing Object Storage exclusive route. Constraint: no changes to core library
(`fn/router_passthrough/lib/`) or existing adapters. Implementation must be achievable
through routing configuration (`routing.json`) and a new JSONata mapping only.

## Analysis

**Routing config** (`tests/fixtures/fn_router_passthrough/routing.json`):
- Add `oci_monitoring:github_workflow_run` adapter entry.
- Add fanout route `github_workflow_run_to_metric` matching `x-github-event: workflow_run`,
  referencing mapping `./workflow_run_metric.jsonata`.

**JSONata mapping** (`fn/router_passthrough/workflow_run_metric.jsonata`):
- Filter `action = "completed"` only.
- Emit `workflow_run_result` (1/0) and `workflow_run_duration_s` (seconds).

**Dispatcher** (`fn/router_passthrough/router_core.js` lines 306–308):
```js
const dispatcher = createDestinationDispatcher({
    adapters: [bucketAdapter],          // ← only Object Storage registered
    deadLetterDestination: definition.dead_letter,
});
```
Only one adapter type is registered. To deliver to `oci_monitoring` destinations the
dispatcher must also hold a `createOciMonitoringAdapter` instance. This requires a code
change to `router_core.js`. **Sprint feasibility check: FAIL.**

## Feasibility verdict

**Cannot deliver SLI-41 as pure configuration.** See `sprint_24_implementation.md`.
