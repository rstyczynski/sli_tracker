# Sprint 5 — Functional Tests

## Test Environment Setup

### Prerequisites

- `gh` — GitHub CLI, authenticated
- `oci` — OCI CLI with `DEFAULT` profile
- `jq` — JSON processor
- `SLI_OCI_LOG_URI` repo variable set

```bash
cd /path/to/SLI_tracker
```

---

## SLI-8 Tests

### Test 1: T_exec_log — Execution log created on run

**Purpose:** Verify `test_run_<ts>.log` is created in `progress/sprint_5/` after execution.

**Expected Outcome:** Log file exists and contains test section headers.

**Test Sequence:**

```bash
bash progress/sprint_5/test_sli_integration.sh
ls progress/sprint_5/test_run_*.log
```

Expected output (example):
```
progress/sprint_5/test_run_20260405_120000.log
```

**Status:** PASS (verified in live run — see notes)

---

### Test 2: T_exec_log_content — Execution log contains full output

**Purpose:** Verify log captures all test sections.

**Test Sequence:**

```bash
LOG=$(ls -t progress/sprint_5/test_run_*.log | head -1)
grep -c "=== T" "$LOG"
```

Expected output: `9` (T0, T0b, T1, T2, T3, T4, T5, T6, T7)

**Status:** PASS (verified in live run)

---

### Test 3: T_oci_log — OCI log JSON created on run

**Purpose:** Verify `oci_logs_<ts>.json` is created after T7 executes.

**Test Sequence:**

```bash
ls progress/sprint_5/oci_logs_*.json
```

Expected output (example):
```
progress/sprint_5/oci_logs_20260405_120000.json
```

**Status:** PASS (verified in live run)

---

### Test 4: T_oci_log_content — OCI log JSON is valid array

**Purpose:** Verify OCI JSON file contains a parseable array.

**Test Sequence:**

```bash
OCI_LOG=$(ls -t progress/sprint_5/oci_logs_*.json | head -1)
jq 'type' "$OCI_LOG"
jq 'length' "$OCI_LOG"
```

Expected output:
```
"array"
12
```
(exact count varies; must be ≥ 12 for a passing run)

**Status:** PASS (verified in live run)

---

### Test 5: T_artifact_paths_printed — Artifact paths printed at end

**Purpose:** Verify both artifact paths appear in end-of-run output (and thus in execution log).

**Test Sequence:**

```bash
LOG=$(ls -t progress/sprint_5/test_run_*.log | head -1)
grep "execution log" "$LOG"
grep "OCI log" "$LOG"
```

Expected output:
```
  execution log : /path/to/SLI_tracker/progress/sprint_5/test_run_20260405_120000.log
  OCI log       : /path/to/SLI_tracker/progress/sprint_5/oci_logs_20260405_120000.json
```

**Status:** PASS (verified in live run)

---

### Test 6: T_sprint4_unchanged — Sprint 4 script unmodified

**Purpose:** Confirm sprint_4 test script was not modified.

**Test Sequence:**

```bash
git diff HEAD -- progress/sprint_4/test_sli_integration.sh
```

Expected output: *(empty — no diff)*

**Status:** PASS

---

## Integration test run — 2026-04-05

**Result: 6/6 static + live checks passed**

Live run output (executed after OCI session refresh):

```
# Sprint 5 integration test run — 2026-04-05T...
# Execution log : progress/sprint_5/test_run_20260405_....log
...
=== T7: OCI Logging received events — query last 15 min ===
# OCI log captured: progress/sprint_5/oci_logs_20260405_....json
...
=== Summary ===
passed: 44  failed: 0

=== Artifacts ===
  execution log : progress/sprint_5/test_run_20260405_....log
  OCI log       : progress/sprint_5/oci_logs_20260405_....json
```

---

## Test Summary

| Backlog Item | Total Tests | Passed | Failed | Status |
|--------------|-------------|--------|--------|--------|
| SLI-8        | 6           | 6      | 0      | PASS   |

## Overall Test Results

**Total Tests:** 6
**Passed:** 6
**Failed:** 0
**Success Rate:** 100%

## Test Execution Notes

Tests 1–5 verified in live run. Test 6 (git diff) confirmed statically. The 44 existing assertions from Sprint 4 carry over unchanged; the 6 new tests verify only the artifact additions.
