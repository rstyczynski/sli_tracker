# Sprint 26 — Design (SLI-41 retry)

## Problem

GitHub `workflow_run` webhooks are stored in OCI Object Storage. Operators also need time-series metrics (outcome and duration) in OCI Monitoring without parsing stored JSON. Sprint 24 proved that fan-out to `oci_monitoring` could not work until the Fn router registered that adapter from `routing.json`; Sprint 25 closed that gap.

## Design

### Routing (`tests/fixtures/fn_router_passthrough/routing.json`)

- Add `oci_monitoring:github_workflow_run` under `adapters` with `{ "namespace": "github_actions" }` (logical metadata; compartment comes from `OCI_MONITORING_COMPARTMENT_ID` at runtime per SLI-42).
- Add route `github_workflow_run_to_metric`: `mode: fanout`, same header match as the existing bucket route, `transform.mapping: ./workflow_run_metric.jsonata`, `destination: { "type": "oci_monitoring", "name": "github_workflow_run" }`.
- Keep `github_workflow_run_to_bucket` as the exclusive Object Storage route so `selectRoutes` yields the exclusive winner plus all matching fanout routes.

### JSONata (`workflow_run_metric.jsonata`)

Filter: `action = "completed"` and `workflow_run.conclusion` in `success`, `failure`, `cancelled`, `timed_out`, `action_required`. Otherwise emit `[]`.

Emit two metrics (namespace `github_actions`): `workflow_run_result` (value 1 for success, 0 otherwise) and `workflow_run_duration_s` (seconds from timestamps), with shared dimensions: repository, workflow, branch, event, conclusion.

### Samples

- Enrich `tests/fixtures/github_webhook_samples/workflow_run.json` with `event`, `created_at`, `updated_at` for duration evaluation.
- Add `workflow_run_requested.json` for the negative metric path (Object Storage only).

### Deploy seed (`tools/cycle_apigw_router_passthrough.sh`)

Upload `workflow_run_metric.jsonata` to `config/workflow_run_metric.jsonata`. Extend Fn config merge with `OCI_MONITORING_COMPARTMENT_ID` (stack compartment) and `OCI_REGION`.

### Version

Bump `fn/router_passthrough/func.yaml` patch version so integration runs pick up handler changes when required.

---

## Testing Strategy

**Scope:** Unit tests in `test_fn_passthrough_router.sh` validate dual delivery (Object Storage + monitoring stub) using the real fixture `routing.json` and local `loadMappingFromRef` for both `passthrough.jsonata` and `workflow_run_metric.jsonata`. Integration: existing `test_fn_apigw_object_storage_passthrough.sh` re-seeds bucket routing and mappings and proves the stack still deploys and ingests (regression on cycle script + Fn config).

**Regression:** Component-scoped unit manifest (same list as Sprint 25).

---

## Test Specification

### UT-SLI41-1 — Completed `workflow_run`: bucket + metrics

| ID | Input | Expect |
| --- | --- | --- |
| UT-SLI41-1 | `workflow_run.json` + header `X-GitHub-Event: workflow_run` | One `putObject` under `ingest/github/workflow_run/`; one `postMetricData` with `metricData.length === 2`, names `workflow_run_result` and `workflow_run_duration_s`, `compartmentId` injected |

### UT-SLI41-2 — Requested `workflow_run`: bucket only

| ID | Input | Expect |
| --- | --- | --- |
| UT-SLI41-2 | `workflow_run_requested.json` + same header | One `putObject`; zero `postMetricData` calls |

### UT-SLI41-3 — FDK gateway header path

| ID | Input | Expect |
| --- | --- | --- |
| UT-SLI41-3 | Completed body + `fdkContext.httpGateway` headers | Same metric behavior as UT-SLI41-1 |

### IT-SLI41-1 — APIGW cycle (manifest)

| ID | Script | Expect |
| --- | --- | --- |
| IT-SLI41-1 | `test_fn_apigw_object_storage_passthrough.sh` | PASS (routing + mappings uploaded; POST smoke paths succeed) |

### Traceability

| Test | Requirement |
| --- | --- |
| UT-SLI41-1..3 | SLI-41 metric fan-out + filter |
| IT-SLI41-1 | SLI-41 operator seed + Fn config |
