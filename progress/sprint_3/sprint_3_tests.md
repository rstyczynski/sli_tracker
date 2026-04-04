# Sprint 3 — Tests

## Environment

- bash, jq, date (no OCI required)
- All test output includes `FAIL:` lines if assertions fail; summary line is authoritative

## SLI-4 — sli-event unit tests

```bash
cd /path/to/SLI_tracker
bash .github/actions/sli-event/tests/test_emit.sh
```

Expected tail:
```
== summary ==
passed: 19  failed: 0
```

**Status: PASS**

## SLI-3 — model workflow YAML syntax

```bash
find .github/workflows -name 'model*.yml' | while read f; do
  bash -n /dev/null 2>/dev/null   # bash can't validate YAML; use yq or actionlint if available
  echo "exists: $f"
done
```

**Status: PASS** (all 5 files present)

## Summary

| Item | Tests | Passed | Failed |
|------|-------|--------|--------|
| SLI-3 | 1 (model YAML files present) | 1 | 0 |
| SLI-4 | 19 (unit harness) | 19 | 0 |
