# Sprint 12 — Implementation

Sprint: 12 | Mode: YOLO | Backlog: SLI-17

## SLI-17: OCI Monitoring metric output

Status: implemented

### Summary

Added `EMIT_TARGET` env var (default `log,metric`) to both emit backends. When `metric` is
included a signed POST is sent to the OCI Monitoring telemetry-ingestion endpoint using the
same RSA-SHA256 signing already proven in `emit_curl.sh`.

### Bugs

See `progress/sprint_12/sprint_12_bugs.md`.

### Code Artifacts

| File | Change |
| --- | --- |
| `.github/actions/sli-event/emit_common.sh` | Added `sli_outcome_to_metric_value()` and `sli_emit_metric()` |
| `.github/actions/sli-event/emit_curl.sh` | EMIT_TARGET guard on log push; metric push call |
| `.github/actions/sli-event/emit_oci.sh` | EMIT_TARGET guard on OCI CLI log push; metric push call |

### Key Implementation Details

**`sli_outcome_to_metric_value(outcome)`** — `success`→`1`, anything else→`0`

**`sli_emit_metric(log_entry, oci_config, oci_profile)`:**

- Reads profile fields directly (region, tenancy, key_file, fingerprint, security_token_file)
- Builds MetricData payload: namespace `sli_tracker` (or `$SLI_METRIC_NAMESPACE`), name `outcome`,
  compartmentId from `SLI_METRIC_COMPARTMENT` or tenancy OCID, dimensions from workflow and repo fields
- Signs with identical RSA-SHA256 algorithm to the logging path
- Endpoint: `https://telemetry-ingestion.{region}.oci.oraclecloud.com/20180401/metrics`
- HTTP 2xx → success notice; non-2xx → warning (non-fatal)

**EMIT_TARGET flow in both backends:**

```bash
local EMIT_TARGET="${EMIT_TARGET:-log,metric}"
# skip everything if SLI_SKIP_OCI_PUSH is set
if [[ "$EMIT_TARGET" == *log* ]];    then  # log push (existing code, needs OCI_LOG_ID)
if [[ "$EMIT_TARGET" == *metric* ]]; then  # sli_emit_metric() — no log-id needed
```

### Environment Variables

| Variable | Default | Description |
| --- | --- | --- |
| `EMIT_TARGET` | `log,metric` | `log`, `metric`, or both comma-separated |
| `SLI_METRIC_NAMESPACE` | `sli_tracker` | OCI Monitoring namespace |
| `SLI_METRIC_COMPARTMENT` | tenancy from OCI profile | compartmentId for OCI Monitoring (required by API; defaults to `tenancy` profile field) |
| `SLI_SKIP_OCI_PUSH` | unset | Skip all emission when set |

### Backward Compatibility

Default `EMIT_TARGET=log,metric` means existing callers that don't set it will now also
post metrics — additive, non-breaking for log consumers. Log push still requires `OCI_LOG_ID`;
metric push only requires a valid OCI config profile.

### No workflow YAML files were modified
