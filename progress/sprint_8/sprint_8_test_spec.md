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

### IT-1: emit_curl local — self-crafted OCI signing (Sprint 8 reopen)
- **Preconditions:** `oci`, `jq`, `curl`, `openssl`; valid profile in `~/.oci` (e.g. `SLI_TEST`); `oci_scaffold` submodule; **no** `gh` workflow dispatch
- **Steps:** Set synthetic `GITHUB_*` env; run `emit_curl.sh`; assert curl push notice; `logging-search` for an event whose `workflow` matches the local test label
- **Expected Outcome:** Script exits 0; artifacts `test_run_emit_curl_local_*.log`, `oci_logs_emit_curl_local_*.json`
- **Target file:** tests/integration/test_sli_emit_curl_local.sh

### IT-2: emit_curl via GitHub workflow (not Sprint 8)
- **Note:** `tests/integration/test_sli_emit_curl_workflow.sh` dispatches `model-emit-curl.yml`. Use for SLI-12 / CI validation; **not** a Sprint 8 reopen requirement.

### IT-3: Full SLI pipeline (not Sprint 8)
- **Note:** `tests/integration/test_sli_integration.sh` — model workflows, oci-cli emit. Not a Sprint 8 reopen gate.

**Running all integration tests:** `tests/run.sh --integration` runs every `tests/integration/test_*.sh` (sorted). For Sprint 8 reopen only, use `--new-only progress/sprint_8/sprint_8_reopen.manifest`.

## Traceability

| Backlog Item | Unit Tests | Integration Tests |
| --- | --- | --- |
| SLI-11 | UT-1 … UT-7 | IT-1 (`test_sli_emit_curl_local.sh` only for reopen) |

## Regression

Existing unit tests in `tests/unit/test_emit.sh` (helpers predating UT-1) and other `tests/unit/test_*.sh` scripts must still pass after the split — tracked as full `tests/run.sh --unit`.
