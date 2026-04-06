# Sprint 8 — Functional Tests

## Test Environment Setup

Prerequisites: bash, jq, openssl (all standard)

## SLI-11 Tests

### Gate A2: New unit tests (UT-1 to UT-7)

```bash
bash tests/unit/test_emit.sh 2>&1 | grep -E "UT-[0-9]|passed:|failed:"
```

Expected: `passed: 33  failed: 0`

**Status:** PASS

### Gate B2: Full unit regression

```bash
bash tests/run.sh --unit 2>&1 | tail -6
```

Expected: `TOTAL: 3 scripts, 3 passed, 0 failed` / `RESULT: PASS`

**Status:** PASS

## Test Summary

| Test | Description | Status |
| --- | --- | --- |
| UT-1 | emit_common.sh helpers sourced | PASS |
| UT-2 | _oci_config_field multi-profile parsing | PASS |
| UT-3 | SLI_SKIP_OCI_PUSH skips curl | PASS |
| UT-4 | Authorization header structure | PASS |
| UT-5 | Payload is valid JSON batch | PASS |
| UT-6 | Dispatcher EMIT_BACKEND=curl | PASS |
| UT-7 | Dispatcher EMIT_BACKEND=oci-cli | PASS |
| Regression | 24 prior unit tests + 2 other scripts | PASS |

Total: 33 passed / 0 failed

## Artifacts

- Gate A2 log: `progress/sprint_8/test_run_A2_unit_20260406_113829.log`
- Gate B2 log: `progress/sprint_8/test_run_B2_unit_20260406_113837.log`
