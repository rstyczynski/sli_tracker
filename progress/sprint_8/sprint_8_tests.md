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

### Gate C2: All integration tests (PLAN: Test: integration)

Runs **every** `tests/integration/test_*.sh` script (currently one: `test_sli_integration.sh`). Add new files under `tests/integration/` as new domains appear; `run.sh` picks them up automatically.

```bash
bash tests/run.sh --integration 2>&1 | tail -12
```

Expected: `TOTAL: 1 scripts, 1 passed, 0 failed` (increment script count when new `test_*.sh` files exist) / `RESULT: PASS`

**Status:** operator-run (requires live infra)

### Gate D2: New-code manifest (unit + integration listed in sprint manifest)

Uses `progress/sprint_8/new_tests.manifest` so `--new-only` includes both the emit unit script and the integration script.

```bash
bash tests/run.sh --unit --new-only progress/sprint_8/new_tests.manifest 2>&1 | tail -8
bash tests/run.sh --integration --new-only progress/sprint_8/new_tests.manifest 2>&1 | tail -8
```

Expected: each run lists only scripts present in the manifest; `RESULT: PASS` when those scripts pass.

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
| IT-1 | Full pipeline (`test_sli_integration.sh`) | operator-run |

Total unit: 33 passed / 0 failed (same as Gate A2/B2).

## Artifacts

- Gate A2 log: `progress/sprint_8/test_run_A2_unit_20260406_113829.log`
- Gate B2 log: `progress/sprint_8/test_run_B2_unit_20260406_113837.log`
