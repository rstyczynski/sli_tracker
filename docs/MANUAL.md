# SLI Tracker Manual

`SLI_tracker` is a framework for collecting, routing, storing, and evaluating Service Level Indicator data on Oracle Cloud Infrastructure. It provides tools and techniques to push service level indicators to OCI Monitoring, OCI Logging, and OCI Object Storage.

The same framework can be used beyond the GitHub Actions example implemented in this repository. The current repository is one concrete system built with these techniques, but the same pattern can be extended to other SLI sources, other telemetry domains, and other kinds of status or health information.

The framework can accept notifications from external systems, receive OCI-native events, and pull data from exposed service endpoints. In all of these cases it applies the same core flow: collect data, normalize it, route it, store it, and evaluate it.

The system model is shown below.

<p align="center"><img src="../model/model.jpg" alt="SLI Tracker system model" width="50%"></p>

The editable source is [`model/model.drawio`](../model/model.drawio).

## 1. Project Overview

`SLI_tracker` is an general purpose OCI-based Service LEvel Indicator (SLI) collection and processing framework. In this repository, the main exemplar use case is CI/CD telemetry built around GitHub Actions, but the architecture is intentionally broader than one pipeline domain.

At a high level, the system does five things:

1. It emits structured SLI events from GitHub Actions workflows.
2. It receives notifications and events from external systems and OCI-native services.
3. It can query exposed service endpoints to collect status data.
4. It transforms and routes JSON payloads using JSONata mappings.
5. It stores telemetry in OCI services such as Logging, Monitoring, and Object Storage, then computes derived SLI values from that telemetry.

The repository evolved in stages:

1. Initial GitHub Actions instrumentation and OCI Logging emission.
2. Optional OCI Monitoring metric emission.
3. Local and workflow-based testing around emission.
4. A generic JSON routing and transformation layer.
5. OCI Function based public ingest and fan-out delivery.
6. Component-scoped testing and RUP-managed delivery process.

## 2. Motivating Story and Mental Model

The best way to understand this repository is to start with one concrete event and follow it until it becomes useful operational data.

### 2.1 Start with a Real `workflow_run` Event

GitHub can send a `workflow_run` webhook when a workflow finishes. That event is rich, but it is not yet in a form that operators want to query, route, alert on, or compute ratios from.

For example, a real payload contains fields in a shape like this:

```json
{
  "action": "completed",
  "workflow_run": {
    "id": 123456789,
    "name": "model-push",
    "conclusion": "success",
    "head_branch": "main",
    "head_sha": "abc123"
  },
  "repository": {
    "full_name": "owner/repo"
  }
}
```

That message already has value. It tells us something happened, where it happened, and whether it succeeded. But it is still source-shaped data. It reflects GitHub's event model, not the model that OCI Logging, OCI Monitoring, dashboards, alerts, or downstream systems want to consume.

### 2.2 Why Transformation Exists

Transformation exists because raw webhook payloads are too source-specific. We usually want a smaller, cleaner contract such as:

- one normalized event for audit and troubleshooting
- one numeric signal for Monitoring
- one destination-specific object for storage or later processing

This is why the project uses JSONata mappings. Instead of hardcoding every source-to-target conversion in application code, the operator can define how a `workflow_run` becomes:

- a searchable log entry
- a metric datapoint
- a normalized router envelope

Transformation is the point where the system stops being "GitHub-specific JSON handling" and becomes a reusable telemetry platform.

### 2.3 Why the Router Exists

Transformation alone is not enough. Once data is normalized, someone still has to decide where it goes.

That is the router's job. The router lets the operator define:

- which messages match which routes
- which mapping should run for each route
- whether delivery is exclusive or fanout
- which destination should receive the result

This matters because the same `workflow_run` can be valuable in more than one place. One route may send an audit-friendly document to OCI Logging. Another may produce a metric-friendly document for OCI Monitoring. A third may archive the same event in Object Storage. The router turns one incoming message into an operator-controlled delivery policy.

## 3. OCI Injection Examples

Before going deeper into the architecture, it helps to see the two basic sink types directly:

- OCI Monitoring for compact numeric signals
- OCI Logging for searchable event records

These examples bypass `emit.sh` and push directly with OCI CLI. Use them when you want to validate OCI ingestion paths without the GitHub payload builder.

These first examples use the local `DEFAULT` OCI profile on purpose. At this stage the reader only needs one working authenticated profile to see data arrive in OCI. The repository-specific `SLI_TEST` profile is introduced later in the operator cookbook.

### 3.1 Inject One Log Entry into OCI Logging

This should append one JSON log entry to the configured OCI log. The payload is intentionally small and easy to recognize when you query the log later.

```bash
repo=$(gh repo view --json nameWithOwner -q .nameWithOwner)
LOG_ID="$(gh variable get SLI_OCI_LOG_ID -R "$repo")"
TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
export OCI_CLI_PROFILE=DEFAULT

LOG_BATCHES="$(jq -nc \
  --arg ts "$TS" \
  '[{
    defaultlogentrytime: $ts,
    source: "manual/oci-cli",
    type: "sli-event",
    entries: [{
      id: ($ts + "-manual"),
      time: $ts,
      data: ({
        source: "manual",
        path: "oci-cli",
        outcome: "success",
        timestamp: $ts
      } | tostring)
    }]
  }]')"

oci logging-ingestion put-logs \
  --log-id "$LOG_ID" \
  --specversion "1.0" \
  --log-entry-batches "$LOG_BATCHES"
```

Open the OCI Console, navigate to the Logging section, select the log group and log associated with your deployment, and query for recent entries. Locate the entry with the `source` set to `"manual/oci-cli"` and confirm that your log injection is visible with the correct timestamp and payload data.

### 3.2 Inject Failure Log Message

To inject a failure event, keep the same shape as the success payload above and change `outcome` to `"failure"`. Include an explicit failure reason so you can spot it easily in OCI Logging.

```bash
repo=$(gh repo view --json nameWithOwner -q .nameWithOwner)
LOG_ID="$(gh variable get SLI_OCI_LOG_ID -R "$repo")"
TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
export OCI_CLI_PROFILE=DEFAULT

LOG_BATCHES="$(jq -nc \
  --arg ts "$TS" \
  '[{
    defaultlogentrytime: $ts,
    source: "manual/oci-cli",
    type: "sli-event",
    entries: [{
      id: ($ts + "-manual"),
      time: $ts,
      data: ({
        source: "manual",
        path: "oci-cli",
        outcome: "failure",
        timestamp: $ts
      } | tostring)
    }]
  }]')"

oci logging-ingestion put-logs \
  --log-id "$LOG_ID" \
  --specversion "1.0" \
  --log-entry-batches "$LOG_BATCHES"
```

### 3.3 Query That Log Category Back and Compute Message-Level SLI

For the manual CLI log examples above, a simple message-level SLI is: `number of success messages / number of messages` The category is identified by the payload fields `source=="manual"` and `path=="oci-cli"`. Wait around 60 seconds for log propagation, and execute log search and SLI computation code for 30 minutes .

```bash
export OCI_CLI_PROFILE=DEFAULT
repo=$(gh repo view --json nameWithOwner -q .nameWithOwner)
COMPARTMENT_OCID="$(gh variable get SLI_OCI_COMPARTMENT_ID -R "$repo")"
LOG_ID="$(gh variable get SLI_OCI_LOG_ID -R "$repo")"
LOG_GROUP_ID="$(gh variable get SLI_OCI_LOG_GROUP_ID -R "$repo")"
TS_START="$(date -u -v-30M '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u --date='-30 min' '+%Y-%m-%dT%H:%M:%SZ')"
TS_END="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

EVENTS="$(
  oci logging-search search-logs \
    --search-query "search \"${COMPARTMENT_OCID}/${LOG_GROUP_ID}/${LOG_ID}\" | sort by datetime desc | limit 200" \
    --time-start "$TS_START" \
    --time-end "$TS_END" \
    --output json \
  | jq '.data.results'
)"

TOTAL="$(echo "$EVENTS" | jq '[.[] | .data.logContent.data | if type=="string" then fromjson else . end | select(.source == "manual" and .path == "oci-cli")] | length')"
SUCCESS="$(echo "$EVENTS" | jq '[.[] | .data.logContent.data | if type=="string" then fromjson else . end | select(.source == "manual" and .path == "oci-cli" and .outcome == "success")] | length')"
FAILURE="$(echo "$EVENTS" | jq '[.[] | .data.logContent.data | if type=="string" then fromjson else . end | select(.source == "manual" and .path == "oci-cli" and .outcome == "failure")] | length')"
SLI="$(jq -n --argjson success "$SUCCESS" --argjson total "$TOTAL" 'if $total == 0 then null else ($success / $total) end')"

jq -n \
  --argjson total "$TOTAL" \
  --argjson success "$SUCCESS" \
  --argjson failure "$FAILURE" \
  --argjson sli "$SLI" \
  '{total_messages: $total, success_messages: $success, failure_messages: $failure, sli: $sli}'
```

If you inserted one success message and one failure message into this category, the expected result is:

```json
{
  "total_messages": 2,
  "success_messages": 1,
  "failure_messages": 1,
  "sli": 0.5
}
```

### 3.4 Inject the Computed SLI as One Derived OCI Metric

After you compute `SLI` from the queried log stream, you can publish that ratio back to OCI Monitoring as a derived metric. Run this in the same shell as the previous snippet, or set `SLI` manually first. In this example the metric carries the dimension `window="30min"` so the reader can see which aggregation window produced the value.

```bash
export OCI_CLI_PROFILE=DEFAULT
repo=$(gh repo view --json nameWithOwner -q .nameWithOwner)
COMPARTMENT_OCID="$(gh variable get SLI_OCI_COMPARTMENT_ID -R "$repo")"
TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
SLI="${SLI:?Run the previous SLI computation snippet first, or export SLI manually.}"
OCI_REGION="$(
  oci os ns get --debug 2>&1 \
    | sed -n 's/.*Endpoint: https:\/\/objectstorage\.\([^.]*\)\..*/\1/p' \
    | head -1
)"
OCI_REALM_SUFFIX="$(
  oci os ns get --debug 2>&1 \
    | sed -n 's/.*Endpoint: https:\/\/objectstorage\.[^.]*\.\([^[:space:]]*\).*/\1/p' \
    | head -1
)"
OCI_MONITORING_ENDPOINT="https://telemetry-ingestion.${OCI_REGION}.${OCI_REALM_SUFFIX}"

SLI_METRIC_PAYLOAD="$(jq -nc \
  --arg compartment "$COMPARTMENT_OCID" \
  --arg ts "$TS" \
  --argjson sli "$SLI" \
  '[{
    compartmentId: $compartment,
    namespace: "sli_tracker_manual",
    name: "sli",
    dimensions: {
      source: "manual",
      path: "oci-cli",
      window: "30min"
    },
    datapoints: [{
      timestamp: $ts,
      value: $sli
    }]
  }]')"

oci monitoring metric-data post \
  --endpoint "$OCI_MONITORING_ENDPOINT" \
  --metric-data "$SLI_METRIC_PAYLOAD" \
  --batch-atomicity ATOMIC \
  | jq
```

### 3.5 Inject One Custom Metric into OCI Monitoring

This should create one `outcome` datapoint in namespace `sli_tracker_manual` with simple dimensions so it is easy to find later.

```bash
repo=$(gh repo view --json nameWithOwner -q .nameWithOwner)
COMPARTMENT_OCID="$(gh variable get SLI_OCI_COMPARTMENT_ID -R "$repo")"
TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
export OCI_CLI_PROFILE=DEFAULT
OCI_REGION="$(
  oci os ns get --debug 2>&1 \
    | sed -n 's/.*Endpoint: https:\/\/objectstorage\.\([^.]*\)\..*/\1/p' \
    | head -1
)"
OCI_REALM_SUFFIX="$(
  oci os ns get --debug 2>&1 \
    | sed -n 's/.*Endpoint: https:\/\/objectstorage\.[^.]*\.\([^[:space:]]*\).*/\1/p' \
    | head -1
)"
OCI_MONITORING_ENDPOINT="https://telemetry-ingestion.${OCI_REGION}.${OCI_REALM_SUFFIX}"

METRIC_PAYLOAD="$(jq -nc \
  --arg compartment "$COMPARTMENT_OCID" \
  --arg ts "$TS" \
  --argjson sli "${SLI:-1}" \
  '[
    {
      compartmentId: $compartment,
      namespace: "sli_tracker_manual",
      name: "outcome",
      dimensions: {
        emit_env: "local",
        source: "manual",
        path: "oci-cli"
      },
      datapoints: [{
        timestamp: $ts,
        value: 1
      }]
    },
    {
      compartmentId: $compartment,
      namespace: "sli_tracker_manual",
      name: "sli",
      dimensions: {
        source: "manual",
        path: "oci-cli",
        window: "30min"
      },
      datapoints: [{
        timestamp: $ts,
        value: $sli
      }]
    }
  ]')"

oci monitoring metric-data post \
  --endpoint "$OCI_MONITORING_ENDPOINT" \
  --metric-data "$METRIC_PAYLOAD" \
  --batch-atomicity ATOMIC \
  | jq
```

Open the OCI Console, then go to Metric Explorer and verify that both metrics are available.

## 4. Injection tools and Router Hands-On

As you learnt log and metric injection is not complex, however demanding from configuration point of view. To make operation easier this project provides facilitators for CLI, GitHub workflows. On the other hand reception of events e.g. GitGub webhooks requires automation - receiving service is a must to handle this traffic. As GitHub emits many different events, that we would like to classify and potentially handle in different ways a kind of configurable element must be in place. Here it comes to transformer and router, that can classify incoming messages, transform as needed and forwards to destination systems.

### 4.1 GitHub Actions SLI Track

GitHub workflows call local actions under [`.github/actions`](../.github/actions). Those actions assemble a structured payload describing a workflow run, its outcome, and failure reasons. The payload can then be pushed to OCI Logging and OCI Monitoring using OCI CLI or direct API call. The latter technique uses `curl` to directly access OCI API.

Core files:

- [`.github/actions/sli-event-js/action.yml`](../.github/actions/sli-event-js/action.yml)
- [`.github/actions/sli-event/emit.sh`](../.github/actions/sli-event/emit.sh)
- [`.github/actions/sli-event/emit_curl.sh`](../.github/actions/sli-event/emit_curl.sh)
- [`.github/actions/sli-event/emit_oci.sh`](../.github/actions/sli-event/emit_oci.sh)

### 4.2 Router and Ingest Track

Incoming JSON payloads can be identified, transformed, and routed to multiple destinations. This part of the project is transport-agnostic at the routing-definition level, then implemented through adapters for file output, OCI Object Storage, OCI Monitoring, and OCI Logging. Routing is defined by a custom data structure shared by CLI and Fn execution, and the transformation uses JSONata mappings.

The main implementation area for this part of the project is [`./tools`](../tools). Router logic, transformer logic, runtime wiring, and adapter code should be understood from the `tools/` tree first. Other locations are deployment-side shadow copies or links used by the OCI Function packaging.

The main layers in this area are:

- router and transformer logic
- CLI execution
- Fn execution
- adapters for concrete sources and destinations

From an operator point of view, this track answers four practical questions:

- how to recognize one incoming message type
- how to reshape it into a destination-specific contract
- how to send it to one destination or fan it out to many destinations
- how to configure source and destination behavior without changing router code

The router CLI is the easiest way to learn this track locally. In Sprint 29 it became a real execution tool, not just a route-preview helper, so a single-envelope run now performs the same match, transform, and delivery flow as batch mode.

#### Router CLI Contract

The basic CLI forms are:

```bash
node tools/json_router_cli.js --routing <file> [--input <file>] [--pretty]
cat envelope.json | node tools/json_router_cli.js --routing <file>
node tools/json_router_cli.js --routing <file> --source-dir <dir> --output-dir <dir> [--pretty]
```

The main operator modes are:

- route one envelope from a local file
- route one envelope from `stdin`
- inspect human-readable result JSON with `--pretty`
- run bulk routing from `--source-dir` to `--output-dir`
- execute one source declared inside `routing.json`

The runtime behind those modes can currently deliver to:

- `file_system`
- `oci_object_storage`
- `oci_logging`
- `oci_monitoring`

#### Capability 1: Route One Envelope from a File or `stdin`

The first practical skill is to run one envelope through real delivery. The operator can pass the envelope through `--input` or through standard input. Both modes execute the same route match, transformation, and destination delivery.

At minimum, the operator needs:

- one envelope
- one route
- one mapping
- one destination

The route can stay logically simple:

```json
{
  "id": "audit_to_file",
  "match": {
    "required_fields": ["audit.id"]
  },
  "transform": {
    "mapping": "./mapping_file.jsonata"
  },
  "destination": {
    "type": "file_system",
    "name": "audit_copy"
  }
}
```

This is the most direct way to validate that:

- the route match works
- the mapping executes
- the destination adapter performs a real write

#### Capability 1A: Influence Adapter Behavior with Labeling

The route destination is a logical label. The actual adapter behavior is configured separately in `adapters`.

This is why a route can stay stable as:

```json
{
  "destination": {
    "type": "file_system",
    "name": "audit_copy"
  }
}
```

while the actual write location is controlled through:

```json
{
  "adapters": {
    "file_system:audit_copy": {
      "directory": "out/custom_audit_location"
    }
  }
}
```

This separation matters because the route expresses intent, while the adapter configuration expresses local or production deployment behavior. The same model works for file paths, buckets, monitoring namespaces, and log targets.

#### Capability 2: Understand Envelope, Body, and Mapping Context

The runtime model behind the CLI is consistent:

- route matching sees the full envelope, for example `headers` and `body`
- JSONata transformation runs on `envelope.body`
- `adapters` configures both source adapters and destination adapters

That means a route match can inspect:

```json
{
  "headers": {
    "X-GitHub-Event": "workflow_run"
  }
}
```

while the mapping should read fields as:

```jsonata
{
  "repo": repository.full_name,
  "outcome": workflow_run.conclusion
}
```

not:

```jsonata
{
  "repo": body.repository.full_name
}
```

This detail is important because operators often debug routing problems by checking whether the failure is in route matching or in mapping context.

#### Capability 3: Batch Routing and Source-Declared Execution

The next level is to stop thinking about one envelope and start thinking about one source of envelopes.

For interactive learning and debugging, operators should usually add `--pretty` so the returned route result is easy to inspect before checking the delivered files or OCI targets.

The CLI supports two local execution patterns here:

- `--source-dir` with `--output-dir` for batch file routing
- `source` declared inside `routing.json` for runtime-driven execution without `--input`

The batch case is useful when the operator wants to send many local envelopes through the same routing definition and inspect the full output tree. This is where fanout and dead-letter behavior become visible.

The source-declared case is useful when the routing definition itself says where input comes from. In that mode:

- `source` selects the logical input
- `adapters["file_system:incoming"]` configures the source adapter
- `adapters["file_system:audit_copy"]` configures the destination adapter

That is the first point where the operator can see clearly that the `adapters` section is shared by both source and target configuration.

#### Production-Level Capabilities

The same router model also covers production-oriented behavior beyond local file delivery.

The key capabilities are:

- load `routing.json` from a remote location in the deployed Function path
- load mapping definitions from OCI Object Storage
- deliver to OCI Logging, OCI Monitoring, and OCI Object Storage
- dead-letter unmatched or failed deliveries in a controlled location

In the local CLI, `--routing` still points to a local file. In the deployed ingest path, the router configuration can instead be resolved from OCI Object Storage. This lets the operator change routing behavior without rebuilding code.

Mappings can also come from OCI Object Storage. That gives the operator the same separation one level deeper:

- code provides runtime behavior
- `routing.json` provides route policy
- remote mapping objects provide destination-specific transformation logic

That same separation is what lets the same routing model work locally with file adapters and later in production with OCI Logging, OCI Monitoring, or OCI Object Storage.

Two diagrams below show the same router from two angles. `Router` is the structural view of the major parts.

<p align="center"><img src="../model/router.jpg" alt="Router structural view" width="50%"></p>

`Router runtime` is the behavioral view of how input, route matching, transformation, and destination dispatch execute together.

<p align="center"><img src="../model/router_runtime.jpg" alt="Router runtime behavioral view" width="50%"></p>

Core files:

- [`tools/json_router.js`](../tools/json_router.js)
- [`tools/json_transformer.js`](../tools/json_transformer.js)
- [`tools/json_router_cli.js`](../tools/json_router_cli.js)
- Fn execution starting point: [`fn/router_passthrough/func.js`](../fn/router_passthrough/func.js)

Adapter code for sources:

- [`file_source_adapter.js`](../tools/adapters/file_source_adapter.js)
- [`oci_object_storage_source_adapter.js`](../tools/adapters/oci_object_storage_source_adapter.js)

Adapter code is under for destinations:

- [`file_adapter.js`](../tools/adapters/file_adapter.js)
- [`oci_object_storage_adapter.js`](../tools/adapters/oci_object_storage_adapter.js)
- [`oci_monitoring_adapter.js`](../tools/adapters/oci_monitoring_adapter.js)
- [`oci_logging_adapter.js`](../tools/adapters/oci_logging_adapter.js)

The operator cookbook in §11.4 (Local Transformation and Routing CLI) shows the same track as hands-on CLI work with complete, runnable bash examples:

- one-envelope local routing
- `stdin` routing
- pretty-printed result inspection
- batch routing
- source-declared execution
- production-oriented OCI mapping and destination examples

### 4.3 SLI Calculation Track

The project includes tools that compute rolling-window SLI values from OCI Monitoring metrics. This is the as simple as possible analytical part of the system: it reads collected telemetry and derives higher-level service indicators from it. Simplicity here comes from both a calculation method, and execution, that uses GitHub workflow scheduling.

Core files:

- [`.github/workflows/sli_compute_sli_metrics.yml`](../.github/workflows/sli_compute_sli_metrics.yml)
- [`tools/sli_compute_sli_metrics.js`](../tools/sli_compute_sli_metrics.js)

### 4.4 Synthetic Event Generator Track

The project also includes tools that generate controlled synthetic outcome streams. These tools are used to validate dashboards, alerts, routing behavior, and SLI calculations under known conditions. On this stage it's a tool to generate synthetic data on a non production platform, however in the future similar technique will be used to push data to a system in an idle period, when users are not generating any traffic.

Core files:

- [`tools/sli_ratio_simulator.sh`](../tools/sli_ratio_simulator.sh)
- [`.github/workflows/sli_ratio_simulator.yml`](../.github/workflows/sli_ratio_simulator.yml)

### 4.5 `SLI_TEST` Profile and Test Authentication

`SLI_TEST` is the default test OCI profile used by this repository. It is part of the test framework and is closely related to the GitHub Action [`.github/actions/oci-profile-setup`](../.github/actions/oci-profile-setup).

By default, `SLI_TEST` is a token-based profile prepared for operator-assisted test sessions. The usual flow is browser-based authentication through OCI CLI session login, then packing the resulting OCI configuration and session files into the GitHub secret `OCI_CONFIG_PAYLOAD`. This mode is convenient for shorter assisted test sessions, typically below 60 minutes, because the session token expires and must be refreshed.

For longer-running tests, the same setup flow also supports mirroring the current `DEFAULT` profile into `SLI_TEST`. In this mode the source profile uses regular API-key access instead of a short-lived browser session token. This is handled by `setup_oci_github_access.sh` with `--account-type config_profile`, where the source profile is usually `DEFAULT` and the destination profile stored for CI remains `SLI_TEST`.

The practical meaning is:

- `SLI_TEST` is the standard profile name expected by tests and workflows
- short assisted test sessions usually use token-based browser authentication
- longer-running tests can use a mirrored API-key profile under the same `SLI_TEST` name
- the profile is restored on runners by the `oci-profile-setup` GitHub Action

Core files:

- [`.github/actions/oci-profile-setup/action.yml`](../.github/actions/oci-profile-setup/action.yml)
- [`.github/actions/oci-profile-setup/oci_profile_setup.sh`](../.github/actions/oci-profile-setup/oci_profile_setup.sh)
- [`.github/actions/oci-profile-setup/setup_oci_github_access.sh`](../.github/actions/oci-profile-setup/setup_oci_github_access.sh)
- [`.github/actions/oci-profile-setup/README.md`](../.github/actions/oci-profile-setup/README.md)

## 5. Major Techniques Used in This Project

This section names the main technical patterns a reader needs to understand.

### 5.1 Structured Event Emission from GitHub Actions

The project treats GitHub workflow runs as telemetry sources. Rather than logging plain text, it builds structured JSON payloads containing:

- workflow identity
- repository and ref metadata
- run outcome
- optional domain-specific inputs
- failure reasons derived from failed steps

This is the core observability technique of the repository.

### 5.2 Backend-Switchable OCI Emission

Emission is not tied to one transport implementation. The repository supports multiple backend styles:

- OCI CLI based emission
- curl plus request-signing emission
- JavaScript action based post-step emission

This keeps the payload contract stable while allowing transport changes. It may be beneficial to fully switch to core API accessible via `curl` or Node.js SDK, as it eliminates OCI CLI and python installation steps what saves pipeline execution time.

### 5.3 Telemetry Sinks

The same logical event can be sent to more than one destination:

- OCI Logging for searchable raw events
- OCI Monitoring for numeric metrics
- OCI Object Storage Bucket for debug and further use cases.

This is important because logs are better for audit and search, while metrics are better for ratio calculation and alerting. Platform comes with pluggable adapter interface, enabling new sources and destination to be added.

### 5.4 JSONata Transformation

JSONata expressions are used to transform one JSON document into another. This lets the project convert source-specific payloads into destination-specific contracts without hardcoding every variation in application logic.

Relevant files:

- [`tools/json_transform_cli.js`](../tools/json_transform_cli.js)
- [`tools/mappings/github_workflow_run_to_oci_log.jsonata`](../tools/mappings/github_workflow_run_to_oci_log.jsonata)
- [`tools/mappings/health_to_oci_metric.jsonata`](../tools/mappings/health_to_oci_metric.jsonata)

### 5.5 Config-Driven Routing

The router identifies payload type, chooses a mapping, and dispatches to one or more destinations based on configuration. This allows new flows to be added by editing routing definitions and mappings instead of rewriting the runtime.

Key concepts:

- source identification
- exclusive versus fanout routing
- destination abstraction
- adapter registration from config
- dead-letter handling for failures

### 5.6 Adapter-Based Delivery

Destination-specific behavior is isolated behind adapters. This is a major design technique in the repo because it separates routing logic from side effects.

Examples:

- file adapter
- OCI Object Storage adapter
- OCI Monitoring adapter
- OCI Logging adapter

### 5.7 OCI Function as Public Ingest Endpoint

The project includes an OCI Function deployment that accepts public traffic through API Gateway and performs routing plus delivery. This is the bridge between external event producers and OCI-hosted telemetry storage.

### 5.8 Test-First Quality Gates

The repo uses centralized shell-driven test execution with suite and component scoping. Tests are grouped by level:

- smoke
- unit
- integration

The test runner supports manifest-based filtering and component-scoped regression, which matters because the repo now contains several semi-independent domains.

Relevant files:

- [`tests/run.sh`](../tests/run.sh)
- [`tests/manifests/component_router.manifest`](../tests/manifests/component_router.manifest)
- [`tests/unit/README.md`](../tests/unit/README.md)
- [`tests/integration/README.md`](../tests/integration/README.md)

### 5.9 Infrastructure Lifecycle Scripts

OCI resources are not assumed to exist forever. The repository contains helper scripts to create, validate, and tear down test infrastructure in a repeatable way.

This includes:

- OCI log and compartment setup
- Function resource policies
- API Gateway router deployment lifecycle
- bucket cleanup and validation helpers

## 6. Major Tools and Components

This section is a compact inventory of the most important building blocks.

### 6.1 GitHub Actions Components

- `install-oci-cli`
  Purpose: install OCI CLI on GitHub runners.
- `oci-profile-setup`
  Purpose: prepare OCI auth material for local or CI usage.
- `sli-event`
  Purpose: build and emit SLI payloads from shell-based action logic.
- `sli-event-js`
  Purpose: emit via JavaScript action lifecycle hooks.

### 6.2 Workflow Models

The workflows under [`.github/workflows`](../.github/workflows) serve two roles:

1. realistic examples of GitHub pipeline patterns
2. test fixtures for SLI instrumentation

Representative workflows:

- `model-push.yml`
- `model-pr.yml`
- `model-call.yml`
- `model-emit-curl.yml`
- `model-emit-js.yml`
- `sli_compute_sli_metrics.yml`
- `sli_ratio_simulator.yml`

### 6.3 Node.js Tooling

The root [package.json](../package.json) shows the key libraries:

- `jsonata`
- `ajv`
- `oci-common`
- `oci-loggingingestion`
- `oci-monitoring`
- `oci-objectstorage`

In practice, Node.js is used for:

- JSON routing and transformation logic
- OCI adapter implementations
- SLI metric computation
- CLI tools for local validation

### 6.4 Shell Tooling

Shell remains a first-class implementation language in this repo.

It is used for:

- GitHub Action runtime scripts
- environment setup
- OCI auth packaging
- integration tests
- simulator control flow
- OCI deployment helpers

### 6.5 OCI-Focused Helpers

Important helpers under [`tools/`](../tools):

- [`ensure_oci_resources.sh`](../tools/ensure_oci_resources.sh)
- [`cycle_apigw_router_passthrough.sh`](../tools/cycle_apigw_router_passthrough.sh)
- [`validate_router_ingest_and_metrics.sh`](../tools/validate_router_ingest_and_metrics.sh)
- [`list_monitoring_metrics.sh`](../tools/list_monitoring_metrics.sh)
- [`list_github_ingest_prefixes.sh`](../tools/list_github_ingest_prefixes.sh)
- [`get_ingest_object.sh`](../tools/get_ingest_object.sh)

### 6.6 OCI Function Router Components

Important files under [`fn/router_passthrough/`](../fn/router_passthrough):

- `func.js`
- `router_core.js`
- `lib/json_router.js`
- `lib/json_transformer.js`
- `lib/destination_dispatcher.js`
- `lib/oci_object_storage_adapter.js`
- `lib/oci_monitoring_adapter.js`
- `lib/oci_logging_adapter.js`
- `lib/schemas/json_router_definition.schema.json`

## 7. Repository Areas and Their Roles

| Area | Role |
|------|------|
| `.github/actions/` | GitHub Action implementations used by workflows |
| `.github/workflows/` | Example and test workflows that emit telemetry |
| `tools/` | Local CLIs, helpers, adapters, and OCI utility scripts |
| `fn/router_passthrough/` | Deployable OCI Function router runtime |
| `tests/` | Centralized smoke, unit, integration, and manifest-based test execution |
| `oci_scaffold/` | OCI resource lifecycle support submodule |
| `progress/` | Sprint-by-sprint implementation trace and test evidence |
| `RUPStrikesBack/` | Delivery process, rules, and agent workflow submodule |

## 8. Operational Knowledge a Reader Should Gain

By the time a reader finishes the first part of this manual, they should be able to answer these questions:

1. What counts as an SLI event in this repo?
2. Which parts emit events, and which parts route them?
3. When should Logging be used versus Monitoring?
4. How are transformations expressed?
5. How does the router choose a destination?
6. Which tests are local-only and which tests require live OCI and GitHub access?
7. Which scripts are used to stand infrastructure up and tear it down?

These questions will later map to deeper chapters.

## 9. Suggested Reading Order

For a new maintainer, this is the recommended order:

1. [`README.md`](../README.md)
2. [`.github/workflows/README.md`](../.github/workflows/README.md)
3. [`.github/actions/README.md`](../.github/actions/README.md)
4. [`tests/unit/README.md`](../tests/unit/README.md)
5. [`tests/integration/README.md`](../tests/integration/README.md)
6. [`PLAN.md`](../PLAN.md)
7. [`PROGRESS_BOARD.md`](../PROGRESS_BOARD.md)

Then continue with the code paths that match the reader's focus:

- emission path
- router path
- OCI deployment path
- testing path

## 10. Known Knowledge Domains for Future Expansion

The next iterations of this manual should likely add dedicated chapters for:

1. event schema and payload anatomy
2. OCI authentication models used by the project
3. router configuration model and mapping files
4. Function deployment flow and required OCI resources
5. test strategy and quality gates
6. troubleshooting and failure modes
7. sprint history and why the architecture evolved the way it did

## 11. Snippet Catalog

This section is intentionally placed at the bottom so it can grow into a practical operator cookbook.

Unless noted otherwise, run the commands below from the repository root. The manual file lives in `docs/`, but the snippets use repository-root relative paths such as `tools/`, `tests/`, `.github/`, and `progress/`.

Each snippet should eventually include:

- scenario
- prerequisites
- command
- expected outcome
- follow-up checks

### 11.1 Prepare `SLI_TEST` Authentication

Most local OCI examples below use `"profile":"SLI_TEST"` inside `SLI_CONTEXT_JSON`. That profile is prepared by the operator-side script [`.github/actions/oci-profile-setup/setup_oci_github_access.sh`](../.github/actions/oci-profile-setup/setup_oci_github_access.sh).

After a successful run, local commands can use `~/.oci/config` with profile `SLI_TEST`. On GitHub runners, the paired restore action [`.github/actions/oci-profile-setup/oci_profile_setup.sh`](../.github/actions/oci-profile-setup/oci_profile_setup.sh) unpacks that same profile from `OCI_CONFIG_PAYLOAD`.

#### Session-Based `SLI_TEST` Profile

Use this mode when you want browser-authenticated OCI access. The script runs `oci session authenticate` and creates an authenticated `SLI_TEST` session profile.

```bash
.github/actions/oci-profile-setup/setup_oci_github_access.sh \
  --account-type session \
  --profile DEFAULT \
  --session-profile-name SLI_TEST \
  --repo "$(gh repo view --json nameWithOwner -q .nameWithOwner)"
```

#### API-Key Mirrored `SLI_TEST` Profile

Use this mode when you want a non-expiring API-key based `SLI_TEST` profile. The script copies an existing local profile such as `DEFAULT` into `SLI_TEST` and packs the key material into the GitHub secret.

```bash
.github/actions/oci-profile-setup/setup_oci_github_access.sh \
  --account-type config_profile \
  --profile DEFAULT \
  --session-profile-name SLI_TEST \
  --repo "$(gh repo view --json nameWithOwner -q .nameWithOwner)"
```

### 11.2 Local SLI Emission

#### Emit one success event locally

```bash
repo=$(gh repo view --json nameWithOwner -q .nameWithOwner)
export SLI_METRIC_COMPARTMENT="$(gh variable get SLI_OCI_COMPARTMENT_ID -R "$repo")"
export SLI_OCI_LOG_ID="$(gh variable get SLI_OCI_LOG_ID -R "$repo")"
export EMIT_BACKEND=curl
export EMIT_TARGET=log,metric
export SLI_OUTCOME=success
export SLI_CONTEXT_JSON='{"oci":{"config-file":"~/.oci/config","profile":"SLI_TEST"}}'
bash .github/actions/sli-event/emit.sh
```

#### Emit one failure event locally

```bash
repo=$(gh repo view --json nameWithOwner -q .nameWithOwner)
export SLI_METRIC_COMPARTMENT="$(gh variable get SLI_OCI_COMPARTMENT_ID -R "$repo")"
export SLI_OCI_LOG_ID="$(gh variable get SLI_OCI_LOG_ID -R "$repo")"
export EMIT_BACKEND=oci-cli
export EMIT_TARGET=log,metric
export SLI_OUTCOME=failure
export STEPS_JSON='{"test_script":{"outcome":"failure","outputs":{}}}'
export SLI_CONTEXT_JSON='{"oci":{"config-file":"~/.oci/config","profile":"SLI_TEST"}}'
bash .github/actions/sli-event/emit.sh
```

### 11.3 SLI Simulation and Computation

#### Run the ratio simulator

This is a live emission example. It uses the same OCI setup as the local emit examples above, so define the OCI target and auth context first, then start the simulator.

```bash
repo=$(gh repo view --json nameWithOwner -q .nameWithOwner)
export SLI_METRIC_COMPARTMENT="$(gh variable get SLI_OCI_COMPARTMENT_ID -R "$repo")"
export SLI_OCI_LOG_ID="$(gh variable get SLI_OCI_LOG_ID -R "$repo")"
export EMIT_BACKEND=curl
export EMIT_TARGET=log,metric
export SLI_METRIC_NAMESPACE="sli_tracker"
export SLI_CONTEXT_JSON='{"oci":{"config-file":"~/.oci/config","profile":"SLI_TEST"}}'

tools/sli_ratio_simulator.sh \
  --target-failure-rate 0.95 \
  --ramp-seconds 120 \
  --hold-seconds 120 \
  --teardown-seconds 120 \
  --interval-seconds 5 \
  --ramp-curve logarithmic \
  --teardown-curve exponential \
  --seed 42
```

#### Compute SLI from OCI Monitoring

```bash
tools/sli_compute_sli_metrics.js \
  --oci-auth config \
  --window-days 30 \
  --mql-resolution 1d \
  --namespace sli_tracker \
  --metric-name outcome \
  --compartment-id "$COMPARTMENT_OCID" \
  --oci-config-file "~/.oci/config" \
  --oci-profile "SLI_TEST" \
  --output json | jq
```

### 11.4 Local Transformation and Routing CLI

`json_transform_cli.js` changes one JSON document into another. `json_router_cli.js` takes the next step: it matches the input against routes, runs the selected mapping, and executes the destination delivery. Since Sprint 29, this is true for single-envelope runs too, not only for batch mode.

#### Transform from stdin

```bash
echo '{"value":21}' | 
node tools/json_transform_cli.js \
  --mapping <(echo '{"expression":"{\"out\": value * 2}"}') \
  --pretty
```

#### Transform local JSON file with a local mapping file

```bash
node tools/json_transform_cli.js \
  --mapping tests/fixtures/transformer/ut20_ut21_ut22_cli_basic/mapping.jsonata \
  --input tests/fixtures/transformer/ut20_ut21_ut22_cli_basic/source.json \
  --pretty
```

#### Router CLI contract

```bash
node tools/json_router_cli.js --routing <file> [--input <file>] [--pretty]
cat envelope.json | node tools/json_router_cli.js --routing <file>
node tools/json_router_cli.js --routing <file> --source-dir <dir> --output-dir <dir> [--pretty]
```

Options:

- `--routing`
  Required. Path to `routing.json`.
- `--input`
  Optional. One envelope JSON file. If omitted, the CLI reads `stdin`.
- `--source-dir`
  Optional. Batch source directory.
- `--output-dir`
  Optional. Batch output directory.
- `--pretty`
  Optional. Pretty-print the result JSON.
- `--help`
  Show usage.

The router CLI supports four main operator modes:

1. route one envelope from a local file
2. route one envelope from `stdin`
3. run batch routing from `--source-dir` to `--output-dir`
4. execute a source declared inside `routing.json` without `--input`

The runtime behind the CLI can use these destination types:

- `file_system`
- `oci_object_storage`
- `oci_logging`
- `oci_monitoring`

The runtime can also load mappings from:

- local files
- OCI Object Storage, when `routing.json` declares `mapping.type = "oci_object_storage"`

#### Router CLI result shape

For one routed envelope, the CLI returns a structure like:

```json
{
  "status": "routed",
  "deliveries": [
    {
      "route": {
        "id": "audit_to_file",
        "mode": "exclusive",
        "destination": {
          "type": "file_system",
          "name": "audit_copy"
        }
      },
      "output": {
        "audit": {
          "id": "A-1"
        }
      }
    }
  ]
}
```

For batch routing, the CLI returns a summary like:

```json
{
  "processed": 4,
  "results": [
    {
      "file": "001.json",
      "route": "workflow_metric",
      "destination": "file_system/workflow_status",
      "output_path": "/tmp/..."
    }
  ]
}
```

#### Capability 1: route one local envelope from a file and inspect the delivered file

```bash
TMP_DIR="$(mktemp -d /tmp/sli_router_single.XXXXXX)"
echo '$' > "$TMP_DIR/mapping_file.jsonata"
cat > "$TMP_DIR/envelope.json" <<'EOF'
{
  "body": {
    "audit": {
      "id": "A-1",
      "message": "copied to file adapter"
    }
  }
}
EOF

cat > "$TMP_DIR/routing.json" <<'EOF'
{
  "routes": [
    {
      "id": "audit_to_file",
      "match": {
        "required_fields": ["audit.id"]
      },
      "transform": {
        "mapping": "./mapping_file.jsonata"
      },
      "destination": {
        "type": "file_system",
        "name": "audit_copy"
      }
    }
  ]
}
EOF

node tools/json_router_cli.js \
  --routing "$TMP_DIR/routing.json" \
  --input "$TMP_DIR/envelope.json" \
  --pretty

cat "$TMP_DIR/file_system/audit_copy/001_audit_to_file.json" | jq
```

Expected operator understanding:

- the route match is evaluated
- the mapping is executed
- the file is really written under `file_system/audit_copy/`

#### Capability 1A: influence adapter behavior with destination labeling

The route destination is a logical label:

```json
{
  "type": "file_system",
  "name": "audit_copy"
}
```

The actual adapter behavior can then be changed through the `adapters` section. For `file_system`, the key format is:

`file_system:<name>`

This lets the operator keep the same route label but redirect the write location.

```bash
TMP_DIR="$(mktemp -d /tmp/sli_router_labeling.XXXXXX)"
echo '$' > "$TMP_DIR/mapping_file.jsonata"
cat > "$TMP_DIR/envelope.json" <<'EOF'
{
  "body": {
    "audit": {
      "id": "A-1",
      "message": "written through labeled adapter"
    }
  }
}
EOF

cat > "$TMP_DIR/routing.json" <<'EOF'
{
  "adapters": {
    "file_system:audit_copy": {
      "directory": "out/custom_audit_location"
    }
  },
  "routes": [
    {
      "id": "audit_to_file",
      "match": {
        "required_fields": ["audit.id"]
      },
      "transform": {
        "mapping": "./mapping_file.jsonata"
      },
      "destination": {
        "type": "file_system",
        "name": "audit_copy"
      }
    }
  ]
}
EOF

node tools/json_router_cli.js \
  --routing "$TMP_DIR/routing.json" \
  --input "$TMP_DIR/envelope.json" \
  --pretty

cat "$TMP_DIR/out/custom_audit_location/001_audit_to_file.json" | jq
```

Operator meaning:

- the route still says `file_system / audit_copy`
- the adapter label `file_system:audit_copy` decides where that logical destination really writes
- this is the main way to keep route intent stable while changing local target behavior

#### Capability 2: route one local envelope from stdin

Use this when the envelope is produced by another command or shell pipeline.

```bash
TMP_DIR="$(mktemp -d /tmp/sli_router_stdin.XXXXXX)"
echo '$' > "$TMP_DIR/mapping_file.jsonata"

cat > "$TMP_DIR/routing.json" <<'EOF'
{
  "routes": [
    {
      "id": "audit_to_file",
      "match": {
        "required_fields": ["audit.id"]
      },
      "transform": {
        "mapping": "./mapping_file.jsonata"
      },
      "destination": {
        "type": "file_system",
        "name": "audit_copy"
      }
    }
  ]
}
EOF

cat <<'EOF' | node tools/json_router_cli.js \
      --routing "$TMP_DIR/routing.json" \
      --pretty
{
  "body": {
    "audit": {
      "id": "A-1",
      "message": "copied to file adapter"
    }
  }
}
EOF

cat "$TMP_DIR/file_system/audit_copy/001_audit_to_file.json" | jq
```

Notice that the output file is auto-numbered. In this example it is `001` because the router writes into a fresh directory.

#### Capability 3: pretty output and mapping context

Use `--pretty` when you want human-readable result JSON.

```bash
TMP_DIR="$(mktemp -d /tmp/sli_router_pretty.XXXXXX)"
cat > "$TMP_DIR/mapping_log.jsonata" <<'EOF'
{
  "kind": "log",
  "repo": repository.full_name,
  "outcome": workflow_run.conclusion
}
EOF

cat > "$TMP_DIR/envelope.json" <<'EOF'
{
  "headers": {
    "X-GitHub-Event": "workflow_run"
  },
  "body": {
    "workflow_run": {
      "conclusion": "success"
    },
    "repository": {
      "full_name": "acme/repo"
    }
  }
}
EOF

cat > "$TMP_DIR/routing.json" <<'EOF'
{
  "routes": [
    {
      "id": "workflow_to_log_shape",
      "match": {
        "headers": {
          "X-GitHub-Event": "workflow_run"
        }
      },
      "transform": {
        "mapping": "./mapping_log.jsonata"
      },
      "destination": {
        "type": "file_system",
        "name": "workflow_logs"
      }
    }
  ]
}
EOF

node tools/json_router_cli.js \
  --routing "$TMP_DIR/routing.json" \
  --input "$TMP_DIR/envelope.json" \
  --pretty

cat "$TMP_DIR/file_system/workflow_logs/001_workflow_to_log_shape.json" | jq
```

Note about mapping context. The CLI reads a full envelope, for example with `headers` and `body`, and route matching can use the full envelope. However JSONata transformation runs on `envelope.body`, not on the whole envelope. That is why the mapping uses `repository.full_name` and `workflow_run.conclusion`, not `body.repository.full_name`.

Without `--pretty`, the output is compact JSON and easier to pipe into other commands.

#### Capability 4: route a local source directory to a local output directory

This example runs three source files through the router in batch mode. Expect one workflow event to fan out into two output files, one health event to produce one metric-style output file, and one unknown event to land in `dead_letter/errors/`.

```bash
OUT_DIR="$(mktemp -d /tmp/sli_router_batch.XXXXXX)"
SRC_DIR="$(mktemp -d /tmp/sli_router_batch_source.XXXXXX)"
ROUTING_DIR="$(mktemp -d /tmp/sli_router_batch_routing.XXXXXX)"

cat > "$SRC_DIR/001_workflow_run.json" <<'EOF'
{
  "headers": {
    "X-GitHub-Event": "workflow_run"
  },
  "body": {
    "schema": "github.workflow_run",
    "workflow_run": {
      "conclusion": "success"
    },
    "repository": {
      "full_name": "org/app"
    }
  }
}
EOF

cat > "$SRC_DIR/002_health.json" <<'EOF'
{
  "endpoint": "/health",
  "body": {
    "service": "payments",
    "status": "ok"
  }
}
EOF

cat > "$SRC_DIR/003_unknown.json" <<'EOF'
{
  "body": {
    "message": "unknown payload"
  }
}
EOF

cat > "$ROUTING_DIR/mapping_generic.jsonata" <<'EOF'
{
  "kind": "generic",
  "repo": repository.full_name
}
EOF

cat > "$ROUTING_DIR/mapping_specific.jsonata" <<'EOF'
{
  "kind": "specific",
  "repo": repository.full_name,
  "schema": schema
}
EOF

cat > "$ROUTING_DIR/mapping_metric.jsonata" <<'EOF'
{
  "metric": "workflow_outcome",
  "repo": repository.full_name,
  "value": workflow_run.conclusion = "success" ? 1 : 0
}
EOF

cat > "$ROUTING_DIR/mapping_health.jsonata" <<'EOF'
{
  "metric": "health_status",
  "service": service,
  "value": status = "ok" ? 1 : 0
}
EOF

cat > "$ROUTING_DIR/routing.json" <<'EOF'
{
  "dead_letter": {
    "type": "dead_letter",
    "name": "errors"
  },
  "routes": [
    {
      "id": "generic_workflow",
      "mode": "exclusive",
      "priority": 100,
      "match": {
        "headers": {
          "X-GitHub-Event": "workflow_run"
        }
      },
      "transform": {
        "mapping": "./mapping_generic.jsonata"
      },
      "destination": {
        "type": "normalized_event",
        "name": "generic"
      }
    },
    {
      "id": "specific_workflow",
      "mode": "exclusive",
      "priority": 200,
      "match": {
        "headers": {
          "X-GitHub-Event": "workflow_run"
        },
        "schema": {
          "path": "schema",
          "equals": "github.workflow_run"
        }
      },
      "transform": {
        "mapping": "./mapping_specific.jsonata"
      },
      "destination": {
        "type": "oci_log",
        "name": "specific_events"
      }
    },
    {
      "id": "workflow_metric",
      "mode": "fanout",
      "match": {
        "headers": {
          "X-GitHub-Event": "workflow_run"
        }
      },
      "transform": {
        "mapping": "./mapping_metric.jsonata"
      },
      "destination": {
        "type": "oci_metric",
        "name": "workflow_status"
      }
    },
    {
      "id": "health_endpoint",
      "mode": "exclusive",
      "priority": 50,
      "match": {
        "endpoint": "/health"
      },
      "transform": {
        "mapping": "./mapping_health.jsonata"
      },
      "destination": {
        "type": "oci_metric",
        "name": "health_signal"
      }
    }
  ]
}
EOF

node tools/json_router_cli.js \
  --routing "$ROUTING_DIR/routing.json" \
  --source-dir "$SRC_DIR" \
  --output-dir "$OUT_DIR" \
  | jq

find "$OUT_DIR" -type f | sort
```

What this mode adds:

- the CLI reads many files
- each item is routed independently
- result JSON includes a processed count and per-file results
- files that do not match or fail can go to dead-letter output

Expected behavior for this example:

- one workflow item fans out to two files
- one health item produces one output file
- one unknown item lands in `dead_letter/errors/`

#### Capability 5: execute a source declared in `routing.json`

If `routing.json` declares a `source`, the CLI can execute end-to-end without `--input` and without shell piping. This is not the webhook reception mode, which uses `stdin`, but it is useful for autonomous batch-style processing and validates that the source-adapter model works above the file wrapper.

Supported source types:

- `file_system`
- `oci_object_storage`

Minimal local file-system source example:

```bash
TMP_DIR="$(mktemp -d /tmp/sli_router_source_mode.XXXXXX)"
mkdir -p "$TMP_DIR/in"
echo '$' > "$TMP_DIR/mapping_file.jsonata"
cat > "$TMP_DIR/in/audit.json" <<'EOF'
{
  "body": {
    "audit": {
      "id": "A-1",
      "message": "copied to file adapter"
    }
  }
}
EOF

cat > "$TMP_DIR/routing.json" <<'EOF'
{
  "source": {
    "type": "file_system",
    "name": "incoming"
  },
  "adapters": {
    "file_system:incoming": { "directory": "in" },
    "file_system:audit_copy": { "directory": "out/audit" }
  },
  "routes": [
    {
      "id": "audit_to_file",
      "match": { "required_fields": ["audit.id"] },
      "transform": { "mapping": "./mapping_file.jsonata" },
      "destination": { "type": "file_system", "name": "audit_copy" }
    }
  ]
}
EOF

(cd "$TMP_DIR" && node "$OLDPWD/tools/json_router_cli.js" --routing "$TMP_DIR/routing.json" --pretty)
find "$TMP_DIR/out" -type f | sort
```

Note about `adapters` in this mode:

- `source` selects one logical input, here `file_system / incoming`
- `adapters["file_system:incoming"]` configures how that source adapter reads input, here from directory `in`
- `adapters["file_system:audit_copy"]` configures how the destination adapter writes output, here to directory `out/audit`
- the `adapters` section is used for both source adapter configuration and target adapter configuration

Operator meaning:

- the source is resolved from the routing definition
- the CLI becomes a runtime launcher, not just a file/stdin wrapper

#### Production-level router capabilities

The same router model also supports OCI-backed behavior.

##### Load `routing.json` from a remote location

Important boundary:

- `json_router_cli.js` still expects `--routing <local-file>`
- the deployed Function runtime can load `routing.json` from OCI Object Storage

The Function runtime uses these environment variables:

- `SLI_ROUTING_BUCKET`
- `SLI_ROUTING_OBJECT`
- fallback: `OCI_INGEST_BUCKET`

Default object name:

- `config/routing.json`

Practical meaning:

- local CLI validation still uses a local `routing.json`
- deployed runtime can keep routing outside the image, so operators can update configuration without rebuilding code

##### Use OCI Object Storage as mapping source

Important boundary for the local CLI:

- `routing.json` itself is still loaded from a local file path passed to `--routing`
- only the mapping files can be loaded from OCI Object Storage in this capability

The CLI can load JSONata mappings from OCI Object Storage when the routing definition declares:

- `mapping.type = "oci_object_storage"`
- an adapter target for the mapping bucket

Operator model:

1. upload mapping files into an OCI bucket
2. point `routing.json` mapping adapter to that bucket or prefix
3. run the CLI normally
4. let the runtime fetch the mapping from OCI before route execution

##### Deliver to OCI destinations

The runtime behind the CLI supports these OCI destinations:

- `oci_object_storage`
- `oci_logging`
- `oci_monitoring`

That means the CLI can be used not only for local file exercises, but also for live OCI delivery when:

- `OCI_CLI_PROFILE` is valid
- the routing adapters contain the needed target configuration
- the mapping output shape matches the destination contract

#### Capability 6: dead-letter handling

Dead-letter behavior is especially visible in batch mode.

If `routing.json` defines `dead_letter`, failed or unreadable items are written there. If it does not, the CLI fails the run.

Practical operator meaning:

- use `dead_letter` when processing mixed-quality inputs
- omit it when you want strict fail-fast behavior

#### Capability 7: error cases you should know

These are the main CLI failure modes:

- missing `--routing`
- malformed input JSON
- batch mode with only one of `--source-dir` or `--output-dir`
- unreadable mapping
- unsupported source type
- unsupported destination configuration

The unit tests that cover these cases are:

- [`tests/unit/test_json_router_cli.sh`](../tests/unit/test_json_router_cli.sh)
- [`tests/unit/test_json_pipeline_cli.sh`](../tests/unit/test_json_pipeline_cli.sh)

#### Recommended operator progression

Use the CLI in this order:

1. single file to local `file_system`
2. `stdin` to local `file_system`
3. transform CLI piped to router CLI
4. batch `--source-dir/--output-dir`
5. source-defined runtime mode in `routing.json`
6. OCI mapping source
7. OCI destinations

That order moves from fully local and observable workflows to live OCI-backed delivery.

#### Takeaway

`json_router_cli.js` is no longer a preview tool for single-envelope runs. It is an execution tool that performs real delivery across the same routing runtime model as the Function path. That makes the CLI the best place to understand, validate, and evolve a routing definition before deploying it to OCI.

### 11.5 OCI Router Operations

#### Deploy or refresh the public router stack

```bash
export NAME_PREFIX="${SLI_FN_APIGW_ROUTER_PREFIX:-sli-router-passthrough-dev}"
export SLI_COMPARTMENT_PATH="${SLI_COMPARTMENT_PATH:-/SLI_tracker}"
export FN_FUNCTION_NAME="${FN_FUNCTION_NAME:-router_passthrough}"
export FN_FUNCTION_SRC_DIR="${FN_FUNCTION_SRC_DIR:-../fn/router_passthrough}"
export FN_ROUTER_AUTO_INGEST_BUCKET=true
export CYCLE_APIGW_TEST_EXPECT=router
export FN_FORCE_DEPLOY="${FN_FORCE_DEPLOY:-true}"

bash tools/cycle_apigw_router_passthrough.sh
```

#### Validate router ingest and metrics

```bash
export NAME_PREFIX="${SLI_FN_APIGW_ROUTER_PREFIX:-sli-router-passthrough-dev}"
export SLI_OCI_STATE_FILE="$(find . -maxdepth 2 -name "state-${NAME_PREFIX}.json" | head -1)"
[ -n "$SLI_OCI_STATE_FILE" ] || { echo "state file not found for ${NAME_PREFIX}" >&2; exit 1; }

bash tools/validate_router_ingest_and_metrics.sh --minutes 45 --limit 5
```

#### List GitHub ingest prefixes

```bash
export NAME_PREFIX="${SLI_FN_APIGW_ROUTER_PREFIX:-sli-router-passthrough-dev}"
export SLI_OCI_STATE_FILE="$(find . -maxdepth 2 -name "state-${NAME_PREFIX}.json" | head -1)"
[ -n "$SLI_OCI_STATE_FILE" ] || { echo "state file not found for ${NAME_PREFIX}" >&2; exit 1; }
export SLI_OS_NAMESPACE="$(jq -r '.bucket.namespace' "$SLI_OCI_STATE_FILE")"
export SLI_INGEST_BUCKET="$(jq -r '.bucket.name' "$SLI_OCI_STATE_FILE")"

bash tools/list_github_ingest_prefixes.sh --limit 5
```

#### POST JSON to the router endpoint and fetch the stored object

```bash
export NAME_PREFIX="${SLI_FN_APIGW_ROUTER_PREFIX:-sli-router-passthrough-dev}"
export SLI_OCI_STATE_FILE="$(find . -maxdepth 2 -name "state-${NAME_PREFIX}.json" | head -1)"
[ -n "$SLI_OCI_STATE_FILE" ] || { echo "state file not found for ${NAME_PREFIX}" >&2; exit 1; }
export SLI_OS_NAMESPACE="$(jq -r '.bucket.namespace' "$SLI_OCI_STATE_FILE")"
export SLI_INGEST_BUCKET="$(jq -r '.bucket.name' "$SLI_OCI_STATE_FILE")"

DEPLOYMENT_ENDPOINT="$(jq -r '.apigw_deployment.endpoint // .apigw.deployment_endpoint' "$SLI_OCI_STATE_FILE")"
ROUTE_PATH="$(jq -r '.inputs.apigw_route_path // "/"' "$SLI_OCI_STATE_FILE")"
URL="${DEPLOYMENT_ENDPOINT%/}/$(printf '%s' "${ROUTE_PATH#/}")"

TS="$(date -u '+%Y%m%d%H%M%S')"
OBJ="manual-${TS}.json"
PAYLOAD="$(jq -n --arg fn "$OBJ" '{body: {manual: true, marker: "manual-check"}, source_meta: {file_name: $fn}}')"

curl -sS \
  -H "content-type: application/json" \
  --data "$PAYLOAD" \
  "$URL" | jq

OBJECT_NAME="ingest/no_github_event/${OBJ}"
bash tools/get_ingest_object.sh "$OBJECT_NAME" | jq
```

#### Clear router ingest objects from the current ingest bucket

```bash
export NAME_PREFIX="${SLI_FN_APIGW_ROUTER_PREFIX:-sli-router-passthrough-dev}"
export SLI_OCI_STATE_FILE="$(find . -maxdepth 2 -name "state-${NAME_PREFIX}.json" | head -1)"
[ -n "$SLI_OCI_STATE_FILE" ] || { echo "state file not found for ${NAME_PREFIX}" >&2; exit 1; }
export SLI_OS_NAMESPACE="$(jq -r '.bucket.namespace' "$SLI_OCI_STATE_FILE")"
export SLI_INGEST_BUCKET="$(jq -r '.bucket.name' "$SLI_OCI_STATE_FILE")"

bash tools/clear_ingest_prefix.sh --dry-run
# real delete:
# bash tools/clear_ingest_prefix.sh --yes
```

### 11.6 Teardown

#### Delete the API Gateway + Fn router stack

```bash
export NAME_PREFIX="${SLI_FN_APIGW_ROUTER_PREFIX:-sli-router-passthrough-dev}"

bash tests/cleanup_router_apigw_stack.sh
```

#### Delete all `sli-*` buckets in `/SLI_tracker`

```bash
bash tests/cleanup_sli_buckets.sh
```

## 12. Supporting Source Documents

This manual is the primary operator document. Supporting sprint documents remain useful when you want historical context, implementation rationale, or detailed test evidence behind the router work.

Useful supporting documents:

- [progress/sprint_29/sprint_29_manual.md](../progress/sprint_29/sprint_29_manual.md)
- [progress/sprint_29/sprint_29_design.md](../progress/sprint_29/sprint_29_design.md)
- [progress/sprint_29/sprint_29_implementation.md](../progress/sprint_29/sprint_29_implementation.md)
- [progress/sprint_29/sprint_29_tests.md](../progress/sprint_29/sprint_29_tests.md)
