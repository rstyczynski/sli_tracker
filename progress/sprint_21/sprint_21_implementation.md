# Sprint 21 Implementation — SLI-33 + SLI-34 Universal Destinations

## Files Created

- `tools/adapters/oci_logging_adapter.js`
- `tools/adapters/oci_monitoring_adapter.js`
- `tools/adapters/oci_object_storage_adapter.js`
- `tools/adapters/destination_dispatcher.js`
- `tools/adapters/mapping_loader.js`
- `tools/adapters/oci_object_storage_mapping_source.js`
- `tests/unit/test_destination_adapters.sh`
- `tests/unit/test_json_router_mapping_source.sh`
- `tests/unit/test_mapping_loader.sh`
- `tests/fixtures/router_destinations/ut111_mixed_destinations/*`
- `progress/sprint_21/new_tests.manifest`
- `progress/sprint_21/regression_tests.manifest`
- `progress/sprint_21/integration_tests.manifest`
- `tests/integration/test_json_router_mapping_oci_object_storage.sh`
- `tests/integration/test_json_router_cli_mapping_oci_object_storage.sh`

## Files Updated

- `tools/schemas/json_router_definition.schema.json`
- `tools/json_router.js`
- `tools/json_router_cli.js`
- `tools/adapters/file_adapter.js`
- `tests/run.sh`
- router batch fixtures
- router schema fixtures

---

## `routing.json` structure

`routing.json` is the single configuration document. Top-level sections:

```json
{
  "adapters": {
    "oci_logging:github_events":     { "logId": "ocid1.log.oc1.iad..example" },
    "oci_monitoring:health_signal":  { "compartmentId": "ocid1.compartment.oc1..example" },
    "oci_object_storage:raw_events": { "bucket": "incoming", "prefix": "events/" },
    "oci_object_storage:mappings":   { "bucket": "sli-mappings", "prefix": "jsonata/" },
    "file_system:audit_copy":        { "directory": "audit/events" },
    "oci_logging:pipeline_errors":   { "logId": "ocid1.log.oc1.iad..example" }
  },
  "source": {
    "type": "file_system",
    "name": "incoming"
  },
  "mapping": {
    "type": "oci_object_storage",
    "name": "mappings"
  },
  "dead_letter": {
    "type": "oci_logging",
    "name": "pipeline_errors"
  },
  "routes": [ ... ]
}
```

### `adapters`

Keys: `"type:name"` (exact match), fallback `"type"` for unnamed destinations.
Values are adapter-specific objects:

- `oci_logging`: `{ "logId": "..." }` — OCI log resource identifier
- `oci_monitoring`: `{ "compartmentId": "..." }` — OCI compartment for metric posting
- `oci_object_storage`: `{ "bucket": "...", "prefix": "..." }` — bucket and object prefix
- `file_system`: `{ "directory": "relative/path" }` — path appended under adapter `rootDir`

### `mapping`

Logical source for mapping files — same `{ type, name }` format as a destination.
The router resolves `transform.mapping` (a filename key) via this adapter at runtime.
When absent, `transform.mapping` is treated as a local file path (backward compat).

`definition.mapping` is exposed after loading.

**Implementation (completed):**

- Router exposes an optional async handler `loadMapping` (passed to `processEnvelope`, `processEnvelopes`, and `routeTransformAll`).
- When `definition.mapping` is present, the router treats `route.transform.mapping` as a **logical key** and resolves it via `loadMapping`.
- `tools/adapters/mapping_loader.js` resolves `definition.mapping` through `definition.adapters` and delegates to mapping-source implementations.
- `tools/adapters/oci_object_storage_mapping_source.js` implements a mapping source for `oci_object_storage` and is unit-testable via injected `getObject`.
- `tools/json_router_cli.js` automatically wires the same behavior when `mapping` is present, using OCI Object Storage SDK (`oci-objectstorage`) and `OCI_CLI_PROFILE` (default: `DEFAULT`).

### `source`

`source` declares the logical input adapter used to read envelopes end-to-end from `routing.json`.
This is used by the library runtime (`tools/router_runtime.js`) and by the CLI when `source` is present.

### `dead_letter`

Logical destination for envelopes that match no route — any adapter type.
Resolved by the dispatcher using the same adapter selection as normal deliveries.
The dead letter payload `{ error, envelope }` is delivered as `output` to the target adapter.

`definition.dead_letter` is exposed after loading.

---

## Adapter API

All adapters share the same factory pattern and are compatible with
`processEnvelope` / `processEnvelopes` in `json_router.js`.

### `createFileAdapter(options)`

```js
const { createFileAdapter } = require('./tools/adapters/file_adapter');

const adapter = createFileAdapter({
  rootDir:                '/var/sli/output',  // required
  preserveSourceFileName: true,              // reuse envelope.source_meta.file_name
  supportedTypes:         ['file_system'],   // restrict accepted destination types
  destinationMap:         definition.adapters
});
```

`destinationMap` entries must be objects with a `directory` field (path appended under `rootDir`).
Fallback without a map entry: `type/name` or `type`.

State: `adapter.getState()` → `{ routeWrites: [{ route, path }], deadLetterWrites: [{ path }] }`

### `createOciLoggingAdapter(options)`

```js
const { createOciLoggingAdapter } = require('./tools/adapters/oci_logging_adapter');

const adapter = createOciLoggingAdapter({
  destinationMap: definition.adapters,
  emit: async ({ route, output, envelope, target }) => {
    // target = { logId: '...' } from routing.json adapters
    await ociLoggingClient.putLogs(target.logId, output);
  }
  // emit defaults to no-op — unit-test friendly
});
```

State: `adapter.getState()` → `{ deliveries: [{ route, target }] }`

Handles both normal deliveries and dead letters (when `dead_letter` points to `oci_logging`).

### `createOciMonitoringAdapter(options)`

```js
const { createOciMonitoringAdapter } = require('./tools/adapters/oci_monitoring_adapter');

const adapter = createOciMonitoringAdapter({
  destinationMap: definition.adapters,
  emit: async ({ route, output, envelope, target }) => {
    // target = { compartmentId: '...' } from routing.json adapters
    await ociMonitoringClient.postMetricData(target.compartmentId, output);
  }
});
```

### `createOciObjectStorageAdapter(options)`

```js
const { createOciObjectStorageAdapter } = require('./tools/adapters/oci_object_storage_adapter');

const adapter = createOciObjectStorageAdapter({
  destinationMap: definition.adapters,
  emit: async ({ route, output, envelope, target }) => {
    // target = { bucket: '...', prefix: '...' } from routing.json adapters
    await objectStorageClient.putObject(target.namespaceName, target.bucket, key, output);
  }
});
```

### `createDestinationDispatcher(options)`

```js
const { createDestinationDispatcher } = require('./tools/adapters/destination_dispatcher');

const dispatcher = createDestinationDispatcher({
  adapters: [logging, monitoring, objectStorage, fileAdapter],
  deadLetterDestination: definition.dead_letter  // { type, name } from routing.json
});
```

Dispatch logic:

- **Normal delivery**: calls `adapter.supports(destination)` in order; dispatches to first match
- **Dead letter**: resolves `deadLetterDestination` through the same adapter selection; calls `adapter.onRoute` with `output: { error, envelope }` — no special dead letter path, any adapter type works

---

## End-to-end wiring

```js
const { loadRoutingDefinition, processEnvelopes } = require('./tools/json_router');
const { createFileAdapter }             = require('./tools/adapters/file_adapter');
const { createOciLoggingAdapter }       = require('./tools/adapters/oci_logging_adapter');
const { createOciMonitoringAdapter }    = require('./tools/adapters/oci_monitoring_adapter');
const { createOciObjectStorageAdapter } = require('./tools/adapters/oci_object_storage_adapter');
const { createDestinationDispatcher }   = require('./tools/adapters/destination_dispatcher');

// 1 — load routing.json (adapters, mapping, dead_letter, routes all in one file)
const definition = loadRoutingDefinition('./routing.json');

// 2 — create adapters — all share definition.adapters as destinationMap
const fileAdapter   = createFileAdapter({
  rootDir: '/var/sli/output',
  supportedTypes: ['file_system'],
  destinationMap: definition.adapters,
});

const logging       = createOciLoggingAdapter(      { destinationMap: definition.adapters });
const monitoring    = createOciMonitoringAdapter(   { destinationMap: definition.adapters });
const objectStorage = createOciObjectStorageAdapter({ destinationMap: definition.adapters });

// 3 — compose dispatcher; dead letter resolved via same adapter selection
const dispatcher = createDestinationDispatcher({
  adapters: [logging, monitoring, objectStorage, fileAdapter],
  deadLetterDestination: definition.dead_letter
});

// 4 — process envelopes
const summary = await processEnvelopes(envelopes, definition, dispatcher);
// { processed: N, routed: N, dead_lettered: N, results: [...] }
```

---

## Design Decisions

- `adapters` section in `routing.json` is the single source of transport config — no
  separate config files, no hardcoded maps in application code
- `dead_letter` is a regular logical destination — any adapter type, resolved via the same
  adapter selection as normal deliveries; no `deadLetterAdapter` property on dispatcher
- `mapping` declares the logical source for mapping files — resolved via `adapters`;
  remote fetch (OCI Object Storage) is supported via `loadMapping` handler; local file path remains a fallback for development
- File adapter `destinationMap` entries use `{ "directory": "..." }` objects (not plain strings)
- OCI adapter `emit` defaults to no-op — adapters are unit-testable without OCI SDK
- Regression scoped to router/transformer component via `--manifest` filter on `tests/run.sh`

## Test scenarios

- **UT-111** (`test_destination_adapters.sh`): file adapter resolves `file_system:audit_copy` → `{ directory }` from `routing.json`
- **UT-112** (`test_destination_adapters.sh`): OCI Logging adapter resolves `oci_logging:github_events` → `{ logId }`
- **UT-113** (`test_destination_adapters.sh`): OCI Monitoring adapter resolves `oci_monitoring:health_signal` → `{ compartmentId }`
- **UT-114** (`test_destination_adapters.sh`): OCI Object Storage adapter resolves `oci_object_storage:raw_events` → `{ bucket, prefix }`
- **UT-115** (`test_destination_adapters.sh`): dispatcher routes 5 envelopes (4 routed, 1 dead-lettered)
- **UT-116** (`test_destination_adapters.sh`): `routing.json` `mapping` parsed and exposed as `definition.mapping`
- **UT-117** (`test_destination_adapters.sh`): dispatcher throws when dead letter fires and no `deadLetterDestination` configured
- **UT-118** (`test_destination_adapters.sh`): dispatcher throws when no adapter supports the configured dead letter destination type

## Known Limitations

- The three OCI adapters share identical internal structure — a shared factory would
  reduce duplication
- `routeDirectory()` in `json_router.js` bypasses the adapter layer — legacy CLI batch path
- Object Storage operations in integration tests can be eventually consistent; tests retry
  `putObject` / `getObject` to avoid flakiness

## Regression Outcome

Component-scoped regression:

```text
tests/run.sh --unit --manifest progress/sprint_21/regression_tests.manifest
```

11 scripts, 11 passed.

## Integration Outcome (added)

Live OCI validation (Object Storage mapping source + CLI parity):

```text
tests/run.sh --integration --manifest progress/sprint_21/integration_tests.manifest
```

2 scripts, 2 passed.
