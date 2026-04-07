# Sprint 12 — Design

## SLI-17: emit.sh — OCI Monitoring metric output

Status: Accepted (YOLO — self-approved)

### Requirement Summary

Add `EMIT_TARGET` env var (values: `log`, `metric`, `log,metric`; default `log,metric`) to
`emit_curl.sh` and `emit_oci.sh`. When `metric` is included, post an `outcome` datapoint
(1=success, 0=other) to OCI Monitoring namespace `sli_tracker` (overridable via
`SLI_METRIC_NAMESPACE`). Changes are limited to `emit_common.sh`, `emit_curl.sh`,
`emit_oci.sh`. No workflow YAML files are touched.

### Feasibility Analysis

**API Availability:**
- OCI Monitoring ingestion endpoint: `POST https://telemetry-ingestion.{region}.oci.oraclecloud.com/20180401/metrics`
- Same RSA-SHA256 signing as OCI Logging — proven working in `emit_curl.sh`
- `compartmentId` required; using tenancy OCID from OCI config profile (YOLO decision)

**Technical Constraints:**
- `emit_oci.sh` uses OCI CLI for logging but OCI CLI has no direct `oci monitoring put-metric-data` for custom ingestion — must use curl for metric emission in both backends
- Session token profiles need `key_file` + `region` (same requirement as logging path)

**Risk Assessment:**
- Tenancy OCID as compartmentId: low risk — sli_tracker metrics live in root compartment; a `SLI_METRIC_COMPARTMENT` override can be added later if needed

### Design Overview

**Architecture:**

```
emit_curl.sh / emit_oci.sh
  └─ sli_emit_main()
       ├─ build LOG_ENTRY (unchanged)
       ├─ [EMIT_TARGET includes log] → existing log push (unchanged logic)
       └─ [EMIT_TARGET includes metric] → sli_emit_metric() in emit_common.sh
```

**New helpers in `emit_common.sh`:**

1. `sli_outcome_to_metric_value(outcome)` — `success`→`1`, anything else→`0`
2. `sli_emit_metric(log_entry, oci_config, oci_profile)` — builds MetricData payload, signs with same RSA-SHA256 algorithm, POSTs to `telemetry-ingestion.{region}.oci.oraclecloud.com`

**EMIT_TARGET handling in both backends:**
```bash
local EMIT_TARGET="${EMIT_TARGET:-log,metric}"
if [[ "$EMIT_TARGET" == *log* ]]; then   # log push (current code)
if [[ "$EMIT_TARGET" == *metric* ]]; then # call sli_emit_metric()
```

### Technical Specification

**OCI Monitoring API:**
```
POST https://telemetry-ingestion.{region}.oci.oraclecloud.com/20180401/metrics
Content-Type: application/json
Authorization: Signature ...  (same signing headers as Logging)

[{
  "namespace":     "sli_tracker",
  "name":          "outcome",
  "compartmentId": "<tenancy-ocid>",
  "dimensions": {
    "workflow_name":   "<workflow.name>",
    "workflow_job":    "<workflow.job>",
    "repo_repository": "<repo.repository>",
    "repo_ref":        "<repo.ref>"
  },
  "datapoints": [{"timestamp": "<ISO8601>", "value": 1}]
}]
```

**Signing headers:** same set as Logging: `date (request-target) host content-length content-type x-content-sha256`

**Scripts modified:**
- `.github/actions/sli-event/emit_common.sh` — add `sli_outcome_to_metric_value()` and `sli_emit_metric()`
- `.github/actions/sli-event/emit_curl.sh` — wrap log push with `EMIT_TARGET` check; add metric call
- `.github/actions/sli-event/emit_oci.sh` — same EMIT_TARGET wrapping; add metric call

**Environment variables:**
| Variable | Default | Description |
|---|---|---|
| `EMIT_TARGET` | `log,metric` | Comma-separated: `log`, `metric`, or both |
| `SLI_METRIC_NAMESPACE` | `sli_tracker` | OCI Monitoring namespace |
| `SLI_SKIP_OCI_PUSH` | unset | Skips both log and metric when set |

### Implementation Approach

1. Add `sli_outcome_to_metric_value()` to `emit_common.sh`
2. Add `sli_emit_metric()` to `emit_common.sh` (self-contained: reads profile, signs, POSTs)
3. Modify `emit_curl.sh`: outer if checks only `OCI_CONFIG` (not `OCI_LOG_ID`); wrap log push in `EMIT_TARGET` check; add metric call
4. Modify `emit_oci.sh`: same EMIT_TARGET wrapping; add metric call after OCI CLI log push block

### Testing Strategy

#### Recommended Sprint Parameters
- Test: integration (emit scripts run locally with real OCI credentials)
- Regression: unit (verify EMIT_TARGET handling + outcome mapping don't break existing unit tests)

#### Unit Test Targets (appended to `tests/unit/test_emit.sh` — exercised via B2 regression)

- **`sli_outcome_to_metric_value`**: success→1, failure→0, cancelled→0, empty→0
- **EMIT_TARGET defaulting**: no `EMIT_TARGET` set → default to `log,metric` behaviour

These are appended to `tests/unit/test_emit.sh`; they run in B2 regression gate (not A gates, since `Test: integration`).

#### Integration Test Scenarios

**IT-1: `EMIT_TARGET=metric` — metric-only push**
- Run `emit_curl.sh` locally with `EMIT_TARGET=metric`, real OCI profile
- Assert: no log push notice; metric push success notice in output
- Query OCI Monitoring to confirm datapoint arrived

**IT-2: `EMIT_TARGET=log,metric` — dual push**
- Run `emit_curl.sh` locally with `EMIT_TARGET=log,metric`, real OCI profile + log-id
- Assert: both log push and metric push success notices in output
- Query OCI Logging and OCI Monitoring to confirm both arrived

**Target file:** `tests/integration/test_sli_emit_metric.sh` (new file)

#### Smoke Test Candidates
None — integration test runs locally in minutes; smoke gate not in this sprint's `Test:` params.

### YOLO Mode Decisions

**Decision 1: compartmentId = tenancy OCID**
- Context: OCI Monitoring requires compartmentId; no dedicated compartment OCID in the SLI config
- Decision: use `tenancy` field from OCI config profile
- Rationale: simplest approach; most users have root-tenancy compartment access
- Risk: Low — `SLI_METRIC_COMPARTMENT` override can be added later

**Decision 2: sli_emit_metric reads profile internally**
- Context: both emit_curl.sh and emit_oci.sh have different log push structures
- Decision: `sli_emit_metric(log_entry, config, profile)` does its own profile field parsing
- Rationale: self-contained, no shared mutable state; consistent with emit_common.sh style
- Risk: Low — slight duplication but clean interface

**Decision 3: no `EMIT_TARGET=none` value**
- Context: what if caller wants to skip everything?
- Decision: `SLI_SKIP_OCI_PUSH` already handles that; `EMIT_TARGET` only selects among active targets
- Risk: None

---

## Test Specification

### Sprint Test Configuration
- Test: integration
- Regression: unit
- Mode: YOLO

### Integration Tests

#### IT-1: metric-only push via emit_curl.sh
- **Input:** `EMIT_TARGET=metric`, real OCI profile (no log-id)
- **Expected Output:** `SLI metric pushed to OCI Monitoring` notice; no log push attempt
- **Verification:** `oci monitoring metric-data summarize-metrics-data` returns ≥1 datapoint
- **Target file:** `tests/integration/test_sli_emit_metric.sh`

#### IT-2: dual push (log + metric) via emit_curl.sh
- **Input:** `EMIT_TARGET=log,metric`, real OCI profile + `SLI_OCI_LOG_ID`
- **Expected Output:** both `SLI log entry pushed` and `SLI metric pushed` notices
- **Verification:** OCI Logging search + OCI Monitoring query both return matching entries
- **Target file:** `tests/integration/test_sli_emit_metric.sh`

### Unit Tests (appended to `tests/unit/test_emit.sh` — run in B2 regression)

#### UT-S12-1: sli_outcome_to_metric_value — success → 1
#### UT-S12-2: sli_outcome_to_metric_value — failure → 0
#### UT-S12-3: sli_outcome_to_metric_value — empty/unknown → 0
#### UT-S12-4: emit_curl.sh EMIT_TARGET=log skips metric
#### UT-S12-5: emit_curl.sh EMIT_TARGET=metric skips log

### Traceability

| Backlog Item | Smoke | Unit Tests | Integration Tests |
|---|---|---|---|
| SLI-17 | — | UT-S12-1..5 (B2 regression) | IT-1, IT-2 (Gate A3) |

### New-Tests Manifest

`progress/sprint_12/new_tests.manifest`:
```
# Sprint 12 — new integration test script (Gate A3)
integration:test_sli_emit_metric.sh
```

Unit tests (UT-S12-*) are added to `tests/unit/test_emit.sh` but exercised in B2 regression (not A gates), since `Test: integration`.
