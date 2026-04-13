# Sprint 27 — Setup (YOLO)

## Contract

RUP simplified manager (`rup_manager_simplified.md`): **YOLO** mode — self-approve design, no blocking waits. **`Test: unit, integration`**. **`Regression: unit`** (reuse Sprint 26 component-scoped router/transformer manifest pattern).

Deliver **SLI-44** (`BACKLOG.md`): fan-out GitHub `workflow_run` to **OCI Logging** in addition to the existing Object Storage archive and OCI Monitoring metrics (Sprint 26 / SLI-41). This sprint **opens** the work: inception and design are binding; full adapter implementation may continue in the same sprint or a follow-up increment per capacity.

Constraints:

- Reuse **SLI-42** config-driven adapter pattern: new `oci_logging:*` adapter entries in `routing.json` must activate only when present; no hardcoded one-off in `router_core` beyond the generic registration rule.
- Reuse **SLI-43** semantics: additional **`fanout`** routes compose with the existing **`exclusive`** bucket route (`selectRoutes` contract).
- IAM, log OCID / log group discovery, payload shape, PII retention, and “log every run vs completed-only” are **design decisions** recorded in `sprint_27_design.md`.

## Analysis

**Feasibility:** Medium. OCI Logging ingestion from Oracle Functions is already established elsewhere in the repo (`emit.sh`, integration tests). The gap is a **router destination adapter** (parallel to `oci_monitoring` / `oci_object_storage`) that accepts JSONata-shaped log payloads, resolves log OCID from Fn config (or URI-style scaffold inputs), and calls PutLogEvents (or equivalent) under **Resource Principal**.

**Routing:** Add adapter e.g. `oci_logging:github_workflow_run` and route `github_workflow_run_to_log` with `mode: fanout`, same header match as bucket + metric routes, `transform.mapping` TBD (dedicated JSONata vs reuse passthrough for raw JSON — design choice).

**Operator path:** Extend `tools/cycle_apigw_router_passthrough.sh` (or companion env) to upload new mapping, merge `SLI_OCI_LOG_ID` / log group variables into Fn config, and extend policies for Logging use.

**Risks:** Log payload size limits; duplicate delivery if idempotency not considered; secrets in raw webhook bodies landing in logs.

**Open questions:** (1) Log all `workflow_run` states or only completed (mirror metrics)? (2) Single log vs per-repo log? (3) Schema of log entry for downstream search.
