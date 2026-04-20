# SLI Tracker Manual

`SLI_tracker` is a framework for collecting, routing, storing, and evaluating Service Level Indicator data on Oracle Cloud Infrastructure. It provides tools and techniques to push service level indicators to OCI Monitoring, OCI Logging, and OCI Object Storage.

The same framework can be used beyond the GitHub Actions example implemented in this repository. The current repository is one concrete system built with these techniques, but the same pattern can be extended to other SLI sources, other telemetry domains, and other kinds of status or health information.

The framework can accept notifications from external systems, receive OCI-native events, and pull data from exposed service endpoints. In all of these cases it applies the same core flow: collect data, normalize it, route it, store it, and evaluate it.

The system model is shown below.

<p align="center"><img src="../model/model.jpg" alt="SLI Tracker system model" width="50%"></p>

The editable source is [`model/model.drawio`](../model/model.drawio).

## Table of Contents

- [1. Project Overview](#1-project-overview)
- [2. Motivating Story and Mental Model](#2-motivating-story-and-mental-model)
  - [2.1 Start with a Real `workflow_run` Event](#21-start-with-a-real-workflow_run-event)
  - [2.2 Why Transformation Exists](#22-why-transformation-exists)
  - [2.3 Why the Router Exists](#23-why-the-router-exists)
- [3. OCI Injection Examples](#3-oci-injection-examples)
  - [3.0 Prerequisites: OCI Resources](#30-prerequisites-oci-resources)
  - [3.1 Inject Log into OCI Logging](#31-inject-log-into-oci-logging)
  - [3.2 Inject Failure Log Message](#32-inject-failure-log-message)
  - [3.3 Query That Log Category Back and Compute Message-Level SLI](#33-query-that-log-category-back-and-compute-message-level-sli)
  - [3.4 Inject the Computed SLI as One Derived OCI Metric](#34-inject-the-computed-sli-as-one-derived-oci-metric)
  - [3.5 Search for metric data](#35-search-for-metric-data)
- [4. Workflow data injection tools Hands-On](#4-workflow-data-injection-tools-hands-on)
  - [4.1 OCI authentication](#41-oci-authentication)
  - [4.2 GitHub Actions SLI metric emitter](#42-github-actions-sli-metric-emitter)
  - [4.3 curl](#43-curl)
  - [4.4 js](#44-js)
  - [4.5 OCI side data view](#45-oci-side-data-view)
- [5. Router and Ingest Hands-On](#5-router-and-ingest-hands-on)
  - [5.1 Key Concepts](#51-key-concepts)
  - [5.2 Step 1 — Transform a Document with JSONata](#52-step-1--transform-a-document-with-jsonata)
  - [5.3 Step 2 — Route One Envelope to a File](#53-step-2--route-one-envelope-to-a-file)
  - [5.4 Step 3 — Route a GitHub Webhook with a Real Mapping](#54-step-3--route-a-github-webhook-with-a-real-mapping)
  - [5.5 Step 4 — Fan-Out One Envelope to Two Destinations](#55-step-4--fan-out-one-envelope-to-two-destinations)
  - [5.6 Step 5 — Batch Route a Source Directory](#56-step-5--batch-route-a-source-directory)
  - [5.7 Step 6 — Deploy the Public Router Function](#57-step-6--deploy-the-public-router-function)
  - [5.8 Step 7 — Send a Webhook to the Deployed Function](#58-step-7--send-a-webhook-to-the-deployed-function)
  - [5.9 Step 8 — Verify Ingest in Object Storage](#59-step-8--verify-ingest-in-object-storage)
  - [5.10 Step 9 — Verify Fan-Out to OCI Monitoring and Logging](#510-step-9--verify-fan-out-to-oci-monitoring-and-logging)
  - [5.11 SLI Calculation](#511-sli-calculation)
  - [5.12 Synthetic Event Generator](#512-synthetic-event-generator)
  - [5.13 OCI Authentication Profiles](#513-oci-authentication-profiles)
- [6. Major Techniques Used in This Project](#6-major-techniques-used-in-this-project)
  - [6.1 Structured Event Emission from GitHub Actions](#61-structured-event-emission-from-github-actions)
  - [6.2 Backend-Switchable OCI Emission](#62-backend-switchable-oci-emission)
  - [6.3 Telemetry Sinks](#63-telemetry-sinks)
  - [6.4 JSONata Transformation](#64-jsonata-transformation)
  - [6.5 Config-Driven Routing](#65-config-driven-routing)
  - [6.6 Adapter-Based Delivery](#66-adapter-based-delivery)
  - [6.7 OCI Function as Public Ingest Endpoint](#67-oci-function-as-public-ingest-endpoint)
  - [6.8 Test-First Quality Gates](#68-test-first-quality-gates)
  - [6.9 Infrastructure Lifecycle Scripts](#69-infrastructure-lifecycle-scripts)
- [7. Major Tools and Components](#7-major-tools-and-components)
- [8. Repository Areas and Their Roles](#8-repository-areas-and-their-roles)
- [9. Operational Knowledge a Reader Should Gain](#9-operational-knowledge-a-reader-should-gain)
- [10. Suggested Reading Order](#10-suggested-reading-order)
- [11. Known Knowledge Domains for Future Expansion](#11-known-knowledge-domains-for-future-expansion)
- [12. Snippet Catalog](#12-snippet-catalog)
  - [12.1 Prepare `SLI_TEST` Authentication](#121-prepare-sli_test-authentication)
  - [12.2 Local SLI Emission](#122-local-sli-emission)
  - [12.3 SLI Simulation and Computation](#123-sli-simulation-and-computation)
  - [12.4 Local Transformation and Routing CLI](#124-local-transformation-and-routing-cli)
  - [12.5 OCI Router Operations](#125-oci-router-operations)
  - [12.6 Teardown](#126-teardown)
- [13. Supporting Source Documents](#13-supporting-source-documents)

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

PARSED_EVENTS="$(
  printf '%s\n' "$EVENTS" \
    | jq '
        [
          .[]
          | .data.logContent.data
          | try (if type=="string" then fromjson else . end) catch empty
          | select(.source == "manual" and .path == "oci-cli")
        ]
      '
)"

TOTAL="$(jq -n --argjson events "$PARSED_EVENTS" '$events | length')"
SUCCESS="$(jq -n --argjson events "$PARSED_EVENTS" '$events | map(select(.outcome == "success")) | length')"
FAILURE="$(jq -n --argjson events "$PARSED_EVENTS" '$events | map(select(.outcome == "failure")) | length')"
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
  --batch-atomicity ATOMIC
```

This is the metric-side equivalent of the earlier Logging check. The command does not just return success locally; it creates real datapoints in OCI Monitoring that can later drive charts, queries, alarms, and derived SLI calculations. Open the OCI Console and go to Metric Explorer.

```bash
echo "Open OCI Metric Explorer: https://cloud.oracle.com/monitoring/explore?region=$OCI_REGION"
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

## 4. Workflow data injection tools Hands-On

Direct log and metric injection is conceptually simple, but it quickly becomes configuration-heavy. This project therefore provides several operator-facing entry points: local CLI examples, GitHub workflow examples, and reusable local GitHub Actions.

The next step after direct injection is automation. Incoming traffic such as GitHub webhooks cannot be handled manually, so the project also provides transformer and router components that can classify messages, reshape them, and forward them to the right destinations. Before getting there, the operator should first understand how workflow-based OCI authentication works.

### 4.1 OCI authentication

Before playing with workflow examples, prepare the project-specific OCI profile `SLI_TEST`. This is the profile name expected by the workflows in this repository. The recommended starting mode is a browser-authenticated session token, which is safer for operator-driven setup than distributing a long-lived API key.

The session-based setup has three moving parts:

- OCI CLI on the machine where you prepare the profile
- the local setup script that creates or refreshes `SLI_TEST`
- the workflow restore action that recreates that profile on GitHub runners

#### 4.1.1. Install OCI CLI locally

The profile setup script calls `oci session authenticate`, so your workstation needs a working OCI CLI first. Use regular Oracle documentation to install OCI CLI on your system; typically it's as easy as package installation.

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

### 4.2 GitHub Actions SLI metric emitter

Metric emitter supports:

- `cli`, regular OCI CLI build on top of python
- `curl` to talk directly over OCI APIs
- `js` to use the Oracle JS SDK

Those three workflow variants are:

- [`.github/workflows/model-emit.yml`](../.github/workflows/model-emit.yml)
- [`.github/workflows/model-emit-curl.yml`](../.github/workflows/model-emit-curl.yml)
- [`.github/workflows/model-emit-js.yml`](../.github/workflows/model-emit-js.yml)

Once `SLI_TEST` is authenticated and the secret is fresh, you can move to workflow examples and expect OCI-backed steps to work without additional local setup.

GitHub workflows call two actions:

- [`.github/actions/sli-event/action.yml`](../.github/actions/sli-event/action.yml) - that cover both `cli` and `curl`
- [`.github/actions/sli-event-js/action.yml`](../.github/actions/sli-event-js/action.yml) - utilizing native GitHub JavaScript support with `post` registration.

Make sure SLI_TEST session is authenticated and run the workflows.

```bash
.github/actions/oci-profile-setup/setup_oci_github_access.sh \
  --account-type session \
  --profile DEFAULT \
  --session-profile-name SLI_TEST \
  --repo "$(gh repo view --json nameWithOwner -q .nameWithOwner)"
```

Execute below snippet to get GitHub console workflow home, where you can trigger it.

```bash
repo="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
echo "https://github.com/${repo}/actions/workflows/model-emit.yml"
```

Below code does the same from gh cli.

```bash
repo="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
WORKFLOW_FILE=".github/workflows/model-emit.yml"

gh workflow run "$WORKFLOW_FILE" -R "$repo" \
-f simulate-failure=false

RUN_ID=$(gh run list -R "$repo" --workflow "$WORKFLOW_FILE" \
--limit 1 --json databaseId -q '.[0].databaseId')

gh run watch "$RUN_ID" -R "$repo"
```

After the workflow finishes, open the GitHub run page first and confirm that `Main step` and `SLI Report (oci)` both executed. Then open the OCI Logging URL and inspect the newest entries. You should see one event emitted by the workflow path rather than by the manual CLI examples from chapter 3. To observe the failure path, run the same command again with `-f simulate-failure=true` and compare the emitted outcome.

```bash
echo "Open GitHub run:"
echo "https://github.com/${repo}/actions/runs/${RUN_ID}"
```

### 4.3 curl

The `curl` workflow exercises the same emission contract, but without installing OCI CLI on the runner. It restores the same `SLI_TEST` profile and signs direct OCI API requests with the profile material.

```bash
repo="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
WORKFLOW_FILE=".github/workflows/model-emit-curl.yml"

gh workflow run "$WORKFLOW_FILE" -R "$repo" \
  -f simulate-failure=false

RUN_ID="$(
  gh run list -R "$repo" --workflow "$WORKFLOW_FILE" \
    --limit 1 --json databaseId -q '.[0].databaseId'
)"

gh run watch "$RUN_ID" -R "$repo"

echo "Open GitHub run:"
echo "https://github.com/${repo}/actions/runs/${RUN_ID}"
```

After the workflow finishes, confirm that `Main step` and `SLI Report (curl)` both executed. This validates the direct OCI API backend.

### 4.4 js

The `js` workflow exercises the Oracle JavaScript SDK path. It uses the same OCI profile but reports through the JavaScript action variant registered with a GitHub `post` hook.

```bash
repo="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
WORKFLOW_FILE=".github/workflows/model-emit-js.yml"

gh workflow run "$WORKFLOW_FILE" -R "$repo" \
  -f simulate-failure=false

RUN_ID="$(gh run list -R "$repo" --workflow "$WORKFLOW_FILE" \
--limit 1 --json databaseId -q '.[0].databaseId'
)"

gh run watch "$RUN_ID" -R "$repo"

echo "Open GitHub run:"
echo "https://github.com/${repo}/actions/runs/${RUN_ID}"
```

After the workflow finishes, confirm that `Main step` and `SLI Report (js)` both executed. This validates the JavaScript SDK backend.

### 4.5 OCI side data view

All three workflow variants now emit OCI log data and OCI Monitoring data in one step. The backend changes from `oci-cli` to `curl` to `js`, but the operator outcome is the same: one workflow run should produce both searchable log records and monitoring datapoints.

Open OCI Console to confirm that log entry was added.

```bash
LOG_ID="$(gh variable get SLI_OCI_LOG_ID -R "$repo")"
LOG_GROUP_ID="$(gh variable get SLI_OCI_LOG_GROUP_ID -R "$repo")"
OCI_REGION="$(echo "$LOG_ID" | cut -d. -f4)"

echo "Open OCI Logging console:"
echo "https://cloud.oracle.com/logging/logs/${LOG_ID}/log-groups/${LOG_GROUP_ID}/explore-log?region=${OCI_REGION}"
```

Finally open OCI Metric Explorer to see that monitoring metric is in place.

```bash
echo "Open OCI Metric Explorer:"
echo "https://cloud.oracle.com/monitoring/explore?region=${OCI_REGION}"
```

Note that URL invoke does not accept any parameters, and you need to select compartment `SLI_tracker`, namespace `sli_tracker_manual`, metric name `sli`, and press `Update chart`. You should see a single point near the right edge of the chart. Press `Show Data Table` to inspect the raw datapoint.

## 5. Router and Ingest Hands-On

This chapter walks through the router from the simplest possible local case to the deployed public ingest Function. Each section is runnable on its own and leaves a visible artifact you can inspect. The progression is:

1. transform one document with JSONata locally — no routing, no OCI
2. route one envelope to a local file — router on, OCI off
3. route a real GitHub `workflow_run` shape with the project mapping
4. fan-out one envelope to two file destinations
5. batch route a directory of envelopes
6. deploy the public router Function to OCI
7. send a webhook to the deployed Function
8. verify ingest in Object Storage
9. verify fan-out to OCI Monitoring and Logging

### 5.1 Key Concepts

**Envelope** — the unit the router operates on. It has three top-level keys:

```json
{
  "headers":     { "X-GitHub-Event": "workflow_run" },
  "body":        { "workflow_run": { "conclusion": "success" }, "repository": { "full_name": "acme/repo" } },
  "source_meta": { "file_name": "event.json" }
}
```

Route matching sees the whole envelope, headers and body alike. JSONata mappings run on `body` directly, so a mapping reads `workflow_run.conclusion`, not `body.workflow_run.conclusion`.

**Route** — a match condition, a mapping, and a destination label. The label is a logical name resolved by the `adapters` section. The route expresses intent; the adapter expresses deployment behavior.

**Transformation** — the step that converts the incoming `body` into a destination-specific shape using a JSONata mapping file. The same body can be transformed differently for each destination: one mapping produces an OCI Logging entry, another produces an OCI Monitoring metric datapoint, a third passes the body through unchanged for archiving. Transformation is what makes the router reusable across different sinks without changing router code.

**Route modes** — `exclusive` means at most one exclusive route fires per envelope. `fanout` routes always fire alongside the first exclusive match. In production, a `workflow_run` event fires one exclusive route (Object Storage archive) plus two fanout routes (OCI Monitoring, OCI Logging) from the same envelope.

**Adapter** — the concrete implementation behind a destination label. Swapping local file adapters for OCI adapters requires only a change to the `adapters` block, not to route definitions.

The diagram below shows the structural view of the router: the major components and how they relate to each other. The envelope enters on the left, passes through the router which consults the routing definition, dispatches to the destination dispatcher, and arrives at one or more adapters.

<p align="center"><img src="../model/router.jpg" alt="Router structural view" width="50%"></p>

The next diagram shows the runtime behavioral view: how a single envelope moves through the system step by step. The router first evaluates all route matches, then for each matched route it runs the assigned JSONata mapping against `body`, and finally hands the transformed output to the adapter for delivery. Fanout routes repeat this transform-and-deliver step for every matching route before the call returns.

<p align="center"><img src="../model/router_runtime.jpg" alt="Router runtime behavioral view" width="50%"></p>

Core files:

- [`tools/json_router.js`](../tools/json_router.js)
- [`tools/json_transformer.js`](../tools/json_transformer.js)
- [`tools/json_router_cli.js`](../tools/json_router_cli.js)
- [`fn/router_passthrough/func.js`](../fn/router_passthrough/func.js)

### 5.2 Step 1 — Transform a Document with JSONata

`json_transform_cli.js` applies one JSONata mapping to one JSON document. There is no routing and no OCI at this step. It is the right tool to debug a mapping expression in isolation before connecting it to a route.

#### Inline expression from stdin

```bash
echo '{"value":21}' | \
node tools/json_transform_cli.js \
  --mapping <(echo '{"expression":"{\"out\": value * 2}"}') \
  --pretty
```

Expected output:

```json
{ "out": 42 }
```

#### Transform with a real project mapping

The project ships a mapping that converts a GitHub `workflow_run` body into an OCI Logging entry shape. Apply it to the sample fixture:

```bash
node tools/json_transform_cli.js \
  --mapping tools/mappings/github_workflow_run_to_oci_log.jsonata \
  --input tests/fixtures/github_webhook_samples/workflow_run.json \
  --pretty
```

You should see a `logEntryBatches` structure containing `outcome`, `workflow`, `branch`, `repo`, and a live timestamp from `$now()`. This is the exact shape the OCI Logging adapter expects when the same mapping runs inside the router.

### 5.3 Step 2 — Route One Envelope to a File

The simplest router case: one route, one `file_system` destination, no OCI. The mapping `$` passes the body through unchanged.

#### Route from a file

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
      "match": { "required_fields": ["audit.id"] },
      "transform": { "mapping": "./mapping_file.jsonata" },
      "destination": { "type": "file_system", "name": "audit_copy" }
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

The `--pretty` output shows `"status": "routed"` with a delivery record for `audit_to_file`. The delivered file appears under `$TMP_DIR/file_system/audit_copy/`.

#### Route from stdin

```bash
cat <<'EOF' | node tools/json_router_cli.js \
      --routing "$TMP_DIR/routing.json" \
      --pretty
{
  "body": {
    "audit": {
      "id": "A-2",
      "message": "via stdin"
    }
  }
}
EOF
```

#### Adapter label and write location

The route uses the label `"name": "audit_copy"`. Without an explicit adapter entry the router writes to `$TMP_DIR/file_system/audit_copy/`. To redirect the write, add an `adapters` block:

```json
{
  "adapters": {
    "file_system:audit_copy": {
      "directory": "out/custom_location"
    }
  }
}
```

The route definition stays unchanged. Only the adapter block controls where data lands, which is the same mechanism used later when switching from local files to OCI Object Storage.

### 5.4 Step 3 — Route a GitHub Webhook with a Real Mapping

Use the project's actual `workflow_run` fixture and the OCI Logging mapping. The route matches on the `X-GitHub-Event` header.

```bash
TMP_DIR="$(mktemp -d /tmp/sli_router_wfrun.XXXXXX)"
cp tools/mappings/github_workflow_run_to_oci_log.jsonata "$TMP_DIR/"

cat > "$TMP_DIR/routing.json" <<'EOF'
{
  "routes": [
    {
      "id": "workflow_to_log_shape",
      "match": { "headers": { "X-GitHub-Event": "workflow_run" } },
      "transform": { "mapping": "./github_workflow_run_to_oci_log.jsonata" },
      "destination": { "type": "file_system", "name": "workflow_logs" }
    }
  ]
}
EOF

jq -n \
  --argjson body "$(cat tests/fixtures/github_webhook_samples/workflow_run.json)" \
  '{"headers": {"X-GitHub-Event": "workflow_run"}, "body": $body}' \
  > "$TMP_DIR/envelope.json"

node tools/json_router_cli.js \
  --routing "$TMP_DIR/routing.json" \
  --input "$TMP_DIR/envelope.json" \
  --pretty

cat "$TMP_DIR/file_system/workflow_logs/"*.json | jq
```

The delivered file contains a `logEntryBatches` structure ready for the OCI Logging adapter. Note that the mapping reads `workflow_run.conclusion` directly — not `body.workflow_run.conclusion` — because the transformer receives `body` as its root context.

### 5.5 Step 4 — Fan-Out One Envelope to Two Destinations

`fanout` routes fire alongside the first exclusive match. This step reproduces the production pattern for `workflow_run`: one archive copy plus one transformed shape.

```bash
TMP_DIR="$(mktemp -d /tmp/sli_router_fanout.XXXXXX)"
cp tools/mappings/github_workflow_run_to_oci_log.jsonata "$TMP_DIR/"
echo '$' > "$TMP_DIR/passthrough.jsonata"

cat > "$TMP_DIR/routing.json" <<'EOF'
{
  "routes": [
    {
      "id": "workflow_run_archive",
      "mode": "exclusive",
      "match": { "headers": { "X-GitHub-Event": "workflow_run" } },
      "transform": { "mapping": "./passthrough.jsonata" },
      "destination": { "type": "file_system", "name": "raw_archive" }
    },
    {
      "id": "workflow_run_to_log_shape",
      "mode": "fanout",
      "match": { "headers": { "X-GitHub-Event": "workflow_run" } },
      "transform": { "mapping": "./github_workflow_run_to_oci_log.jsonata" },
      "destination": { "type": "file_system", "name": "log_shape" }
    }
  ]
}
EOF

jq -n \
  --argjson body "$(cat tests/fixtures/github_webhook_samples/workflow_run.json)" \
  '{"headers": {"X-GitHub-Event": "workflow_run"}, "body": $body}' \
  > "$TMP_DIR/envelope.json"

node tools/json_router_cli.js \
  --routing "$TMP_DIR/routing.json" \
  --input "$TMP_DIR/envelope.json" \
  --pretty

echo "--- raw archive ---"
cat "$TMP_DIR/file_system/raw_archive/"*.json | jq

echo "--- log shape ---"
cat "$TMP_DIR/file_system/log_shape/"*.json | jq
```

The `--pretty` output shows two deliveries. The `raw_archive` destination has the original body unchanged. The `log_shape` destination has the `logEntryBatches` structure from the mapping. In production the two fanout destinations are OCI Object Storage and OCI Logging instead of two file directories.

### 5.6 Step 5 — Batch Route a Source Directory

Batch mode feeds a directory of envelope files through the same routing definition and writes results to an output tree.

```bash
SRC_DIR="$(mktemp -d /tmp/sli_router_batch_src.XXXXXX)"
OUT_DIR="$(mktemp -d /tmp/sli_router_batch_out.XXXXXX)"
TMP_DIR="$(mktemp -d /tmp/sli_router_batch_cfg.XXXXXX)"
cp tools/mappings/github_workflow_run_to_oci_log.jsonata "$TMP_DIR/"
echo '$' > "$TMP_DIR/passthrough.jsonata"

# Write several envelopes into the source directory.
for conclusion in success success failure success; do
  jq -n \
    --arg c "$conclusion" \
    --argjson body "$(cat tests/fixtures/github_webhook_samples/workflow_run.json)" \
    '{"headers": {"X-GitHub-Event": "workflow_run"}, "body": ($body | .workflow_run.conclusion = $c)}' \
    >> "$SRC_DIR/batch_$(date +%s%N).json"
done

cat > "$TMP_DIR/routing.json" <<'EOF'
{
  "routes": [
    {
      "id": "workflow_run_archive",
      "mode": "exclusive",
      "match": { "headers": { "X-GitHub-Event": "workflow_run" } },
      "transform": { "mapping": "./passthrough.jsonata" },
      "destination": { "type": "file_system", "name": "raw_archive" }
    },
    {
      "id": "workflow_run_to_log_shape",
      "mode": "fanout",
      "match": { "headers": { "X-GitHub-Event": "workflow_run" } },
      "transform": { "mapping": "./github_workflow_run_to_oci_log.jsonata" },
      "destination": { "type": "file_system", "name": "log_shape" }
    }
  ]
}
EOF

node tools/json_router_cli.js \
  --routing "$TMP_DIR/routing.json" \
  --source-dir "$SRC_DIR" \
  --output-dir "$OUT_DIR" \
  --pretty

echo "Files written to $OUT_DIR:"
find "$OUT_DIR" -type f | sort
```

Each source file produces one or more output files under the named destination directories inside `$OUT_DIR`. Fanout routes multiply the output: four input envelopes produce four files under `raw_archive` and four files under `log_shape`.

### 5.7 Step 6 — Deploy the Public Router Function

The OCI Function is the public webhook listener. It accepts POST requests through an API Gateway endpoint, runs the same router logic, and delivers to OCI Object Storage, OCI Monitoring, and OCI Logging.

#### Prerequisites

- OCI auth — `DEFAULT` profile or `SLI_TEST` profile set up (see §5.13)
- `fn` CLI installed (`brew install fn` on macOS)
- Docker available to the `fn` CLI (required to build the Function image)
- `oci_scaffold` submodule initialized (`git submodule update --init`)

#### Deploy

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

The script is idempotent. On a fresh account it creates the compartment, Fn app, Function, API Gateway, and ingest bucket. On subsequent runs it reuses existing resources and redeploys only the Function code.

#### Read the API Gateway endpoint from the state file

```bash
STATE_FILE="oci_scaffold/state-${NAME_PREFIX}.json"

DEPLOYMENT_ENDPOINT=$(jq -r '.apigw_deployment.endpoint // .apigw.deployment_endpoint // empty' "$STATE_FILE")
ROUTE_PATH=$(jq -r '.inputs.apigw_route_path // "/"' "$STATE_FILE")
ROUTER_URL="${DEPLOYMENT_ENDPOINT%/}/${ROUTE_PATH#/}"

echo "Router endpoint: $ROUTER_URL"
```

Keep `ROUTER_URL` set for the next steps.

### 5.8 Step 7 — Send a Webhook to the Deployed Function

The Function accepts a JSON envelope with `headers`, `body`, and optional `source_meta`. This is the same envelope structure used by the local CLI.

#### Generic POST (no GitHub header)

A payload without an `X-GitHub-Event` header routes to the `no_github_event` bucket prefix.

```bash
TS="$(date -u +%Y%m%d%H%M%S)"
curl -sS -w "\nHTTP %{http_code}\n" \
  -H "content-type: application/json" \
  --data "$(jq -n --arg fn "test-${TS}.json" \
    '{body: {test: true, ts: $fn}, source_meta: {file_name: $fn}}')" \
  "$ROUTER_URL"
```

Expected response: `{"status":"routed","deliveries":[...]}` with HTTP 200.

#### POST a GitHub ping event

```bash
PING_OBJ="ping-${TS}.json"
curl -sS -w "\nHTTP %{http_code}\n" \
  -H "content-type: application/json" \
  -H "X-GitHub-Event: ping" \
  --data "$(jq -n \
    --arg fn "$PING_OBJ" \
    --argjson b "$(cat tests/fixtures/github_webhook_samples/ping.json)" \
    '{body: $b, headers: {"X-GitHub-Event": "ping"}, source_meta: {file_name: $fn}}')" \
  "$ROUTER_URL"
```

#### POST a completed workflow_run event

```bash
WF_OBJ="wf-${TS}.json"
WF_CREATED="$(date -u -v-5M '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u --date='-5 min' '+%Y-%m-%dT%H:%M:%SZ')"
WF_UPDATED="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

curl -sS -w "\nHTTP %{http_code}\n" \
  -H "content-type: application/json" \
  -H "X-GitHub-Event: workflow_run" \
  --data "$(jq -n \
    --arg fn "$WF_OBJ" \
    --arg c "$WF_CREATED" \
    --arg u "$WF_UPDATED" \
    --argjson b "$(cat tests/fixtures/github_webhook_samples/workflow_run.json)" \
    '{body: ($b | .workflow_run.created_at = $c | .workflow_run.updated_at = $u),
      headers: {"X-GitHub-Event": "workflow_run"},
      source_meta: {file_name: $fn}}')" \
  "$ROUTER_URL"
```

A `workflow_run` envelope fires three routes simultaneously: one exclusive route to Object Storage under `ingest/github/workflow_run/`, one fanout route that posts a metric to OCI Monitoring (`github_actions.workflow_run_result`), and one fanout route that writes a log entry to OCI Logging.

### 5.9 Step 8 — Verify Ingest in Object Storage

Read the bucket namespace and name from the state file, then list and inspect ingest objects.

```bash
NS="$(jq -r '.bucket.namespace' "oci_scaffold/state-${NAME_PREFIX}.json")"
BUCKET="$(jq -r '.bucket.name' "oci_scaffold/state-${NAME_PREFIX}.json")"
export OCI_CLI_PROFILE=DEFAULT

# List newest objects per event prefix.
SLI_OS_NAMESPACE="$NS" SLI_INGEST_BUCKET="$BUCKET" \
  bash tools/list_github_ingest_prefixes.sh --limit 3
```

To fetch the body of one object:

```bash
# Replace with an object key from the listing above.
OBJECT_KEY="ingest/github/workflow_run/${WF_OBJ}"

SLI_OS_NAMESPACE="$NS" SLI_INGEST_BUCKET="$BUCKET" \
  bash tools/get_ingest_object.sh "$OBJECT_KEY" | jq
```

The body should be the original `workflow_run` payload. It is written as-is by the `passthrough.jsonata` mapping (`$`), which is correct for the archive route. The transformed shapes (log entry, metric payload) go to Logging and Monitoring via the fanout routes, not to Object Storage.

### 5.10 Step 9 — Verify Fan-Out to OCI Monitoring and Logging

`validate_router_ingest_and_metrics.sh` reads the state file, lists recent ingest objects, and queries OCI Monitoring for `github_actions.workflow_run_result` datapoints over the last N minutes.

```bash
SLI_OCI_STATE_FILE="oci_scaffold/state-${NAME_PREFIX}.json" \
  bash tools/validate_router_ingest_and_metrics.sh --minutes 45 --limit 5
```

The script reports:

- newest object keys under each `ingest/github/<event>/` prefix
- a JSON peek at the newest `workflow_run` object
- `workflow_run_result` metric datapoints with timestamps and values (1 = success, 0 = other)
- `workflow_run_duration_s` metric datapoints

If the `workflow_run` POST from step 7 has propagated, you should see at least one datapoint with a timestamp close to `$WF_UPDATED` and a value of `1`.

To open OCI Monitoring and inspect the metric interactively:

```bash
REGION="$(jq -r '.inputs.oci_region // empty' "oci_scaffold/state-${NAME_PREFIX}.json")"
echo "Open OCI Metric Explorer: https://cloud.oracle.com/monitoring/explore?region=${REGION}"
```

Select compartment `SLI_tracker`, namespace `github_actions`, metric name `workflow_run_result`, and press `Update chart`.

### 5.11 SLI Calculation

`sli_compute_sli_metrics.js` queries OCI Monitoring for `workflow_run_result` datapoints over a rolling window, then computes `success / total` and publishes the ratio back as a derived SLI metric.

The simplest way to trigger it is via the scheduled GitHub workflow. The workflow authenticates with `SLI_TEST`, queries the metric namespace, and posts the result.

```bash
repo="$(gh repo view --json nameWithOwner -q .nameWithOwner)"

gh workflow run ".github/workflows/sli_compute_sli_metrics.yml" -R "$repo"

RUN_ID="$(gh run list -R "$repo" \
  --workflow "sli_compute_sli_metrics.yml" \
  --limit 1 --json databaseId -q '.[0].databaseId')"

gh run watch "$RUN_ID" -R "$repo"
echo "https://github.com/${repo}/actions/runs/${RUN_ID}"
```

After the run completes, the derived SLI metric is visible in OCI Monitoring under namespace `sli_tracker`, metric name `sli`.

Core files:

- [`tools/sli_compute_sli_metrics.js`](../tools/sli_compute_sli_metrics.js)
- [`.github/workflows/sli_compute_sli_metrics.yml`](../.github/workflows/sli_compute_sli_metrics.yml)

### 5.12 Synthetic Event Generator

`sli_ratio_simulator.sh` injects a controlled stream of success and failure `workflow_run` events into OCI Monitoring. It is used to validate dashboards, alarms, and SLI calculations under known conditions — for example, to confirm that a 75% success ratio produces the expected SLI value.

Run it locally:

```bash
export OCI_CLI_PROFILE=DEFAULT
export COMPARTMENT_OCID="$(jq -r '.compartment.ocid' "oci_scaffold/state-${NAME_PREFIX}.json")"

bash tools/sli_ratio_simulator.sh
```

Or trigger it as a workflow:

```bash
repo="$(gh repo view --json nameWithOwner -q .nameWithOwner)"

gh workflow run ".github/workflows/sli_ratio_simulator.yml" -R "$repo"

RUN_ID="$(gh run list -R "$repo" \
  --workflow "sli_ratio_simulator.yml" \
  --limit 1 --json databaseId -q '.[0].databaseId')"

gh run watch "$RUN_ID" -R "$repo"
```

After the simulator finishes, run `validate_router_ingest_and_metrics.sh` or open OCI Metric Explorer to confirm the injected datapoints are present before triggering `sli_compute_sli_metrics`.

Core files:

- [`tools/sli_ratio_simulator.sh`](../tools/sli_ratio_simulator.sh)
- [`.github/workflows/sli_ratio_simulator.yml`](../.github/workflows/sli_ratio_simulator.yml)

### 5.13 OCI Authentication Profiles

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
