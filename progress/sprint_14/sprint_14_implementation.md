# Sprint 14 — Implementation

Sprint: 14 | Mode: YOLO | Backlog: SLI-20

## SLI-20: Rolling-window SLI from OCI Monitoring (Node.js)

Status: implemented

### Summary

Added a Node.js CLI that computes SLI (success ratio) over a configurable rolling window (default 30 days) from OCI Monitoring `outcome` metrics, parameterized by dimensions. The tool supports fixture mode for deterministic tests and live OCI query mode via OCI config file + profile. Optional persistence to OCI Logging and/or OCI Monitoring is supported via flags.

### Operator usage

Fixture mode (no OCI access):

```bash
tools/sli_compute_sli_metrics.js \
  --input-file tests/fixtures/sli_compute_metrics_sample.json \
  --window-days 30 \
  --dimension repo_repository=rstyczynski/sli_tracker \
  --dimension workflow_job=emit-metric-local \
  --output json
```

Live mode (OCI Monitoring query via Node SDK):

```bash
tools/sli_compute_sli_metrics.js \
  --oci-auth config \
  --window-days 30 \
  --mql-resolution 1d \
  --namespace sli_tracker \
  --metric-name outcome \
  --compartment-id "<compartment-ocid>" \
  --oci-config-file "~/.oci/config" \
  --oci-profile "SLI_TEST" \
  --dimension repo_repository="rstyczynski/sli_tracker" \
  --output text
```

For “live-moving” numbers while you’re actively emitting datapoints, use a smaller MQL resolution, e.g. 5 minutes:

```bash
tools/sli_compute_sli_metrics.js \
  --oci-auth config \
  --window-days 1 \
  --mql-resolution 5m \
  --namespace sli_tracker \
  --metric-name outcome \
  --compartment-id "<compartment-ocid>" \
  --oci-config-file "~/.oci/config" \
  --oci-profile "SLI_TEST" \
  --output text
```

Instance Principal mode (run on OCI Compute with dynamic group + policy):

```bash
tools/sli_compute_sli_metrics.js \
  --oci-auth instance_principal \
  --window-days 30 \
  --namespace sli_tracker \
  --metric-name outcome \
  --compartment-id "<compartment-ocid>" \
  --output text
```

Optional persistence (add `--persist` targets):

```bash
SLI_OCI_LOG_ID=
SLI_METRIC_COMPARTMENT=
tools/sli_compute_sli_metrics.js \
  --oci-auth config \
  --window-days 30 \
  --namespace sli_tracker \
  --metric-name outcome \
  --compartment-id "$COMPARTMENT_OCID" \
  --oci-config-file "~/.oci/config" \
  --oci-profile "SLI_TEST" \
  --persist log,metric \
  --persist-log-id "$SLI_OCI_LOG_ID" \
  --persist-metric-namespace "sli_tracker" \
  --output json
```

### Code Artifacts

|File|Change|
|---|---|
|`tools/sli_compute_sli_metrics.js`|New CLI tool (fixture-first; live mode stub)|
|`tests/fixtures/sli_compute_metrics_sample.json`|Fixture buckets for deterministic tests|
|`tests/unit/test_sli_compute_sli_metrics.sh`|Unit tests for ratio + dimension parsing|
|`tests/integration/test_sli_compute_sli_metrics.sh`|Integration test for CLI text output|

### Bugs

See `progress/sprint_14/sprint_14_bugs.md`.
