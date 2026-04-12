# Sprint 26 — Implementation (SLI-41)

## Status: DONE

## Summary

Delivered configuration-only SLI-41 now that SLI-42 registers `oci_monitoring` from `routing.json` keys.

### Files

| Area | Change |
| --- | --- |
| `tests/fixtures/fn_router_passthrough/routing.json` | `oci_monitoring:github_workflow_run` adapter + fanout route `github_workflow_run_to_metric` |
| `tests/fixtures/fn_router_passthrough/workflow_run_metric.jsonata` | New JSONata filter and dual-metric payload |
| `tests/fixtures/github_webhook_samples/workflow_run.json` | Added `event`, `created_at`, `updated_at` for duration |
| `tests/fixtures/github_webhook_samples/workflow_run_requested.json` | New sample for non-completed runs |
| `tests/unit/test_fn_passthrough_router.sh` | SLI-41 assertions: metrics for completed run, none for requested; FDK path |
| `tools/cycle_apigw_router_passthrough.sh` | Upload `config/workflow_run_metric.jsonata`; Fn config `OCI_MONITORING_COMPARTMENT_ID` + `OCI_REGION` |
| `fn/router_passthrough/func.yaml` | Version `0.0.30` |

### Runtime

- `router_core.js` unchanged in this sprint (SLI-42 already wires monitoring).
- Operators must set `OCI_MONITORING_COMPARTMENT_ID` (cycle script sets it to the scaffold compartment for dev stacks).
