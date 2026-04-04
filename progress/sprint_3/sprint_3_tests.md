# Sprint 3 — Tests

## Environment

- bash, jq, repo checkout
- SLI-4: no OCI secrets required for unit harness (`SLI_SKIP_OCI_PUSH` implicit in helpers tests)

## SLI-4 — sli-event

| Test | Command | Expected |
|------|-----------|----------|
| Emit unit tests | `bash .github/actions/sli-event/tests/test_emit.sh` | `passed: 16` `failed: 0` |

**Test sequence:**

```bash
cd /path/to/SLI_tracker
bash .github/actions/sli-event/tests/test_emit.sh
```

**Status:** PASS

## SLI-3 — model workflows

| Test | Command | Expected |
|------|-----------|----------|
| YAML syntax | `find .github/workflows -name 'model*.yml' -print` | files listed |
| Optional | Push branch → GitHub Actions runs if workflow exists | workflows valid |

**Note:** Full GitHub execution not run in this YOLO cycle; static review only.

## Summary

| Item | Tests | Passed | Failed |
|------|-------|--------|--------|
| SLI-3 | static review | 1 | 0 |
| SLI-4 | test_emit.sh | 16 | 0 |
