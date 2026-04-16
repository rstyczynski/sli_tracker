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

> **Profile note:** The examples in this section use the local `DEFAULT` OCI profile on purpose. At this stage the reader only needs one working authenticated profile to see data arrive in OCI. The repository-specific `SLI_TEST` profile is introduced later in [Authenticate SLI_TEST](#authenticate-sli_test) and described in more detail in §5.6.

### 3.0 Prerequisites: OCI Resources

#### Required OCI access

> **Note:** This project is in construction phase. The access policy below grants broad privileges intentionally — least-privilege hardening is deferred to a future production readiness sprint.

Tenancy-level administrator access is preferred and simplifies setup. Compartment-level access works too, but the operator must ensure the profile has the following permissions on the target compartment:

| OCI service | Required permission |
| ----------- | ------------------- |
| Compartments | `COMPARTMENT_INSPECT` |
| Logging (log groups + logs) | `LOG_GROUP_CREATE`, `LOG_GROUP_INSPECT`, `LOG_CREATE`, `LOG_INSPECT` |
| Logging ingestion | `LOG_PUSH_DATA` |
| Monitoring (metric post) | `METRIC_SUBMIT` |
| Object Storage | `OBJECT_CREATE`, `OBJECT_READ`, `BUCKET_CREATE`, `BUCKET_INSPECT` |
| Functions + API Gateway | `FN_FUNCTION_CREATE`, `FN_FUNCTION_INVOKE`, `API_GATEWAY_CREATE` |

The simplest policy statement for a **tenancy administrator**:

```text
Allow group <your-group> to manage all-resources in tenancy
```

For **compartment-level** access, scope the same statement to the compartment:

```text
Allow group <your-group> to manage all-resources in compartment <compartment-name>
```

These policies are set in the OCI Console under **Identity → Policies** or via OCI CLI.

Before running the examples below, you need three OCIDs in your shell environment: `COMPARTMENT_OCID`, `LOG_ID`, and `LOG_GROUP_ID`. Choose one path.

#### Path A — Create resources with `ensure_oci_resources.sh`

If you do not yet have an OCI log set up for this project, load the helper script first, then call the specific function that creates or adopts the compartment, log group, and log. The script itself is source-only: `source tools/ensure_oci_resources.sh` just loads function definitions into the current shell. The actual OCI work starts when you call `ensure_sli_log_resources ...`. That function is idempotent, so it is safe to re-run.

```bash
source tools/ensure_oci_resources.sh

export NAME_PREFIX="sli_quickstart"
export SLI_OCI_LOG_URI="/SLI_tracker/sli-events/github-actions"

ensure_sli_log_resources "$(pwd)" DEFAULT "$NAME_PREFIX" "$SLI_OCI_LOG_URI"
export LOG_ID="$SLI_LOG_OCID"
export LOG_GROUP_ID="$LOG_GROUP_OCID"
```

State is written to `./state-${NAME_PREFIX}.json`. You can read OCIDs from it any time:

```bash
jq '{compartment: .compartment.ocid, log_group: .log_group.ocid, log: .log.ocid}' state-sli_quickstart.json
```

#### Path B — Adopt existing OCI resources

`ensure_sli_log_resources` is idempotent — it inspects existing OCI resources by name and adopts them if they already exist, creating only what is missing. This is the reason the project uses `oci_scaffold` helpers instead of Terraform: the same script works on a fresh account and on an account where those resources were created by hand or by a previous run.

If you prefer to skip the helper entirely and point at OCIDs you already know, export them directly:

```bash
export COMPARTMENT_OCID="ocid1.compartment.oc1..<your-compartment-ocid>"
export LOG_GROUP_ID="ocid1.loggroup.oc1..<your-log-group-ocid>"
export LOG_ID="ocid1.log.oc1..<your-log-ocid>"
```

#### Sync OCIDs to GitHub repository variables

GitHub workflows read these OCIDs from repository variables. Once the OCIDs are in your shell, push them to the repository — this step is required for any workflow in this project to reach OCI:

```bash
repo=$(gh repo view --json nameWithOwner -q .nameWithOwner)
gh variable set SLI_OCI_LOG_ID          --body "$LOG_ID"           -R "$repo"
gh variable set SLI_OCI_COMPARTMENT_ID  --body "$COMPARTMENT_OCID" -R "$repo"
gh variable set SLI_OCI_LOG_GROUP_ID    --body "$LOG_GROUP_ID"     -R "$repo"
```

### 3.1 Inject Log into OCI Logging

Having infrastructure ready, we can inject log entry into OCI logging subsystem. Logging is one of techniques used by SLI tracker to store descriptive events inside of the OCI.

The payload is intentionally small and easy to recognize when you query the log later.

```json
{
  "defaultlogentrytime": "2024-01-19T15:23:45Z",
  "source": "manual/oci-cli",
  "type": "sli-event",
  "entries": [
    {
      "id": "2024-01-19T15:23:45Z-manual",
      "time": "2024-01-19T15:23:45Z",
      "data": "{\"source\":\"manual\",\"path\":\"oci-cli\",\"outcome\":\"success\",\"timestamp\":\"2024-01-19T15:23:45Z\"}"
    }
  ]
}
```

Below bash code appends above JSON log entry to the configured OCI log.

```bash
# Requires: LOG_ID exported in §3.0
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

### 3.2 Inject Failure Log Message

To demonstrate SLI you will inject a failure event, keeping the same shape as the success payload above and change `outcome` to `"failure"`. Include an explicit failure reason so you can spot it easily in OCI Logging.

```bash
# Requires: LOG_ID exported in §3.0
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

This is the first point where the operator can see the whole idea working end to end. The CLI command is not just accepted locally; it creates a real searchable record in OCI Logging. Open the OCI Console, go to the log associated with this deployment, and inspect recent entries. Look for records where `source == "manual"` and `path == "oci-cli"` to confirm that the timestamp and payload match what you injected.

Once both `success` and `failure` entries are visible, you have validated the most basic ingestion path: a structured event left your shell, reached OCI, and became queryable operational data.

If you want to jump directly to the log in OCI Console, derive the region from the log OCID and open it. Be prepared to wait 30-60 seconds for data to appear in the log search console - it's the time needed to ingest the data.

```bash
REGION=$(echo "$LOG_ID" | cut -d. -f4)
open "https://cloud.oracle.com/logging/logs/${LOG_ID}/log-groups/${LOG_GROUP_ID}/explore-log?region=${REGION}"
```

### 3.3 Query That Log Category Back and Compute Message-Level SLI

For the manual CLI log examples above, a simple message-level SLI is `number of success messages / number of messages`. The category is identified by the payload fields `source=="manual"` and `path=="oci-cli"`. Wait around 60 seconds for log propagation, then search the last 30 minutes of data and compute the ratio.

```bash
# Requires: COMPARTMENT_OCID, LOG_ID, LOG_GROUP_ID exported in §3.0
export OCI_CLI_PROFILE=DEFAULT
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

After you compute `SLI` from the queried log stream, you can publish that ratio back to OCI Monitoring as a derived metric. Run this in the same shell as the previous snippet if you want to reuse the computed value. If `SLI` is not already set, this example falls back to `0.5` so the reader can still exercise the Monitoring path. In this example the metric carries the dimension `window="30min"` so the reader can see which aggregation window produced the value.

```bash
# Requires: COMPARTMENT_OCID exported in §3.0; optionally reuse SLI from §3.3
export OCI_CLI_PROFILE=DEFAULT
TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
SLI="${SLI:-0.5}"

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

This is the metric-side equivalent of the earlier Logging check. The command does not just return success locally; it creates real datapoints in OCI Monitoring that can later drive charts, queries, alarms, and derived SLI calculations. Open the OCI Console and go to Metric Explorer.

```bash
open https://cloud.oracle.com/monitoring/explore?region=$OCI_REGION
```

Select compartment `SLI_tracker`, namespace `sli_tracker_manual`, metric name `sli`, and press `Update chart`. You should see a single point near the right edge of the chart. Press `Show Data Table` to inspect the raw datapoint.

Once those datapoints are visible, you have validated the second half of the telemetry story: the same manual exercise can now produce both searchable event records in Logging and numeric signals in Monitoring.

### 3.5 Search for metric data

The project later computes SLI from Monitoring data over a sliding time window. The live implementation in [`tools/sli_compute_sli_metrics.js`](../tools/sli_compute_sli_metrics.js) uses Monitoring summary queries over a bounded interval, then derives `success / total` from the returned datapoints. Before going there, it is useful to query the just-inserted manual datapoints directly with OCI CLI and see that they are really present.

The example below searches the last 60 minutes for the metric series created in the previous step. It is the CLI equivalent of searching for the same series in OCI Metric Explorer.

```bash
# Requires: COMPARTMENT_OCID exported in §3.0
export OCI_CLI_PROFILE=DEFAULT
TS_START="$(date -u -v-60M '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u --date='-60 min' '+%Y-%m-%dT%H:%M:%SZ')"
TS_END="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

oci monitoring metric-data summarize-metrics-data \
  --compartment-id "$COMPARTMENT_OCID" \
  --namespace sli_tracker_manual \
  --start-time "$TS_START" \
  --end-time "$TS_END" \
  --resolution 1m \
  --query-text 'sli[1m].mean()' \
  --output json \
| jq '.data[]'
```

If the data is already visible, the query returns one or more streams with `aggregated-datapoints`. The timestamps should be close to the values you inserted manually. If you do not see anything yet, wait a short while and repeat the command, because Monitoring ingestion is not always immediate.

This is a simplified form of the same idea used later for sliding-window SLI computation. Here you only verify that the datapoints exist. Later, the project queries Monitoring over a larger rolling interval and aggregates those datapoints into one operational SLI value.

## 4. Injection tools Hands-On

Direct log and metric injection is conceptually simple, but it quickly becomes configuration-heavy. This project therefore provides several operator-facing entry points: local CLI examples, GitHub workflow examples, and reusable local GitHub Actions.

The next step after direct injection is automation. Incoming traffic such as GitHub webhooks cannot be handled manually, so the project also provides transformer and router components that can classify messages, reshape them, and forward them to the right destinations. Before getting there, the operator should first understand how workflow-based OCI authentication works.

### 4.1 Authenticate SLI_TEST

Before playing with workflow examples, prepare the project-specific OCI profile `SLI_TEST`. This is the profile name expected by the workflows in this repository. The recommended starting mode is a browser-authenticated session token, which is safer for operator-driven setup than distributing a long-lived API key.

The session-based setup has three moving parts:

- OCI CLI on the machine where you prepare the profile
- the local setup script that creates or refreshes `SLI_TEST`
- the workflow restore action that recreates that profile on GitHub runners

#### 4.1.1. Install OCI CLI locally

The profile setup script calls `oci session authenticate`, so your workstation needs a working OCI CLI first.

If OCI CLI is not installed yet, use Oracle's standard installation path or the helper logic documented in:

- [`.github/actions/install-oci-cli/README.md`](../.github/actions/install-oci-cli/README.md)

On GitHub runners, the same role is handled by the action:

- [`.github/actions/install-oci-cli/action.yml`](../.github/actions/install-oci-cli/action.yml)

Operator meaning:

- locally, OCI CLI is needed to open the browser login flow and create the session token
- in workflows, `install-oci-cli` makes the `oci` command available before profile restoration and OCI calls

#### 4.1.2. Create or refresh `SLI_TEST` with a browser-authenticated session

Run the operator-side setup script from the repository root:

```bash
.github/actions/oci-profile-setup/setup_oci_github_access.sh \
  --account-type session \
  --profile DEFAULT \
  --session-profile-name SLI_TEST \
  --repo "$(gh repo view --json nameWithOwner -q .nameWithOwner)"
```

What this does:

- starts `oci session authenticate`
- lets you log in through the browser
- creates a local session profile named `SLI_TEST`
- packs the needed `~/.oci/config` and `~/.oci/sessions/SLI_TEST` content
- uploads that payload to the GitHub secret `OCI_CONFIG_PAYLOAD`

This same command is also the refresh command. When the session token expires, run it again to replace the GitHub secret with a fresh session.

After it succeeds, verify locally:

```bash
oci iam region-subscription list --profile SLI_TEST --auth security_token | jq '.data[0]'
```

#### 4.1.3. Understand what workflows do with that secret

Workflows do not log in interactively. Instead, they restore and replay the profile you prepared earlier.

The usual pair of workflow steps is:

1. `install-oci-cli`
2. `oci-profile-setup`

Both are packaged in this repository as local GitHub Actions:

- [`.github/actions/install-oci-cli/action.yml`](../.github/actions/install-oci-cli/action.yml)
- [`.github/actions/oci-profile-setup/action.yml`](../.github/actions/oci-profile-setup/action.yml)

So workflows use them through `uses: ./.github/actions/...` rather than reimplementing shell logic inline.

`install-oci-cli`:

- installs OCI CLI on the GitHub runner
- adds `oci` to `PATH`
- is required for any workflow that uses the `oci-cli` backend

`oci-profile-setup`:

- reads the repository secret `OCI_CONFIG_PAYLOAD`
- restores `~/.oci/config` and session files on the runner
- exposes the resolved profile name to later workflow steps

Example workflow pattern:

```yaml
- name: Install OCI CLI
  uses: ./.github/actions/install-oci-cli

- name: Restore OCI profile
  id: oci_profile
  uses: ./.github/actions/oci-profile-setup
  with:
    oci_config_payload: ${{ secrets.OCI_CONFIG_PAYLOAD }}
    profile: SLI_TEST
```

Then later steps use:

- `profile: ${{ steps.oci_profile.outputs.profile || 'SLI_TEST' }}`

This is why the profile name matters. The packed profile name and the workflow restore profile must match.

Useful references:

- [`.github/actions/oci-profile-setup/setup_oci_github_access.sh`](../.github/actions/oci-profile-setup/setup_oci_github_access.sh)
- [`.github/actions/oci-profile-setup/README.md`](../.github/actions/oci-profile-setup/README.md)

### 4.2 GitHub Actions SLI Track

#### 4.2.1. Emit monitoring and log data via OCI CLI, direct API, and JS SDK

The OCI profile is the critical prerequisite, however OCI CLI itself is only one possible emission backend. This project provides alternatives to interplay with OCI:

- `cli`, regular OCI CLI build on top of python
- `curl`, which talks directly to OCI APIs
- JavaScript, which uses the Oracle JS SDK

Those three workflow variants are:

- [`.github/workflows/model-emit.yml`](../.github/workflows/model-emit.yml)
- [`.github/workflows/model-emit-curl.yml`](../.github/workflows/model-emit-curl.yml)
- [`.github/workflows/model-emit-js.yml`](../.github/workflows/model-emit-js.yml)

Once `SLI_TEST` is authenticated and the secret is fresh, you can move to workflow examples and expect OCI-backed steps to work without additional local setup.

GitHub workflows call local actions:

- [`.github/actions/sli-event/action.yml`](../.github/actions/sli-event/action.yml) - that cover both `cli` and `curl`
- [`.github/actions/sli-event-js/action.yml`](../.github/actions/sli-event-js/action.yml) - utilizing native GitHub JavaScript support with `post` registration.

Open GitHub Actions and inspect the three `MODEL — emit / ...` workflows to see the same event path exercised through different emission backends.

XXXXX use gh to run and check
```bash
```

## 5. Router tools Hands-On

### 5.1 Router and Ingest Track1

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

### 5.2 Local Transformation and Routing CLI

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

#### Capability 2: route one local envelope from stdin

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

#### Capability 3: pretty output and mapping context

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

#### Capability 4: route a local source directory to a local output directory

```bash
OUT_DIR="$(mktemp -d /tmp/sli_router_batch.XXXXXX)"
SRC_DIR="$(mktemp -d /tmp/sli_router_batch_source.XXXXXX)"
ROUTING_DIR="$(mktemp -d /tmp/sli_router_batch_routing.XXXXXX)"
```

This chapter continues later in the snippet catalog with the same runnable examples, but router-specific material now belongs conceptually to section 5.

### 5.3 OCI Router Operations

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

### 5.4 SLI Calculation Track

The project includes tools that compute rolling-window SLI values from OCI Monitoring metrics. This is the as simple as possible analytical part of the system: it reads collected telemetry and derives higher-level service indicators from it. Simplicity here comes from both a calculation method, and execution, that uses GitHub workflow scheduling.

Core files:

- [`.github/workflows/sli_compute_sli_metrics.yml`](../.github/workflows/sli_compute_sli_metrics.yml)
- [`tools/sli_compute_sli_metrics.js`](../tools/sli_compute_sli_metrics.js)

### 5.5 Synthetic Event Generator Track

The project also includes tools that generate controlled synthetic outcome streams. These tools are used to validate dashboards, alerts, routing behavior, and SLI calculations under known conditions. On this stage it's a tool to generate synthetic data on a non production platform, however in the future similar technique will be used to push data to a system in an idle period, when users are not generating any traffic.

Core files:

- [`tools/sli_ratio_simulator.sh`](../tools/sli_ratio_simulator.sh)
- [`.github/workflows/sli_ratio_simulator.yml`](../.github/workflows/sli_ratio_simulator.yml)

### 5.6 OCI Authentication Profiles

This project uses two named OCI profiles:

| Profile | Where used | Lifetime |
| ------- | ---------- | -------- |
| `DEFAULT` | Local operator commands, §3 examples | Depends on local key — usually non-expiring API key |
| `SLI_TEST` | Tests, GitHub Actions workflows, operator cookbook | Session: ~60 min · API key: non-expiring |

`DEFAULT` is the standard OCI CLI profile every operator already has locally. The early examples in §3 use it deliberately — no extra setup required, and it proves that OCI ingestion works before introducing any project-specific tooling.

`SLI_TEST` is the project-standard profile name expected by all tests and workflows in this repository. It is created by a dedicated setup tool and optionally packed into a GitHub secret so CI runners can authenticate to OCI.

#### The Profile Setup Tool

`setup_oci_github_access.sh` is the operator-facing script that creates `SLI_TEST` and (optionally) uploads it to GitHub as a repository secret. It supports two authentication modes.

##### Mode 1 — Session (browser-authenticated token)

Use this for short-lived operator-assisted test sessions. The script runs `oci session authenticate`, which opens a browser for OCI IAM login and produces a time-limited session token. The resulting profile and token files are packed into `OCI_CONFIG_PAYLOAD` and uploaded to GitHub.

```bash
.github/actions/oci-profile-setup/setup_oci_github_access.sh \
  --account-type session \
  --profile DEFAULT \
  --session-profile-name SLI_TEST \
  --repo "$(gh repo view --json nameWithOwner -q .nameWithOwner)"
```

- Token expires after approximately 60 minutes
- Must be refreshed before the next test session
- Suitable for interactive work where an operator is present

##### Mode 2 — Config profile (API-key based)

Use this for longer-running tests or fully automated CI. The script mirrors an existing local profile (usually `DEFAULT`) into `SLI_TEST`, copying the API key configuration. The result is packed and uploaded to GitHub in the same way.

```bash
.github/actions/oci-profile-setup/setup_oci_github_access.sh \
  --account-type config_profile \
  --profile DEFAULT \
  --session-profile-name SLI_TEST \
  --repo "$(gh repo view --json nameWithOwner -q .nameWithOwner)"
```

- Token does not expire
- Copies your local `DEFAULT` private key material into the packed secret — treat the secret accordingly
- Suitable for unattended pipelines

#### Profile Restoration on CI Runners

On GitHub Actions runners, the packed `OCI_CONFIG_PAYLOAD` secret is unpacked by the restore action:

- [`.github/actions/oci-profile-setup/action.yml`](../.github/actions/oci-profile-setup/action.yml)
- [`.github/actions/oci-profile-setup/oci_profile_setup.sh`](../.github/actions/oci-profile-setup/oci_profile_setup.sh)

After restoration, the runner has `~/.oci/config` with the `SLI_TEST` profile available for OCI SDK calls and OCI CLI commands.

Full tool reference:

- [`.github/actions/oci-profile-setup/setup_oci_github_access.sh`](../.github/actions/oci-profile-setup/setup_oci_github_access.sh)
- [`.github/actions/oci-profile-setup/README.md`](../.github/actions/oci-profile-setup/README.md)

## 6. Major Techniques Used in This Project

This section names the main technical patterns a reader needs to understand.

### 6.1 Structured Event Emission from GitHub Actions

The project treats GitHub workflow runs as telemetry sources. Rather than logging plain text, it builds structured JSON payloads containing:

- workflow identity
- repository and ref metadata
- run outcome
- optional domain-specific inputs
- failure reasons derived from failed steps

This is the core observability technique of the repository.

### 6.2 Backend-Switchable OCI Emission

Emission is not tied to one transport implementation. The repository supports multiple backend styles:

- OCI CLI based emission
- curl plus request-signing emission
- JavaScript action based post-step emission

This keeps the payload contract stable while allowing transport changes. It may be beneficial to fully switch to core API accessible via `curl` or Node.js SDK, as it eliminates OCI CLI and python installation steps what saves pipeline execution time.

### 6.3 Telemetry Sinks

The same logical event can be sent to more than one destination:

- OCI Logging for searchable raw events
- OCI Monitoring for numeric metrics
- OCI Object Storage Bucket for debug and further use cases.

This is important because logs are better for audit and search, while metrics are better for ratio calculation and alerting. Platform comes with pluggable adapter interface, enabling new sources and destination to be added.

### 6.4 JSONata Transformation

JSONata expressions are used to transform one JSON document into another. This lets the project convert source-specific payloads into destination-specific contracts without hardcoding every variation in application logic.

Relevant files:

- [`tools/json_transform_cli.js`](../tools/json_transform_cli.js)
- [`tools/mappings/github_workflow_run_to_oci_log.jsonata`](../tools/mappings/github_workflow_run_to_oci_log.jsonata)
- [`tools/mappings/health_to_oci_metric.jsonata`](../tools/mappings/health_to_oci_metric.jsonata)

### 6.5 Config-Driven Routing

The router identifies payload type, chooses a mapping, and dispatches to one or more destinations based on configuration. This allows new flows to be added by editing routing definitions and mappings instead of rewriting the runtime.

Key concepts:

- source identification
- exclusive versus fanout routing
- destination abstraction
- adapter registration from config
- dead-letter handling for failures

### 6.6 Adapter-Based Delivery

Destination-specific behavior is isolated behind adapters. This is a major design technique in the repo because it separates routing logic from side effects.

Examples:

- file adapter
- OCI Object Storage adapter
- OCI Monitoring adapter
- OCI Logging adapter

### 6.7 OCI Function as Public Ingest Endpoint

The project includes an OCI Function deployment that accepts public traffic through API Gateway and performs routing plus delivery. This is the bridge between external event producers and OCI-hosted telemetry storage.

### 6.8 Test-First Quality Gates

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

### 6.9 Infrastructure Lifecycle Scripts

OCI resources are not assumed to exist forever. The repository contains helper scripts to create, validate, and tear down test infrastructure in a repeatable way.

This includes:

- OCI log and compartment setup
- Function resource policies
- API Gateway router deployment lifecycle
- bucket cleanup and validation helpers

## 7. Major Tools and Components

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

## 8. Repository Areas and Their Roles

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

## 9. Operational Knowledge a Reader Should Gain

By the time a reader finishes the first part of this manual, they should be able to answer these questions:

1. What counts as an SLI event in this repo?
2. Which parts emit events, and which parts route them?
3. When should Logging be used versus Monitoring?
4. How are transformations expressed?
5. How does the router choose a destination?
6. Which tests are local-only and which tests require live OCI and GitHub access?
7. Which scripts are used to stand infrastructure up and tear it down?

These questions will later map to deeper chapters.

## 10. Suggested Reading Order

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

## 11. Known Knowledge Domains for Future Expansion

The next iterations of this manual should likely add dedicated chapters for:

1. event schema and payload anatomy
2. OCI authentication models used by the project
3. router configuration model and mapping files
4. Function deployment flow and required OCI resources
5. test strategy and quality gates
6. troubleshooting and failure modes
7. sprint history and why the architecture evolved the way it did

## 12. Snippet Catalog

This section is intentionally placed at the bottom so it can grow into a practical operator cookbook.

Unless noted otherwise, run the commands below from the repository root. The manual file lives in `docs/`, but the snippets use repository-root relative paths such as `tools/`, `tests/`, `.github/`, and `progress/`.

Each snippet should eventually include:

- scenario
- prerequisites
- command
- expected outcome
- follow-up checks

### 12.1 Prepare `SLI_TEST` Authentication

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

### 12.2 Local SLI Emission

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

### 12.3 SLI Simulation and Computation

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

### 12.4 Local Transformation and Routing CLI

The canonical router CLI guide now lives in §5.2. This snippet-catalog entry remains only as a navigation point for readers who jump here directly.

Use §5.2 for:

- transform CLI basics
- router CLI contract
- one-envelope routing from file and `stdin`
- pretty output and mapping context
- batch routing
- source-declared execution
- OCI-backed router capabilities
- dead-letter handling and common router error cases

### 12.5 OCI Router Operations

The canonical operational router commands now live in §5.3. This snippet-catalog entry remains only as a navigation point for readers who search for OCI router operations directly.

### 12.6 Teardown

#### Delete the API Gateway + Fn router stack

```bash
export NAME_PREFIX="${SLI_FN_APIGW_ROUTER_PREFIX:-sli-router-passthrough-dev}"

bash tests/cleanup_router_apigw_stack.sh
```

#### Delete all `sli-*` buckets in `/SLI_tracker`

```bash
bash tests/cleanup_sli_buckets.sh
```

## 13. Supporting Source Documents

This manual is the primary operator document. Supporting sprint documents remain useful when you want historical context, implementation rationale, or detailed test evidence behind the router work.

Useful supporting documents:

- [progress/sprint_29/sprint_29_manual.md](../progress/sprint_29/sprint_29_manual.md)
- [progress/sprint_29/sprint_29_design.md](../progress/sprint_29/sprint_29_design.md)
- [progress/sprint_29/sprint_29_implementation.md](../progress/sprint_29/sprint_29_implementation.md)
- [progress/sprint_29/sprint_29_tests.md](../progress/sprint_29/sprint_29_tests.md)
