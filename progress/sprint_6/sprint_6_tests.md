# Sprint 6 — Functional Tests

## Test Environment Setup

### Prerequisites

- `gh` — GitHub CLI, authenticated
- `oci` — OCI CLI with `DEFAULT` profile
- `jq` — JSON processor
- `OCI_CONFIG_PAYLOAD` repo secret holding a valid (non-expired) OCI session token

```bash
cd /path/to/SLI_tracker
```

### OCI Session Refresh (when expired)

```bash
bash .github/actions/oci-profile-setup/setup_oci_github_access.sh --session-profile-name SLI_TEST
```

---

## SLI-9 Unit Tests — `sli_unescape_json_fields`

### Test 1: Array string unescaped to native array

**Purpose:** String value starting with `[` is parsed to native array.

**Test Sequence:**

```bash
bash .github/actions/sli-event/tests/test_emit.sh 2>&1 | grep -E "passed|failed"
```

**Status:** PASS (24/24)

---

### Test 2: Object string unescaped to native object

**Status:** PASS

### Test 3: Plain string not starting with `[` or `{` left as-is

**Status:** PASS

### Test 4: Plain value not touched

**Status:** PASS

### Test 5: Already-native array left unchanged

**Status:** PASS

---

## SLI-9 Integration Tests — OCI log verification

### Test T8: environments field is native JSON array in OCI log

**Purpose:** Verify that `environments` field in OCI log entries is a native JSON array (not an escaped string), confirming SLI-9 fix works end-to-end.

**Test Sequence:**

```bash
bash progress/sprint_6/test_sli_integration.sh
```

Relevant assertions:

```bash
OCI_LOG=$(ls -t progress/sprint_6/oci_logs_*.json | head -1)
# No events with environments as escaped string:
jq '[.[] | .data.logContent.data | if type=="string" then fromjson else . end | select(.environments != null) | select(.environments | type == "string")] | length' "$OCI_LOG"
# At least 4 events with environments as native array:
jq '[.[] | .data.logContent.data | if type=="string" then fromjson else . end | select(.environments != null) | select(.environments | type == "array")] | length' "$OCI_LOG"
```

Expected output:

```
0
4
```

**Status:** PASS

---

## Integration test runs — 2026-04-05

### Run 1 — OCI session expired (negative test)

Result: 24 passed / 22 failed

- T1 also failed (wrong expected count 19 vs actual 24) — fixed before Run 2
- T6/T7/T8 failed — zero OCI events due to expired `OCI_CONFIG_PAYLOAD`

### Run 2 — After fix + OCI session refresh (positive test)

Result: 46 passed / 0 failed

```
=== T1: unit tests — emit.sh helper functions ===
PASS: emit.sh unit tests: passed count
PASS: emit.sh unit tests: failed count

=== T6: sli-event step emitted to OCI (per-job notice) ===
PASS: run 24000547707 / ... / SLI — init → SLI pushed
[×12 T6 passes]

=== T7: OCI Logging received events — query last 15 min ===
PASS: OCI received at least 12 events (4 runs × 3 jobs)
[×8 T7 passes]

=== T8: SLI-9 — environments field is native JSON array (not escaped string) ===
PASS: OCI: environments field is not an escaped string (count=0)
PASS: OCI: environments field is native array in at least 4 events

=== Summary ===
passed: 46  failed: 0
```

Artifacts:

- Execution log: `progress/sprint_6/test_run_20260405_112711.log`
- OCI log: `progress/sprint_6/oci_logs_20260405_112711.json`

---

## Test Summary

| Test       | Description                               | Status |
|------------|-------------------------------------------|--------|
| Unit 1–5   | `sli_unescape_json_fields` (5 cases)      | PASS   |
| Regression | 19 pre-existing unit tests                | PASS   |
| T8         | environments is native array in OCI       | PASS   |
| T0–T7      | Full integration baseline (44 assertions) | PASS   |

## Overall Test Results

**Total Tests:** 46 (24 unit + 2 T8 assertions + 20 integration baseline)
**Passed:** 46
**Failed:** 0
**Success Rate:** 100%

## Test Execution Notes

Run 1 revealed two issues: hardcoded `want=19` in T1 (fixed to 24), and expired OCI session. Both fixed before Run 2. Run 2: 46/46.
