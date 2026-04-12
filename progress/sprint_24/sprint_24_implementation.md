# Sprint 24 — Implementation (SLI-41) — STOPPED

## Status: FAIL — core adapter layer change required

Sprint stopped per constraint: *"Do not change core library or adapter; when such change is
needed stop the sprint with failure."*

---

## Why the sprint cannot proceed as configuration-only

### Blocker 1 — `router_core.js` dispatcher hardcodes a single adapter

`fn/router_passthrough/router_core.js` lines 306–308:

```js
const dispatcher = createDestinationDispatcher({
    adapters: [bucketAdapter],
    deadLetterDestination: definition.dead_letter,
});
```

`createDestinationDispatcher` is constructed with exactly one adapter: the OCI Object Storage
adapter (`bucketAdapter`). When `processEnvelope` emits a route result whose destination type
is `oci_monitoring`, the dispatcher iterates its `adapters` array, finds no adapter that
`.supports({ type: 'oci_monitoring' })`, and either throws or dead-letters the event.

**Required change:** instantiate `createOciMonitoringAdapter` (from
`fn/router_passthrough/lib/oci_monitoring_adapter.js`) and add it to the `adapters` array:

```js
const monitoringAdapter = createOciMonitoringAdapter({
    destinationMap: definition.adapters,
    emit: async ({ output, target }) => { /* postMetricData() via Resource Principal */ },
});
const dispatcher = createDestinationDispatcher({
    adapters: [bucketAdapter, monitoringAdapter],
    deadLetterDestination: definition.dead_letter,
});
```

This is a code change to `router_core.js`, the Fn orchestration/adapter layer.

### Blocker 2 — `oci_monitoring_adapter.js` is not in the Fn build context

The monitoring adapter exists at `tools/adapters/oci_monitoring_adapter.js` but has no
presence in `fn/router_passthrough/lib/`. The Fn Docker build packages only the
`fn/router_passthrough/` directory tree. `router_core.js` cannot `require` the monitoring
adapter unless:

- A symlink `fn/router_passthrough/lib/oci_monitoring_adapter.js →
  tools/adapters/oci_monitoring_adapter.js` is created (same pattern as BUG-4 for the other
  shared library files), **or**
- The file is physically copied (defeats single-source).

This is a structural change beyond routing configuration.

### Blocker 3 — OCI Monitoring `postMetricData()` call needs implementation

The `oci_monitoring_adapter.js` `emit` function is a no-op stub (`async () => {}`). A
concrete implementation must call:

```js
const monitoring = require('oci-monitoring');
const client = new monitoring.MonitoringClient({ authenticationDetailsProvider: provider });
await client.postMetricData({ postMetricDataDetails: { metricData: output, batchAtomicity: 'ATOMIC' } });
```

This requires adding `oci-monitoring` to `fn/router_passthrough/package.json` and writing
the emit function body in `router_core.js`. Not configuration.

---

## What IS pure configuration (not blocked)

| Item | File | Status |
| --- | --- | --- |
| `oci_monitoring:github_workflow_run` adapter entry | `routing.json` | Ready |
| Fanout route `github_workflow_run_to_metric` | `routing.json` | Ready |
| JSONata mapping `workflow_run_metric.jsonata` | new file | Ready |

These can be prepared now and activated once the blockers above are resolved in a follow-up
sprint that explicitly permits `router_core.js` changes.

---

## Root cause — design deficiency, not missing code

The sprint constraint ("no core changes") exposed a design deficiency: `router_core.js`
hardcodes its adapter list instead of deriving it from the routing definition. The correct
fix is **not** to add adapters manually each time — it is to make `router_core.js` react to
the routing config:

```js
// Derive required adapter types from definition.adapters keys
const adapterTypes = new Set(
    Object.keys(definition.adapters).map(k => k.split(':')[0])
);

const adapters = [];
if (adapterTypes.has('oci_object_storage')) adapters.push(createOciObjectStorageAdapter(...));
if (adapterTypes.has('oci_monitoring'))     adapters.push(createOciMonitoringAdapter(...));
// future types: oci_logging, file_system, …

const dispatcher = createDestinationDispatcher({ adapters, ... });
```

Once this is in place, adding `oci_monitoring:github_workflow_run` to `routing.json` is
sufficient to activate the monitoring adapter — no further `router_core.js` changes needed.
This is tracked as **SLI-42**.

## Recommended next sprint scope

**Sprint N (SLI-42 prerequisite):** make `router_core.js` config-driven:

1. Symlink `fn/router_passthrough/lib/oci_monitoring_adapter.js` → `tools/adapters/oci_monitoring_adapter.js`
2. Add `oci-monitoring` to `fn/router_passthrough/package.json`
3. Replace hardcoded `adapters: [bucketAdapter]` with type-detection loop over `definition.adapters` keys
4. Add `postMetricData` emit implementation using Resource Principal auth
5. Unit test: routing definition with only `oci_object_storage:*` → one adapter; add `oci_monitoring:*` → two adapters automatically

**Sprint N+1 (SLI-41, pure config):** once SLI-42 is in place:

1. Add `oci_monitoring:github_workflow_run` adapter entry to `routing.json`
2. Add fanout route `github_workflow_run_to_metric` to `routing.json`
3. Upload `workflow_run_metric.jsonata` to `config/` in Object Storage
4. Unit + integration tests for the new route and metric shape
