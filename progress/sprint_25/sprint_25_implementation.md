# Sprint 25 — Implementation (SLI-42)

## Status: DONE

---

## Changes delivered

### 1. `fn/router_passthrough/lib/oci_monitoring_adapter.js` (new)

Copy of `tools/adapters/oci_monitoring_adapter.js` added to the Fn build context.
Same pattern as the existing `oci_object_storage_adapter.js` copy.

### 2. `fn/router_passthrough/package.json`

Added `"oci-monitoring": "^2.127.0"` alongside the existing OCI SDK dependencies.

### 3. `fn/router_passthrough/router_core.js`

Three additions:

**Import:**
```js
const { createOciMonitoringAdapter } = require('./lib/oci_monitoring_adapter');
```

**Compartment injection in `applyIngestBucketToRoutingObject`:**
```js
const compartmentId = (process.env.OCI_MONITORING_COMPARTMENT_ID || '').trim();
for (const [key, val] of Object.entries(obj.adapters)) {
    if (String(key).startsWith('oci_monitoring:') && isObject(val) && compartmentId && !val.compartmentId) {
        val.compartmentId = compartmentId;
    }
}
```

**Config-driven dispatcher in `runRouter`:**

Replaced the hardcoded `adapters: [bucketAdapter]` with a type-detection loop:

```js
const adapterTypes = new Set(Object.keys(definition.adapters).map(k => k.split(':')[0]));
const adapters = [];

if (adapterTypes.has('oci_object_storage')) adapters.push(bucketAdapter);

if (adapterTypes.has('oci_monitoring')) {
    adapters.push(createOciMonitoringAdapter({
        destinationMap: definition.adapters,
        emit: async ({ output, target }) => {
            if (output === undefined || output === null) return;
            const metricData = Array.isArray(output) ? output : [output];
            if (metricData.length === 0) return;
            const enriched = metricData.map(m => ({ compartmentId: target.compartmentId, ...m }));
            await postMetricDataImpl({ metricData: enriched });
        },
    }));
}

const dispatcher = createDestinationDispatcher({ adapters, deadLetterDestination: definition.dead_letter });
```

The monitoring `emit` uses a `postMetricDataImpl` stub (testable via `options.postMetricData`) that
falls back to `oci-monitoring` `MonitoringClient.postMetricData()` with Resource Principal auth and
the telemetry-ingestion endpoint when `OCI_REGION` is set.

**Guard for empty JSONata output:**

JSONata returns `undefined` for empty sequences and `[]` for explicit empty array expressions. Both
are handled — `postMetricDataImpl` is not called in either case.

### 4. `tests/unit/test_fn_passthrough_router.sh`

Three new test cases (UT-SLI42-1 through UT-SLI42-3):

| ID | Assertion |
| --- | --- |
| UT-SLI42-1 | Routing with only `oci_object_storage:*` — monitoring emit never called |
| UT-SLI42-2 | Routing with `oci_monitoring:*` — monitoring adapter activated; `compartmentId` injected from env |
| UT-SLI42-3 | Transform returning `[]` — `postMetricData` skipped; Object Storage emit still fires |

---

## Env vars introduced

| Var | Required | Purpose |
| --- | --- | --- |
| `OCI_MONITORING_COMPARTMENT_ID` | When `oci_monitoring:*` adapters are present | Injected into each metric data item as `compartmentId` |
| `OCI_REGION` | Recommended | Sets `telemetry-ingestion.<region>.oraclecloud.com` endpoint on `MonitoringClient` |

---

## Design note — path.basename in test helpers

The `loadMappingFromRef` helpers in tests must use `path.basename(String(mappingRef))` rather than
`String.includes('passthrough')` to distinguish `passthrough.jsonata` from other mapping files.
The router resolves mapping refs to absolute paths, and the directory name `router_passthrough`
would cause naive substring checks to match unintended refs.
