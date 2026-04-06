# Sprint 8 — Test Specification

## Sprint Test Configuration

- Test: unit, integration
- Mode: YOLO
- Regression: unit — full `tests/unit/` suite; no regression shrink for integration (each run is live infra)

## Unit Tests

### UT-1: emit_common.sh sourcing — all helpers available
- **Input:** `source emit_common.sh` in a fresh bash subshell
- **Expected Output:** `declare -f sli_build_log_entry` exits 0; all 10 helpers declared
- **Edge Cases:** none
- **Isolation:** none (pure source test)
- **Target file:** tests/unit/test_emit.sh (append)

### UT-2: _oci_config_field — correct value from multi-profile config
- **Input:** temp config file with `[DEFAULT]` and `[SLI_TEST]` sections; request `region` from `SLI_TEST`
- **Expected Output:** region value from `[SLI_TEST]`, not `[DEFAULT]`
- **Edge Cases:** missing field → empty string; spaces around `=`
- **Isolation:** temp file written inline
- **Target file:** tests/unit/test_emit.sh (append)

### UT-3: emit_curl.sh — SLI_SKIP_OCI_PUSH skips curl
- **Input:** `SLI_SKIP_OCI_PUSH=1 SLI_OUTCOME=success` sourced; mock curl records calls
- **Expected Output:** curl never called; notice printed
- **Isolation:** mock `curl` function
- **Target file:** tests/unit/test_emit.sh (append)

### UT-4: emit_curl.sh — Authorization header structure
- **Input:** valid mock OCI config, mock key, `SLI_OUTCOME=success`, mock curl capturing `-H` headers
- **Expected Output:** Authorization header matches `Signature version="1",keyId=".+/.+/.+",algorithm="rsa-sha256",headers=".*",signature=".+"`
- **Isolation:** mock `curl`, temp OCI config with RSA test key (generated inline)
- **Target file:** tests/unit/test_emit.sh (append)

### UT-5: emit_curl.sh — ingestion body matches `put-logs`
- **Input:** same as UT-4
- **Expected Output:** body passed to curl is JSON with `specversion == "1.0"` and `logEntryBatches[0].entries[0].data` present (same wire shape as `oci logging-ingestion put-logs`)
- **Target file:** tests/unit/test_emit.sh (append)

### UT-6: emit.sh dispatcher — EMIT_BACKEND=curl invokes emit_curl.sh
- **Input:** `EMIT_BACKEND=curl bash emit.sh` with `SLI_SKIP_OCI_PUSH=1`
- **Expected Output:** exits 0; output contains "SLI OCI push skipped" (from curl backend)
- **Isolation:** SLI_SKIP_OCI_PUSH avoids actual curl call
- **Target file:** tests/unit/test_emit.sh (append)

### UT-7: emit.sh dispatcher — EMIT_BACKEND=oci-cli invokes emit_oci.sh
- **Input:** `EMIT_BACKEND=oci-cli bash emit.sh` with `SLI_SKIP_OCI_PUSH=1`
- **Expected Output:** exits 0; output contains "SLI OCI push skipped"
- **Target file:** tests/unit/test_emit.sh (append)

## Integration Tests

### IT-1: Full SLI pipeline (existing)
- **Preconditions:** Authenticated `gh` CLI, OCI CLI with DEFAULT profile, `jq`, `OCI_CONFIG_PAYLOAD` repo secret, `oci_scaffold` submodule
- **Steps:** oci_scaffold ensure + `gh variable set`; nested unit count check; dispatch model-call / model-push; wait; OCI Logging search; SLI-9 field checks
- **Expected Outcome:** Script exits 0; artifacts `test_run_*.log` and `oci_logs_*.json` under `tests/integration/`
- **Target file:** tests/integration/test_sli_integration.sh

**Running all integration tests:** `tests/run.sh` executes every `tests/integration/test_*.sh` (sorted). New domains append new `test_<domain>.sh` files; do not split by sprint.

## Traceability

| Backlog Item | Unit Tests | Integration Tests |
| --- | --- | --- |
| SLI-11 | UT-1 … UT-7 | IT-1 (full pipeline; includes nested unit gate) |

## Regression

Existing unit tests in `tests/unit/test_emit.sh` (helpers predating UT-1) and other `tests/unit/test_*.sh` scripts must still pass after the split — tracked as full `tests/run.sh --unit`.
