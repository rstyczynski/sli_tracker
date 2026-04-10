# Sprint 21 Design — SLI-33 + SLI-34 Universal Destinations

## Goal

Decouple the routing contract from transport-specific configuration. Routes carry
logical destinations; adapters resolve them to transport targets at runtime.

---

## Routing contract (`routing.json`)

`routing.json` is the **single configuration document** for the routing pipeline.
It contains these top-level sections:

1. `adapters` — target config for every logical destination, keyed by `"type:name"`
2. `source` — logical source from which envelopes are read (resolved via `adapters`)
3. `mapping` — logical source from which mapping files are fetched (resolved via `adapters`)
4. `dead_letter` — logical destination for envelopes that match no route (any adapter type)
5. `routes` — routing and transformation rules

```json
{
  "adapters": {
    "oci_logging:github_events": {
      "logId": "ocid1.log.oc1.iad..example"
    },
    "oci_monitoring:health_signal": {
      "compartmentId": "ocid1.compartment.oc1..example"
    },
    "oci_object_storage:raw_events": {
      "bucket": "incoming",
      "prefix": "events/"
    },
    "oci_object_storage:mappings": {
      "bucket": "sli-mappings",
      "prefix": "jsonata/"
    },
    "file_system:audit_copy": {
      "directory": "audit/events"
    },
    "oci_logging:pipeline_errors": {
      "logId": "ocid1.log.oc1.iad..example"
    }
  },
  "mapping": {
    "type": "oci_object_storage",
    "name": "mappings"
  },
  "dead_letter": {
    "type": "oci_logging",
    "name": "pipeline_errors"
  },
  "routes": [
    {
      "id": "workflow_to_logging",
      "match": {
        "headers": {
          "X-GitHub-Event": "workflow_run"
        }
      },
      "transform": {
        "mapping": "mapping_log.jsonata"
      },
      "destination": {
        "type": "oci_logging",
        "name": "github_events"
      }
    },
    {
      "id": "health_to_monitoring",
      "match": {
        "endpoint": "/health"
      },
      "transform": {
        "mapping": "mapping_metric.jsonata"
      },
      "destination": {
        "type": "oci_monitoring",
        "name": "health_signal"
      }
    },
    {
      "id": "bucket_to_object_storage",
      "match": {
        "schema": {
          "path": "type",
          "equals": "com.oraclecloud.objectstorage.createobject"
        }
      },
      "transform": {
        "mapping": "mapping_bucket.jsonata"
      },
      "destination": {
        "type": "oci_object_storage",
        "name": "raw_events"
      }
    },
    {
      "id": "audit_to_file",
      "match": {
        "required_fields": [
          "audit.id"
        ]
      },
      "transform": {
        "mapping": "mapping_file.jsonata"
      },
      "destination": {
        "type": "file_system",
        "name": "audit_copy"
      }
    }
  ]
}
```

### `adapters` section

Keys use the format `"type:name"` (exact match). A bare `"type"` key acts as a fallback
for unnamed destinations. Values are adapter-specific objects:

- OCI adapters: `{ "logId": "...", "compartmentId": "..." }`, `{ "namespace": "...", "metric": "..." }`, etc.
- File adapter: `{ "directory": "relative/path" }` — path is appended under the adapter's `rootDir`

`loadRoutingDefinition()` / `loadRoutingDefinitionFromObject()` parse and expose
`definition.adapters`. Adapters receive it as `destinationMap`:

```js
const definition = loadRoutingDefinition('./routing.json');
const logging = createOciLoggingAdapter({ destinationMap: definition.adapters });
```

### `mapping` section

`mapping` declares the logical source from which the router fetches mapping files.
It uses the same `{ type, name }` format as any destination:

```json
"mapping": { "type": "oci_object_storage", "name": "mappings" }
```

The `adapters` section must contain a matching entry:

```json
"oci_object_storage:mappings": { "bucket": "sli-mappings", "prefix": "jsonata/" }
```

Each route's `transform.mapping` value is then a **key** (filename) resolved against
that source — e.g., `"mapping_log.jsonata"` becomes object key `jsonata/mapping_log.jsonata`
in the `sli-mappings` bucket.

When `mapping` is absent, the router resolves `transform.mapping` as a local file path
(current behavior, for local/development use).

`loadRoutingDefinition()` exposes the parsed value as `definition.mapping`.

#### Runtime wiring (implemented)

The router supports an optional async handler **`loadMapping`**:

- If `definition.mapping` is present: `route.transform.mapping` is treated as a **logical key** and resolved via `loadMapping`.
- If `definition.mapping` is absent: `route.transform.mapping` is treated as a local file path (backward compatible).

The default CLI (`tools/json_router_cli.js`) uses the same mechanism when `mapping` is present, using `OCI_CLI_PROFILE` (default `DEFAULT`) for OCI auth.

### `dead_letter` section

`dead_letter` is a regular logical destination — it uses the same `{ type, name }` format
as any route destination and is resolved through the same `adapters` section.

The dead letter target can be any supported adapter type:

```json
// send dead letters to OCI Logging
"dead_letter": { "type": "oci_logging", "name": "pipeline_errors" }

// or to Object Storage
"dead_letter": { "type": "oci_object_storage", "name": "error_bucket" }

// or to the local filesystem
"dead_letter": { "type": "file_system", "name": "errors" }
```

The dispatcher resolves the dead letter destination using the same adapter selection
logic as for normal route deliveries — it calls `adapter.supports(destination)` on each
adapter in order and dispatches to the first match. There is no `deadLetterAdapter`
hardcoded at construction time.

### Route destination rules

- `type` identifies the destination class (`oci_logging`, `oci_monitoring`,
  `oci_object_storage`, `file_system`, …) — applies equally to routes and dead letter
- `name` identifies the instance within that class — matched against `adapters` keys
- route and dead_letter destinations carry only `type` + `name` — no transport-specific fields
- all transport-specific config (`directory`, `logId`, `bucket`, …) belongs in `adapters`, not in routes

---

## Adapter modules

```text
tools/adapters/file_adapter.js
tools/adapters/oci_logging_adapter.js
tools/adapters/oci_monitoring_adapter.js
tools/adapters/oci_object_storage_adapter.js
tools/adapters/destination_dispatcher.js
```

Each adapter is created with a **`destinationMap`** that maps logical destination keys
to transport-specific target objects. The key format is `"type:name"` (exact match first,
then fallback to `"type"` alone for unnamed destinations).

---

## Adapter configuration

### `createFileAdapter(options)`

Resolves logical destinations to filesystem paths.

```js
const fileAdapter = createFileAdapter({
  rootDir: '/var/sli/output',          // required — all output paths are relative to this
  preserveSourceFileName: true,        // optional — reuse envelope.source_meta.file_name
  supportedTypes: ['file_system'],     // optional — restrict which destination types this adapter handles
  destinationMap: definition.adapters  // loaded from routing.json
});
```

`destinationMap` entries for the file adapter must be objects with a `directory` field
(relative path appended under `rootDir`). Without a map entry, the adapter falls back to `type/name` or just `type`.

### `createOciLoggingAdapter(options)`

Resolves `oci_logging` / `oci_log` destinations.

```js
const loggingAdapter = createOciLoggingAdapter({
  destinationMap: definition.adapters,  // loaded from routing.json
  emit: async ({ route, output, envelope, target }) => {
    // called for each delivery — plug in OCI SDK call here
    // target = { logId: 'log-1' } as configured in routing.json adapters
    await ociLoggingClient.putLogs(target.logId, output);
  }
});
```

`emit` defaults to a no-op. In tests, the default is used and deliveries are inspected via
`adapter.getState().deliveries`.

### `createOciMonitoringAdapter(options)`

Resolves `oci_monitoring` / `oci_metric` destinations.

```js
const monitoringAdapter = createOciMonitoringAdapter({
  destinationMap: definition.adapters,
  emit: async ({ route, output, envelope, target }) => {
    // target = { namespace: 'sli', metric: 'health' } as configured in routing.json adapters
    await ociMonitoringClient.postMetricData(target.compartmentId, output);
  }
});
```

### `createOciObjectStorageAdapter(options)`

Resolves `oci_object_storage` destinations.

```js
const objectStorageAdapter = createOciObjectStorageAdapter({
  destinationMap: definition.adapters,
  emit: async ({ route, output, envelope, target }) => {
    // target = { bucket: 'incoming', prefix: 'events/' } as configured in routing.json adapters
    await objectStorageClient.putObject(target.namespaceName, target.bucket, key, output);
  }
});
```

---

## Dispatcher configuration

`createDestinationDispatcher` composes multiple adapters into a single handler object
compatible with `processEnvelope` / `processEnvelopes`.

```js
const dispatcher = createDestinationDispatcher({
  adapters: [loggingAdapter, monitoringAdapter, objectStorageAdapter, fileAdapter],
  deadLetterDestination: definition.dead_letter  // logical destination from routing.json
});
```

For normal deliveries, the dispatcher calls `adapter.supports(destination)` on each adapter
in order and dispatches to the first match.

For dead letters, the dispatcher resolves `deadLetterDestination` through the same adapter
selection — no separate `deadLetterAdapter` is needed. The dead letter can land on any
adapter that supports the configured destination type.

The dispatcher exposes `onRoute` and `onDeadLetter` — the shape expected by `processEnvelopes`.

---

## End-to-end wiring

```js
const { loadRoutingDefinition, processEnvelopes } = require('./tools/json_router');
const { createFileAdapter }             = require('./tools/adapters/file_adapter');
const { createOciLoggingAdapter }       = require('./tools/adapters/oci_logging_adapter');
const { createOciMonitoringAdapter }    = require('./tools/adapters/oci_monitoring_adapter');
const { createOciObjectStorageAdapter } = require('./tools/adapters/oci_object_storage_adapter');
const { createDestinationDispatcher }   = require('./tools/adapters/destination_dispatcher');

const definition = loadRoutingDefinition('./routing.json');
// definition.adapters  — all target config, keyed by "type:name"
// definition.dead_letter — logical destination for dead letters, e.g. { type: 'oci_logging', name: 'pipeline_errors' }

// all adapters share the same destinationMap from routing.json
const fileAdapter    = createFileAdapter({
  rootDir: '/var/sli/output',
  supportedTypes: ['file_system'],
  destinationMap: definition.adapters,
  preserveSourceFileName: true,
});

const logging       = createOciLoggingAdapter(      { destinationMap: definition.adapters });
const monitoring    = createOciMonitoringAdapter(   { destinationMap: definition.adapters });
const objectStorage = createOciObjectStorageAdapter({ destinationMap: definition.adapters });

// dead letter destination is resolved by the same adapter selection — no special adapter
const dispatcher = createDestinationDispatcher({
  adapters: [logging, monitoring, objectStorage, fileAdapter],
  deadLetterDestination: definition.dead_letter   // { type: 'oci_logging', name: 'pipeline_errors' }
});

const summary = await processEnvelopes(envelopes, definition, dispatcher);
// summary: { processed, routed, dead_lettered, results }
```

---

## Envelope format

Each envelope passed to `processEnvelopes` must match the router's match criteria:

```json
// matched by header
{ "headers": { "X-GitHub-Event": "workflow_run" }, "body": { ... } }

// matched by endpoint
{ "endpoint": "/health", "body": { "status": "UP" } }

// matched by body field value
{ "body": { "type": "com.oraclecloud.objectstorage.createobject", "data": { ... } } }

// matched by required field presence
{ "body": { "audit": { "id": "A-1", "message": "..." } } }

// matches no route → dead letter
{ "body": { "message": "no route" } }
```

---

## Architecture constraints

- The router still routes and transforms; it has no knowledge of adapters.
- Adapters carry transport-specific config; they have no knowledge of routing rules.
- The dispatcher composes them without modifying either side.
- `routeDirectory()` in `json_router.js` is a legacy filesystem-direct path that bypasses
  adapters — it remains for CLI batch use but will diverge from the adapter layer over time.

---

## Test runner

`tests/run.sh` gains a generic manifest filter:

```text
tests/run.sh --unit --manifest <file>
```

Used for component-scoped regression while `--new-only` remains the new-code gate alias.

---

## Testing strategy

Scope: unit + integration. Unit tests remain offline; integration tests validate live OCI Object Storage mapping fetch.

New-code gate (`new_tests.manifest`):

- router schema, batch routing, CLI batch behavior, destination adapter unit tests

Regression gate (`regression_tests.manifest`):

- limited to router/transformer component scripts

| ID      | Scenario                                                                        |
|---------|---------------------------------------------------------------------------------|
| UT-111  | file adapter resolves logical destination via `destinationMap`                  |
| UT-112  | OCI Logging adapter resolves `oci_logging:github_events` → target               |
| UT-113  | OCI Monitoring adapter resolves `oci_monitoring:health_signal` → target         |
| UT-114  | OCI Object Storage adapter resolves `oci_object_storage:raw_events` → target    |
| UT-115  | dispatcher routes 5 envelopes: 4 routed to mixed adapters, 1 dead-lettered      |

Integration gate (`integration_tests.manifest`):

| ID      | Scenario                                                                        |
|---------|---------------------------------------------------------------------------------|
| IT-1    | router fetches mapping from OCI Object Storage using `mapping` + `adapters`     |
| IT-2    | router CLI fetches mapping from OCI Object Storage (CLI/library parity)         |
