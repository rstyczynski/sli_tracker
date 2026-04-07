# Sprint 14 — Setup

## Contract

Sprint 14 — YOLO mode.

**Scope constraint:** Implement SLI-20 only (Node.js tool for rolling-window SLI from OCI Monitoring metrics; window length parameterized, default 30 days).

**Responsibilities:**

- Define acceptance for dimension-parameterized SLI computation, configurable evaluation window (default 30 days), and optional log/metric persistence.

**Open Questions:** None.

---

## Analysis

### SLI-20: Compute rolling-window SLI from OCI Monitoring metrics by dimensions

Backlog item requires a Node.js tool using the OCI SDK to query Monitoring, compute success ratio over a configurable rolling window (default 30 days) for selected dimensions, and optionally emit the computed snapshot to Logging and/or Monitoring per configuration.
