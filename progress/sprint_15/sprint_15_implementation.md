# Sprint 15 — Implementation

Sprint: 15 | Mode: YOLO | Backlog: SLI-22, SLI-23

## Summary

Implemented two scheduled workflows:

- `SLI-22` every 30 minutes computes rolling-window SLI from OCI Monitoring and persists the snapshot to OCI Logging + OCI Monitoring.
- `SLI-23` hourly runs the synthetic ratio simulator to emit test SLI traffic to OCI Logging + OCI Monitoring.

Both use the token-based `SLI_TEST` profile restored from `secrets.OCI_CONFIG_PAYLOAD` and read OCI resource IDs from repo variables.

## Operator usage

- Trigger on demand (manual):
  - Actions → `SLI-22 — scheduled SLI snapshot (30 min)` → Run workflow
  - Actions → `SLI-23 — scheduled synthetic emitter (hourly)` → Run workflow

## Code artifacts

| File | Purpose |
| --- | --- |
| `.github/workflows/sli_compute_sli_metrics.yml` | 30-minute snapshot workflow (persist log+metric) |
| `.github/workflows/sli_ratio_simulator.yml` | Hourly synthetic emitter workflow |
