# Sprint 26 — Tests (YOLO)

Sprint mode: **YOLO**. `Test: unit, integration`. `Regression: unit`.

## Status: PASS

## Artifacts

| Gate | Log |
| --- | --- |
| A2 Unit (`--new-only progress/sprint_26/new_tests.manifest`) | `progress/sprint_26/test_run_A2_unit_20260412_143035.log` |
| A3 Integration (`--new-only progress/sprint_26/new_tests.manifest`) | `progress/sprint_26/test_run_A3_integration_20260412_143056.log` |
| B2 Unit regression (`--manifest progress/sprint_26/regression_tests.manifest`) | `progress/sprint_26/test_run_B2_unit_20260412_143332.log` |

Phase B integration regression not in `Regression:` parameter (unit-only), so B3 full integration regression was not a sprint gate. **SLI-41-2** (mapping loader) and **SLI-41-1** (live Monitoring) were re-verified with the targeted commands below (tee optional for audit).

## Targeted verification (router + metric ingest)

Use when you want **routing / Monitoring ingest** without `tests/run.sh --all` (avoids unrelated suites such as Podman-backed `test_install_oci_cli.sh`).

```bash
# Unit: router core, monitoring adapter, SLI-41-2 mapping resolution
bash tests/unit/test_fn_passthrough_router.sh

# Integration: API GW → Fn → Object Storage + SLI-41-1 Monitoring poll (deploys if FN_FORCE_DEPLOY set by cycle)
bash tests/integration/test_fn_apigw_object_storage_passthrough.sh
```

Optional log (RUP-style):

```bash
TS="$(date -u '+%Y%m%d_%H%M%S')"
LOG="progress/sprint_26/test_run_router_metrics_targeted_${TS}.log"
( bash tests/unit/test_fn_passthrough_router.sh && \
  bash tests/integration/test_fn_apigw_object_storage_passthrough.sh ) 2>&1 | tee "$LOG"
```

Post-run operator check (metric definitions; compartment from scaffold state):

```bash
SLI_OCI_STATE_FILE=oci_scaffold/state-sli-router-passthrough-dev.json \
  ./tools/list_monitoring_metrics.sh --limit 50
```

Bucket + metric **values** (Object Storage newest keys, optional body peek, Monitoring `summarize-metrics-data`):

```bash
SLI_OCI_STATE_FILE=oci_scaffold/state-sli-router-passthrough-dev.json \
  ./tools/validate_router_ingest_and_metrics.sh --minutes 90
```

## Summary

- Phase A: new-code unit + integration PASS.
- Phase B: component-scoped unit regression PASS (14 scripts).
- Bugfix cycle: **SLI-41-1** (integration asserts `workflow_run` → Monitoring), **SLI-41-2** (`router_core` mapping load + unit guard); details in `progress/sprint_26/sprint_26_bugfixes.md`.
