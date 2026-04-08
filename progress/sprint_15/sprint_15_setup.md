# Sprint 15 — Setup

Sprint: 15 | Mode: YOLO | Backlog: SLI-22, SLI-23

## Contract

- Goal: deliver two unattended scheduled workflows:
  - SLI-22: every 5 minutes compute rolling-window SLI from OCI Monitoring and persist snapshot to OCI Logging + Monitoring.
  - SLI-23: hourly run the synthetic ratio emitter to generate steady test traffic to OCI Logging + Monitoring.
- Constraints:
  - Must run using token-based `SLI_TEST` OCI profile restored from `secrets.OCI_CONFIG_PAYLOAD`.
  - Must use repo variables for OCI resource identifiers (log OCID, compartment OCID, and metric namespace where applicable).
  - Must be safe to run unattended (no interactive auth).
  - Cron schedules should coexist with manual `workflow_dispatch` runs for operator debugging.
- Quality gates: Unit + Integration for new code; Regression: unit.

## Analysis

- Feasibility: both workflows can reuse existing building blocks already used in other workflows:
  - `.github/actions/oci-profile-setup` for restoring `~/.oci/config` + token session material.
  - `tools/sli_compute_sli_metrics.js` for SLI computation and persistence (`--persist log,metric`).
  - `tools/sli_ratio_simulator.sh` for synthetic emission, configured using the same env vars as `emit.sh`.
- Compatibility:
  - Scheduled workflows require repo variables to exist: `SLI_OCI_COMPARTMENT_ID`, `SLI_OCI_LOG_ID` (and optionally `SLI_METRIC_NAMESPACE` or default `sli_tracker`).
  - Persisting SLI snapshots to Monitoring requires telemetry-ingestion endpoint; already handled by the tool.
- Risks:
  - Schedule cadence: GitHub cron is best-effort and may drift; acceptance should tolerate delays.
  - Token expiration: `OCI_CONFIG_PAYLOAD` must be refreshed before it expires; workflows should fail clearly when auth is invalid.
