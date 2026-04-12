# Sprint 25 — Setup (YOLO)

## Contract

RUP simplified manager: YOLO mode — self-approve design, no blocking waits.
`Test: unit, integration`. `Regression: unit` (component-scoped manifest).

Deliver SLI-42 then SLI-41 in a single sprint. SLI-42 is a prerequisite that makes
`router_core.js` config-driven; SLI-41 becomes pure configuration once SLI-42 is in place.
Unlike Sprint 24, this sprint **explicitly permits changes to `router_core.js`** and the Fn
build context. Changes to the shared adapter library `tools/adapters/oci_monitoring_adapter.js`
are not permitted; the adapter's `emit` parameter is implemented inside `router_core.js` at
wiring time.

## Analysis

### SLI-42 — Config-driven adapter registration

**Current state (`router_core.js` lines 306–308):**

```js
const dispatcher = createDestinationDispatcher({
    adapters: [bucketAdapter],
    deadLetterDestination: definition.dead_letter,
});
```

Only `oci_object_storage` is supported. Adding `oci_monitoring` requires a code change.

**Required change:** inspect `definition.adapters` keys to derive which adapter types are
needed, then instantiate only those adapters:

```js
const adapterTypes = new Set(Object.keys(definition.adapters).map(k => k.split(':')[0]));
const adapters = [];
if (adapterTypes.has('oci_object_storage')) adapters.push(bucketAdapter);
if (adapterTypes.has('oci_monitoring'))     adapters.push(monitoringAdapter);
const dispatcher = createDestinationDispatcher({ adapters, deadLetterDestination: definition.dead_letter });
```

**Build context:** `fn/router_passthrough/lib/oci_monitoring_adapter.js` must exist (symlink
to `tools/adapters/oci_monitoring_adapter.js`, same pattern as the existing BUG-4 symlinks).

**npm dependency:** `oci-monitoring` must be added to `fn/router_passthrough/package.json`.

**`emit` implementation:** `createOciMonitoringAdapter` receives an `emit` callback. In
`router_core.js`, the callback calls `oci.monitoring.MonitoringClient.postMetricData()` using
Resource Principal auth — the same auth pattern as the existing `putObject` call.

### SLI-41 — Fanout route for workflow_run → OCI Monitoring (pure config)

Once SLI-42 is in place, three configuration changes are sufficient:

1. Add adapter entry `oci_monitoring:github_workflow_run` to `routing.json`.
2. Add fanout route `github_workflow_run_to_metric` (priority 40, matches
   `x-github-event: workflow_run`, destination type `oci_monitoring`).
3. Create `fn/router_passthrough/lib/workflow_run_metric.jsonata` with the mapping defined in
   `progress/sprint_23/workflow_run_metric_mapping.md`.

## Feasibility

Both items are feasible. SLI-42 requires code changes to `router_core.js` and the build
context; SLI-41 requires only configuration and a new JSONata file. No changes to
`tools/adapters/oci_monitoring_adapter.js` or `fn/router_passthrough/lib/json_router.js`.
