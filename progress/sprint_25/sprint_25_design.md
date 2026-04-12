# Sprint 25 — Design (SLI-42)

## Problem

`router_core.js` creates its `DestinationDispatcher` with a hardcoded adapter list:

```js
const dispatcher = createDestinationDispatcher({
    adapters: [bucketAdapter],   // ← always exactly one adapter
    ...
});
```

Adding a second destination type (e.g. `oci_monitoring`) requires modifying source code.
The adapter library (`tools/adapters/`) already supports multiple adapters and multiple
destination types — the gap is only in the Fn wiring layer.

---

## Design

### 1 — Adapter presence in build context

`fn/router_passthrough/lib/oci_monitoring_adapter.js` must exist so Docker can include it.
Pattern: copy of `tools/adapters/oci_monitoring_adapter.js` (same as existing lib files).

### 2 — npm dependency

Add `"oci-monitoring": "^2.127.0"` to `fn/router_passthrough/package.json`.

### 3 — `applyIngestBucketToRoutingObject` — compartment injection

Inject `compartmentId` from `OCI_MONITORING_COMPARTMENT_ID` env var into every
`oci_monitoring:*` adapter entry that lacks one. Mirrors the existing bucket injection for
`oci_object_storage:*` entries.

### 4 — Config-driven dispatcher in `runRouter`

Replace the hardcoded adapter list with a type-detection loop:

```js
const adapterTypes = new Set(Object.keys(definition.adapters).map(k => k.split(':')[0]));
const adapters = [];
if (adapterTypes.has('oci_object_storage')) adapters.push(bucketAdapter);
if (adapterTypes.has('oci_monitoring'))     adapters.push(monitoringAdapter);
const dispatcher = createDestinationDispatcher({ adapters, ... });
```

Each adapter type is activated only when at least one key with that prefix exists in
`definition.adapters`. No code change is needed to add future types — only a new
`if (adapterTypes.has(...))` branch.

### 5 — OCI Monitoring emit

`createOciMonitoringAdapter` accepts a caller-supplied `emit` callback.
`router_core.js` provides a concrete emit that:

1. Guards against `undefined`/`null`/empty-array output (JSONata empty-sequence semantics).
2. Spreads `compartmentId` from `target` into each metric data item.
3. Calls `oci-monitoring` `MonitoringClient.postMetricData()` with Resource Principal auth.
4. Sets `https://telemetry-ingestion.${OCI_REGION}.oraclecloud.com` endpoint when `OCI_REGION` is set.
5. Uses `batchAtomicity: 'ATOMIC'`.

For tests, `options.postMetricData` overrides the live OCI call — same pattern as
`options.putObject` for the Object Storage adapter.

### 6 — Env vars introduced

| Var | Required | Purpose |
| --- | --- | --- |
| `OCI_MONITORING_COMPARTMENT_ID` | When `oci_monitoring:*` adapters present | Injected as `compartmentId` on each metric |
| `OCI_REGION` | Recommended | Sets telemetry-ingestion endpoint |

---

## Testing Strategy

**Scope:** unit tests only. Integration deferred — no `oci_monitoring` route exists in the live
`routing.json` yet (that is SLI-41). The unit tests exercise every code path through stubs.

**New test cases (in `test_fn_passthrough_router.sh`):**

| ID | Scenario | Assertion |
| --- | --- | --- |
| UT-SLI42-1 | Routing definition with only `oci_object_storage:*` adapters | `postMetricData` never called; `putObject` fires once |
| UT-SLI42-2 | Routing definition with both `oci_object_storage:*` and `oci_monitoring:*` (fanout) | Both stubs fire; `compartmentId` injected from env var |
| UT-SLI42-3 | Fanout route where monitoring transform returns `[]` (filtered event) | `postMetricData` skipped; `putObject` unaffected |

**Regression scope:** Sprint 25 inherits the Sprint 23 14-file manifest
(`progress/sprint_25/regression_tests.manifest`).

---

## Test Specification

### UT-SLI42-1 — OS-only routing: monitoring adapter not activated

```
Input routing: adapters = { 'oci_object_storage:ingest': {...} }
Event: any body, no monitoring route
Expect: putObject called once, postMetricData never called
```

### UT-SLI42-2 — Fanout with monitoring: both adapters fire, compartmentId injected

```
Input routing: adapters = { 'oci_object_storage:ingest': {...}, 'oci_monitoring:events': {...} }
OCI_MONITORING_COMPARTMENT_ID = 'ocid1.compartment.oc1..test'
Event: body that passes through both fanout routes
Expect: putObject called once, postMetricData called once,
        metricData[0].compartmentId === 'ocid1.compartment.oc1..test'
```

### UT-SLI42-3 — Empty transform output: postMetricData skipped

```
Input routing: same as UT-SLI42-2
Monitoring route mapping: returns [] (simulates action=requested filter)
Expect: putObject called once (OS route), postMetricData never called
```
