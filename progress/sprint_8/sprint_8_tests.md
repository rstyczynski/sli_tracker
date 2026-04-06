# Sprint 8 — Functional Tests

## Test Environment Setup

**Unit:** bash, jq, openssl (standard)

**Integration:** bash, `gh`, `oci`, `jq`, OCI tenancy + GitHub repo access, `OCI_CONFIG_PAYLOAD` secret, `oci_scaffold` submodule initialized

## SLI-11 Tests

### Gate A2: New unit tests (UT-1 to UT-7)

```bash
bash tests/unit/test_emit.sh 2>&1 | grep -E "UT-[0-9]|passed:|failed:"
```

Expected: `passed: 33  failed: 0`

**Status:** PASS

### Gate B2: Full unit regression (PLAN: Regression: unit)

```bash
bash tests/run.sh --unit 2>&1 | tail -8
```

Expected: `TOTAL: 3 scripts, 3 passed, 0 failed` / `RESULT: PASS`

**Status:** PASS

### Gate C2: Sprint 8 reopen — integration (local emit_curl only, no workflows)

**Not** workflow dispatch (`test_sli_emit_curl_workflow.sh` is out of scope for this sprint). **Not** the full pipeline (`test_sli_integration.sh`).

```bash
bash tests/run.sh --integration --new-only progress/sprint_8/sprint_8_reopen.manifest 2>&1 | tail -12
```

Expected: `TOTAL: 1 scripts, 1 passed, 0 failed` for `test_sli_emit_curl_local.sh` / `RESULT: PASS`

**Status:** operator-run (OCI + `~/.oci`; no `gh` workflow)

### Gate C3: Full integration suite (repository regression; optional for Sprint 8)

Runs **every** `tests/integration/test_*.sh` script. Use outside Sprint 8 reopen scope.

```bash
bash tests/run.sh --integration 2>&1 | tail -12
```

### Gate D2: New-code manifest (historical Sprint 8 split)

`progress/sprint_8/new_tests.manifest` — original manifest including `test_sli_integration.sh`.

### Gate D3: Sprint 8 reopen manifest (unit + emit_curl integration only)

```bash
bash tests/run.sh --unit --new-only progress/sprint_8/sprint_8_reopen.manifest 2>&1 | tail -8
bash tests/run.sh --integration --new-only progress/sprint_8/sprint_8_reopen.manifest 2>&1 | tail -8
```

Expected: `RESULT: PASS` when listed scripts pass.

## Test Summary

| Test | Description | Status |
| --- | --- | --- |
| UT-1 | emit_common.sh helpers sourced | PASS |
| UT-2 | _oci_config_field multi-profile parsing | PASS |
| UT-3 | SLI_SKIP_OCI_PUSH skips curl | PASS |
| UT-4 | Authorization header structure | PASS |
| UT-5 | Ingestion body (`specversion` + `logEntryBatches`) | PASS |
| UT-6 | Dispatcher EMIT_BACKEND=curl | PASS |
| UT-7 | Dispatcher EMIT_BACKEND=oci-cli | PASS |
| Regression unit | 24 prior + 2 other `tests/unit` scripts | PASS |
| IT-1 | emit_curl local (`test_sli_emit_curl_local.sh`) | operator-run |
| — | Workflow dispatch (`test_sli_emit_curl_workflow.sh`) | not Sprint 8 |
| — | Full pipeline (`test_sli_integration.sh`) | not Sprint 8 reopen gate |

Total unit: 33 passed / 0 failed (same as Gate A2/B2).

## Artifacts

- Gate A2 log: `progress/sprint_8/test_run_A2_unit_20260406_113829.log`
- Gate B2 log: `progress/sprint_8/test_run_B2_unit_20260406_113837.log`
