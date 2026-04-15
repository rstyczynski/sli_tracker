# SLI Tracker Manual

`SLI_tracker` is a framework for collecting, routing, storing, and evaluating Service Level Indicator data on Oracle Cloud Infrastructure. It provides tools and techniques to push service level indicators to OCI Monitoring, OCI Logging, and OCI Object Storage.

The same framework can be used beyond the GitHub Actions example implemented in this repository. The current repository is one concrete system built with these techniques, but the same pattern can be extended to other SLI sources, other telemetry domains, and other kinds of status or health information.

The framework can accept notifications from external systems, receive OCI-native events, and pull data from exposed service endpoints. In all of these cases it applies the same core flow: collect data, normalize it, route it, store it, and evaluate it.

The system model is shown below.

![SLI Tracker system model](model/model.jpg)

The editable source is [`model/model.drawio`](/Users/rstyczynski/projects/SLI_tracker/model/model.drawio).

## 1. Project Overview

`SLI_tracker` is an OCI-based SLI collection and processing framework. In this repository, the main exemplar use case is CI/CD telemetry built around GitHub Actions, but the architecture is intentionally broader than one pipeline domain.

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

## 3. First OCI Injection Examples

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

GitHub workflows call local actions under [`.github/actions`](/Users/rstyczynski/projects/SLI_tracker/.github/actions). Those actions assemble a structured payload describing a workflow run, its outcome, and failure reasons. The payload can then be pushed to OCI Logging and OCI Monitoring using OCI CLI or direct API call. The latter technique uses `curl` to directly access OCI API.

Core files:

- [`.github/actions/sli-event-js/action.yml`](/Users/rstyczynski/projects/SLI_tracker/.github/actions/sli-event-js/action.yml)
- [`.github/actions/sli-event/emit.sh`](/Users/rstyczynski/projects/SLI_tracker/.github/actions/sli-event/emit.sh)
- [`.github/actions/sli-event/emit_curl.sh`](/Users/rstyczynski/projects/SLI_tracker/.github/actions/sli-event/emit_curl.sh)
- [`.github/actions/sli-event/emit_oci.sh`](/Users/rstyczynski/projects/SLI_tracker/.github/actions/sli-event/emit_oci.sh)

### 4.2 Router and Ingest Track

Incoming JSON payloads can be identified, transformed, and routed to multiple destinations. This part of the project is transport-agnostic at the routing-definition level, then implemented through adapters for file output, OCI Object Storage, OCI Monitoring, and OCI Logging. Routing is defined by a custom - Fn execution data structure, and the transformation uses JSONata mappings.

The main implementation area for this part of the project is [`./tools`](/Users/rstyczynski/projects/SLI_tracker/tools). Router logic, transformer logic, runtime wiring, and adapter code should be understood from the `tools/` tree first. Other locations are deployment-side shadow copies or links used by the OCI Function packaging.

The main layers in this area are:

- router and transformer logic
- CLI execution
- Fn execution
- adapters for concrete sources and destinations

Two diagrams below show the same router from two angles. `Router` is the structural view of the major parts.

![Router structural view](model/router.jpg)

`Router runtime` is the behavioral view of how input, route matching, transformation, and destination dispatch execute together.

![Router runtime behavioral view](model/router_runtime.jpg)

Core files:

- [`tools/json_router.js`](/Users/rstyczynski/projects/SLI_tracker/tools/json_router.js)
- [`tools/json_transformer.js`](/Users/rstyczynski/projects/SLI_tracker/tools/json_transformer.js)
- [`tools/json_router_cli.js`](/Users/rstyczynski/projects/SLI_tracker/tools/json_router_cli.js)
- Fn execution starting point: [`fn/router_passthrough/func.js`](/Users/rstyczynski/projects/SLI_tracker/fn/router_passthrough/func.js)

Adapter code for sources:

- [`file_source_adapter.js`](/Users/rstyczynski/projects/SLI_tracker/tools/adapters/file_source_adapter.js)
- [`oci_object_storage_source_adapter.js`](/Users/rstyczynski/projects/SLI_tracker/tools/adapters/oci_object_storage_source_adapter.js)

Adapter code is under for destinations:

- [`file_adapter.js`](/Users/rstyczynski/projects/SLI_tracker/tools/adapters/file_adapter.js)
- [`oci_object_storage_adapter.js`](/Users/rstyczynski/projects/SLI_tracker/tools/adapters/oci_object_storage_adapter.js)
- [`oci_monitoring_adapter.js`](/Users/rstyczynski/projects/SLI_tracker/tools/adapters/oci_monitoring_adapter.js)
- [`oci_logging_adapter.js`](/Users/rstyczynski/projects/SLI_tracker/tools/adapters/oci_logging_adapter.js)

### 4.3 SLI Calculation Track

The project includes tools that compute rolling-window SLI values from OCI Monitoring metrics. This is the as simple as possible analytical part of the system: it reads collected telemetry and derives higher-level service indicators from it. Simplicity here comes from both a calculation method, and execution, that uses GitHub workflow scheduling.

Core files:

- [`.github/workflows/sli_compute_sli_metrics.yml`](/Users/rstyczynski/projects/SLI_tracker/.github/workflows/sli_compute_sli_metrics.yml)
- [`tools/sli_compute_sli_metrics.js`](/Users/rstyczynski/projects/SLI_tracker/tools/sli_compute_sli_metrics.js)

### 4.4 Synthetic Event Generator Track

The project also includes tools that generate controlled synthetic outcome streams. These tools are used to validate dashboards, alerts, routing behavior, and SLI calculations under known conditions. On this stage it's a tool to generate synthetic data on a non production platform, however in the future similar technique will be used to push data to a system in an idle period, when users are not generating any traffic.

Core files:

- [`tools/sli_ratio_simulator.sh`](/Users/rstyczynski/projects/SLI_tracker/tools/sli_ratio_simulator.sh)
- [`.github/workflows/sli_ratio_simulator.yml`](/Users/rstyczynski/projects/SLI_tracker/.github/workflows/sli_ratio_simulator.yml)

### 4.5 `SLI_TEST` Profile and Test Authentication

`SLI_TEST` is the default test OCI profile used by this repository. It is part of the test framework and is closely related to the GitHub Action [`.github/actions/oci-profile-setup`](/Users/rstyczynski/projects/SLI_tracker/.github/actions/oci-profile-setup).

By default, `SLI_TEST` is a token-based profile prepared for operator-assisted test sessions. The usual flow is browser-based authentication through OCI CLI session login, then packing the resulting OCI configuration and session files into the GitHub secret `OCI_CONFIG_PAYLOAD`. This mode is convenient for shorter assisted test sessions, typically below 60 minutes, because the session token expires and must be refreshed.

For longer-running tests, the same setup flow also supports mirroring the current `DEFAULT` profile into `SLI_TEST`. In this mode the source profile uses regular API-key access instead of a short-lived browser session token. This is handled by `setup_oci_github_access.sh` with `--account-type config_profile`, where the source profile is usually `DEFAULT` and the destination profile stored for CI remains `SLI_TEST`.

The practical meaning is:

- `SLI_TEST` is the standard profile name expected by tests and workflows
- short assisted test sessions usually use token-based browser authentication
- longer-running tests can use a mirrored API-key profile under the same `SLI_TEST` name
- the profile is restored on runners by the `oci-profile-setup` GitHub Action

Core files:

- [`.github/actions/oci-profile-setup/action.yml`](/Users/rstyczynski/projects/SLI_tracker/.github/actions/oci-profile-setup/action.yml)
- [`.github/actions/oci-profile-setup/oci_profile_setup.sh`](/Users/rstyczynski/projects/SLI_tracker/.github/actions/oci-profile-setup/oci_profile_setup.sh)
- [`.github/actions/oci-profile-setup/setup_oci_github_access.sh`](/Users/rstyczynski/projects/SLI_tracker/.github/actions/oci-profile-setup/setup_oci_github_access.sh)
- [`.github/actions/oci-profile-setup/README.md`](/Users/rstyczynski/projects/SLI_tracker/.github/actions/oci-profile-setup/README.md)

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

- [`tools/json_transform_cli.js`](/Users/rstyczynski/projects/SLI_tracker/tools/json_transform_cli.js)
- [`tools/mappings/github_workflow_run_to_oci_log.jsonata`](/Users/rstyczynski/projects/SLI_tracker/tools/mappings/github_workflow_run_to_oci_log.jsonata)
- [`tools/mappings/health_to_oci_metric.jsonata`](/Users/rstyczynski/projects/SLI_tracker/tools/mappings/health_to_oci_metric.jsonata)

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

- [`tests/run.sh`](/Users/rstyczynski/projects/SLI_tracker/tests/run.sh:1)
- [`tests/manifests/component_router.manifest`](/Users/rstyczynski/projects/SLI_tracker/tests/manifests/component_router.manifest)
- [`tests/unit/README.md`](/Users/rstyczynski/projects/SLI_tracker/tests/unit/README.md:1)
- [`tests/integration/README.md`](/Users/rstyczynski/projects/SLI_tracker/tests/integration/README.md:1)

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

The workflows under [`.github/workflows`](/Users/rstyczynski/projects/SLI_tracker/.github/workflows) serve two roles:

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

The root [package.json](/Users/rstyczynski/projects/SLI_tracker/package.json:1) shows the key libraries:

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

Important helpers under [`tools/`](/Users/rstyczynski/projects/SLI_tracker/tools):

- [`ensure_oci_resources.sh`](/Users/rstyczynski/projects/SLI_tracker/tools/ensure_oci_resources.sh)
- [`cycle_apigw_router_passthrough.sh`](/Users/rstyczynski/projects/SLI_tracker/tools/cycle_apigw_router_passthrough.sh)
- [`validate_router_ingest_and_metrics.sh`](/Users/rstyczynski/projects/SLI_tracker/tools/validate_router_ingest_and_metrics.sh)
- [`list_monitoring_metrics.sh`](/Users/rstyczynski/projects/SLI_tracker/tools/list_monitoring_metrics.sh)
- [`list_github_ingest_prefixes.sh`](/Users/rstyczynski/projects/SLI_tracker/tools/list_github_ingest_prefixes.sh)
- [`get_ingest_object.sh`](/Users/rstyczynski/projects/SLI_tracker/tools/get_ingest_object.sh)

### 6.6 OCI Function Router Components

Important files under [`fn/router_passthrough/`](/Users/rstyczynski/projects/SLI_tracker/fn/router_passthrough):

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

1. [`README.md`](/Users/rstyczynski/projects/SLI_tracker/README.md:1)
2. [`.github/workflows/README.md`](/Users/rstyczynski/projects/SLI_tracker/.github/workflows/README.md:1)
3. [`.github/actions/README.md`](/Users/rstyczynski/projects/SLI_tracker/.github/actions/README.md:1)
4. [`tests/unit/README.md`](/Users/rstyczynski/projects/SLI_tracker/tests/unit/README.md:1)
5. [`tests/integration/README.md`](/Users/rstyczynski/projects/SLI_tracker/tests/integration/README.md:1)
6. [`PLAN.md`](/Users/rstyczynski/projects/SLI_tracker/PLAN.md:1)
7. [`PROGRESS_BOARD.md`](/Users/rstyczynski/projects/SLI_tracker/PROGRESS_BOARD.md:1)

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

Each snippet should eventually include:

- scenario
- prerequisites
- command
- expected outcome
- follow-up checks

### 11.1 Prepare `SLI_TEST` Authentication

Most local OCI examples below use `profile":"SLI_TEST"` in `SLI_CONTEXT_JSON`. That profile is prepared by the operator-side script [`.github/actions/oci-profile-setup/setup_oci_github_access.sh`](/Users/rstyczynski/projects/SLI_tracker/.github/actions/oci-profile-setup/setup_oci_github_access.sh).

After a successful run, local commands can use `~/.oci/config` with profile `SLI_TEST`. On GitHub runners, the paired restore action [`.github/actions/oci-profile-setup/oci_profile_setup.sh`](/Users/rstyczynski/projects/SLI_tracker/.github/actions/oci-profile-setup/oci_profile_setup.sh) unpacks that same profile from `OCI_CONFIG_PAYLOAD`.

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

#### Route one local envelope from a file and inspect the delivered file

```bash
TMP_DIR="$(mktemp -d /tmp/sli_router_single.XXXXXX)"
cp tests/fixtures/router_destinations/ut111_mixed_destinations/mapping_file.jsonata "$TMP_DIR/mapping_file.jsonata"

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
  --input tests/fixtures/router_destinations/ut111_mixed_destinations/source/004_audit.json \
  --pretty

find "$TMP_DIR/file_system" -type f | sort
cat "$TMP_DIR/file_system/audit_copy/001_audit_to_file.json" | jq
```

#### Route one local envelope from stdin

```bash
TMP_DIR="$(mktemp -d /tmp/sli_router_stdin.XXXXXX)"
cp tests/fixtures/router_destinations/ut111_mixed_destinations/mapping_file.jsonata "$TMP_DIR/mapping_file.jsonata"

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

cat tests/fixtures/router_destinations/ut111_mixed_destinations/source/004_audit.json \
  | node tools/json_router_cli.js \
      --routing "$TMP_DIR/routing.json" \
      --pretty

find "$TMP_DIR/file_system" -type f | sort
cat "$TMP_DIR/file_system/audit_copy/001_audit_to_file.json" | jq
```

#### Route a local source directory to a local output directory

This example runs three source files through the router in batch mode. Expect one workflow event to fan out into two output files, one health event to produce one metric-style output file, and one unknown event to land in `dead_letter/errors/`.

```bash
OUT_DIR="$(mktemp -d /tmp/sli_router_batch.XXXXXX)"

node tools/json_router_cli.js \
  --routing tests/fixtures/router_batch/ut83_bulk_mixed_delivery/routing.json \
  --source-dir tests/fixtures/router_batch/ut83_bulk_mixed_delivery/source \
  --output-dir "$OUT_DIR" \
  | jq

find "$OUT_DIR" -type f | sort
```

#### Transform from stdin and pipe directly into router CLI

This pipeline first reshapes the source JSON into a router envelope, then routes it. In this routing definition the main workflow match is combined with a fanout route, so expect two delivered files: one normalized workflow record in `file_system/specific_events/` and one metric-style record in `file_system/workflow_status/`.

```bash
TMP_DIR="$(mktemp -d /tmp/sli_router_pipeline.XXXXXX)"

cat > "$TMP_DIR/routing.json" <<EOF
{
  "routes": [
    {
      "id": "specific_workflow",
      "mode": "exclusive",
      "priority": 200,
      "match": {
        "headers": { "X-GitHub-Event": "workflow_run" },
        "schema": { "path": "schema", "equals": "github.workflow_run" }
      },
      "transform": {
        "mapping": "${PWD}/tests/fixtures/pipeline_cli/ut94_transform_then_route_success/mapping_specific.jsonata"
      },
      "destination": {
        "type": "file_system",
        "name": "specific_events"
      }
    },
    {
      "id": "workflow_metric",
      "mode": "fanout",
      "match": {
        "headers": { "X-GitHub-Event": "workflow_run" }
      },
      "transform": {
        "mapping": "${PWD}/tests/fixtures/pipeline_cli/ut94_transform_then_route_success/mapping_metric.jsonata"
      },
      "destination": {
        "type": "file_system",
        "name": "workflow_status"
      }
    }
  ]
}
EOF

cat tests/fixtures/pipeline_cli/ut94_transform_then_route_success/source.json \
  | node tools/json_transform_cli.js \
      --mapping tests/fixtures/pipeline_cli/ut94_transform_then_route_success/mapping.jsonata \
  | node tools/json_router_cli.js \
      --routing "$TMP_DIR/routing.json" \
      --pretty

find "$TMP_DIR/file_system" -type f | sort
```

This stdin-to-stdout chaining is the regular stream-processing technique used when data is passed between processing stages without intermediate files. The same style is important for Function-style processing, where the input body is received as a stream, transformed, and handed to the next stage.

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

## 12. Status of This Manual

This is the initial structure-focused version of the manual. It is intentionally broad and should be expanded with deeper chapters instead of being rewritten from scratch.
