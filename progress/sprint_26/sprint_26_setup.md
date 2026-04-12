# Sprint 26 — Setup (YOLO)

## Contract

RUP simplified manager: YOLO mode — self-approve design, no blocking waits.
`Test: unit, integration`. `Regression: unit` (component-scoped manifest, same as Sprint 24).

Deliver **SLI-41**: fan-out `workflow_run` GitHub webhooks to OCI Monitoring metrics while keeping the existing Object Storage exclusive route. Sprint 24 failed because `router_core.js` could not activate `oci_monitoring` from configuration alone. **Sprint 25 (SLI-42)** delivered config-driven adapter registration; this sprint retries SLI-41 under the updated constraint set: routing configuration, JSONata mapping, fixture and deploy seed updates, and tests — **no further changes to `router_core.js` adapter wiring** beyond what SLI-42 already shipped.

## Analysis

**Feasibility:** Unblocked. The live fixture `tests/fixtures/fn_router_passthrough/routing.json` gains:

1. Adapter entry `oci_monitoring:github_workflow_run` with logical `namespace` metadata aligned to emitted metric namespaces.
2. Fanout route `github_workflow_run_to_metric` (priority 40, header `x-github-event: workflow_run`) with `transform.mapping` `./workflow_run_metric.jsonata` and destination `oci_monitoring` / `github_workflow_run`.
3. The existing exclusive route `github_workflow_run_to_bucket` remains unchanged so completed and in-progress payloads still land under `ingest/github/workflow_run/`.

**JSONata** (`tests/fixtures/fn_router_passthrough/workflow_run_metric.jsonata`): Implements the Sprint 23 design note — emit only when `action = "completed"` and `conclusion` is in the SLI-relevant set; produce `workflow_run_result` (1/0) and `workflow_run_duration_s` from `created_at` / `updated_at`.

**Operator / CI:** `tools/cycle_apigw_router_passthrough.sh` uploads the new mapping to `config/workflow_run_metric.jsonata` and merges `OCI_MONITORING_COMPARTMENT_ID` and `OCI_REGION` into Fn configuration so live `postMetricData` can succeed when the stack is exercised.

**Unit tests:** Extend `tests/unit/test_fn_passthrough_router.sh` — completed sample produces one `postMetricData` call with two metric definitions; `workflow_run_requested.json` sample produces Object Storage only.

**Open questions:** None critical. Skipped/neutral conclusions continue to map to `[]` per design note (no SLI signal).
