# Sprint 14 — Design

## SLI-20: Rolling-window SLI from OCI Monitoring (Node.js)

Status: Accepted (YOLO — self-approved)

### Requirement Summary

Provide a Node.js tool that computes SLI from the emitted `outcome` metric over a configurable rolling window (default 30 days). The computation must be parameterized by selected metric dimensions (for example repository/workflow/job) and must return the ratio plus supporting counts for auditability. The computed snapshot must optionally be persisted to OCI Logging and/or OCI Monitoring as configurable outputs.

### Design Overview

**Core idea:** since `outcome` is emitted as 1 (success) and 0 (non-success), SLI over a window is:

- `success_count = sum(outcome)`
- `total_count = count(outcome)`
- `sli = success_count / total_count`

**Query strategy:** use OCI Monitoring `summarizeMetricsData` to retrieve aggregated datapoints over the chosen window and compute totals across the returned buckets.

**Dimension filtering:** accept a set of dimension key/value pairs and apply them consistently so operators can compute per-slice SLI (for example per repo or per workflow/job).

**Persistence:** when enabled, write the computed snapshot (ratio + counts + window + filter) to OCI Logging and/or as a separate Monitoring metric datapoint.

### Technical Constraints

- Tool must run locally and be callable from tests.
- Tests must not require OCI credentials; they should validate computation with fixtures and a dry-run mode.
- Live mode uses the OCI Node.js SDK (config-file + profile).

### Testing Strategy

Test: **unit, integration**. Regression: **unit**.

- **Unit**: validate ratio computation from aggregated datapoints and CLI argument parsing (window length + dimensions).
- **Integration**: run the CLI end-to-end in fixture mode and assert printed output (ratio + counts + filter) is correct.

## Test Specification

### Unit tests

- **UT-1**: compute SLI from sums+counts across multiple buckets (happy path).
- **UT-2**: handles empty dataset (no datapoints) with a clear error or sentinel result.
- **UT-3**: dimension parsing (repeated `--dimension key=value`) is stable.

### Integration tests

- **IT-1**: `--input-file <fixture>` produces correct ratio + counts and prints the applied dimension filter and window.

### Traceability

|Backlog item|Tests|
|---|---|
|SLI-20|UT-1, UT-2, UT-3, IT-1|
