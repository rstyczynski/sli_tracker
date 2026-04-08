# Sprint 15 — Design

Sprint: 15 | Mode: YOLO | Backlog: SLI-22, SLI-23

## Overview

Implement two scheduled GitHub Actions workflows that operate unattended using the token-based `SLI_TEST` OCI profile restored from `secrets.OCI_CONFIG_PAYLOAD`:

- **SLI-22 (every 30 minutes)**: compute rolling-window SLI from OCI Monitoring `outcome` metrics and persist a snapshot to OCI Logging + OCI Monitoring (`sli_ratio` datapoint).
- **SLI-23 (hourly)**: generate synthetic success/failure traffic by running `tools/sli_ratio_simulator.sh`, using the same env variables as the local operator flow in `README.md`.

Both workflows should support `workflow_dispatch` in addition to cron scheduling.

## Inputs and configuration (repo-level)

- **Repo secret**: `OCI_CONFIG_PAYLOAD` (packed `~/.oci/config` + session directory)
- **Repo variables**:
  - `SLI_OCI_COMPARTMENT_ID` (compartment OCID for metrics and for the SLI snapshot metric datapoint)
  - `SLI_OCI_LOG_ID` (target OCI Log OCID for emit + snapshot persistence)
  - `SLI_METRIC_NAMESPACE` (optional; default `sli_tracker`)

## Scheduled workflow design

### Workflow A — SLI snapshot (SLI-22)

- Restore OCI profile via `./.github/actions/oci-profile-setup` with `profile: SLI_TEST` and `oci-auth-mode: token_based`.
- Run `tools/sli_compute_sli_metrics.js` with:
  - `--window-days 30` (default rolling window)
  - `--mql-resolution 5m` (stable while still reasonably fresh)
  - `--persist log,metric`
  - `--persist-log-id $SLI_OCI_LOG_ID`
  - `--persist-metric-namespace $SLI_METRIC_NAMESPACE` (or default)
- Output JSON to workflow logs for auditability.

### Workflow B — synthetic emitter (SLI-23)

- Restore OCI profile via `oci-profile-setup` (same as above).
- Set env for `emit.sh` / simulator:
  - `EMIT_BACKEND=curl`
  - `EMIT_TARGET=log,metric`
  - `SLI_OCI_LOG_ID`, `SLI_METRIC_COMPARTMENT`, `SLI_METRIC_NAMESPACE`
  - `SLI_CONTEXT_JSON` points at `~/.oci/config` and `SLI_TEST`
- Run `tools/sli_ratio_simulator.sh` with a short, bounded duration suitable for hourly runs (to be defined in implementation, but must not exceed runner limits).

## Failure behavior

- Workflows must fail loudly if required repo variables are missing.
- Token expiration should manifest as an OCI auth error; no retries beyond workflow rerun.

### Testing Strategy

We will use fast, non-flaky tests that validate workflow wiring without requiring live OCI:

- **Unit**: validate the presence and shape of the two new workflow YAML files (cron schedules, required steps/inputs, and use of `SLI_TEST` / `OCI_CONFIG_PAYLOAD`).
- **Integration (new-code manifest)**: run a repo-local script that parses both workflow YAMLs and asserts key invariants (same checks as unit, but run under the integration gate to match sprint parameters).

## Test Specification

### UT-1 — workflow files exist and schedules are correct

- **Traceability**: SLI-22, SLI-23
- **Method**: parse `.github/workflows/*.yml` and assert:
  - SLI-22 has `schedule` with `*/30` minutes
  - SLI-23 has hourly `schedule`
  - both expose `workflow_dispatch`

### UT-2 — workflows use token-based `SLI_TEST` + OCI_CONFIG_PAYLOAD

- **Traceability**: SLI-22, SLI-23
- **Method**: assert each workflow includes `oci-profile-setup` step with:
  - `oci_config_payload: ${{ secrets.OCI_CONFIG_PAYLOAD }}`
  - `profile: SLI_TEST`
  - `oci-auth-mode: token_based`

### UT-3 — workflows use repo variables for OCIDs

- **Traceability**: SLI-22, SLI-23
- **Method**: assert each workflow reads:
  - `vars.SLI_OCI_COMPARTMENT_ID`
  - `vars.SLI_OCI_LOG_ID`

### IT-1 — integration gate: YAML invariants script passes

- **Traceability**: SLI-22, SLI-23
- **Method**: run the same validation script under integration gate.
