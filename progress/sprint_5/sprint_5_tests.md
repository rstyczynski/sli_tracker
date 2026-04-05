# Sprint 5 — Functional Tests

## Test Environment Setup

### Prerequisites

- `gh` — GitHub CLI, authenticated
- `oci` — OCI CLI with `DEFAULT` profile
- `jq` — JSON processor
- `SLI_OCI_LOG_URI` repo variable set
- `OCI_CONFIG_PAYLOAD` repo secret holding a valid (non-expired) OCI session token

```bash
cd /path/to/SLI_tracker
```

### OCI Session Refresh (when expired)

If the test run shows T6 failures (`unexpected SLI push outcome`) and T7 returning 0 events, the `OCI_CONFIG_PAYLOAD` secret has expired. Refresh it:

```bash
bash .github/actions/oci-profile-setup/setup_oci_github_access.sh --session-profile-name SLI_TEST
```

Then re-run the test. Expected symptom in workflow job logs:

```
WARNING: SLI report failed to push to OCI Logging (non-fatal)
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

**Status:** PASS

---

### Test 2: T_exec_log_content — Execution log contains full output

**Purpose:** Verify log captures all test sections.

**Test Sequence:**

```bash
LOG=$(ls -t progress/sprint_5/test_run_*.log | head -1)
grep -c "=== T" "$LOG"
```

Expected output: `9` (T0, T0b, T1, T2, T3, T4, T5, T6, T7)

**Status:** PASS

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

**Status:** PASS

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

**Status:** PASS

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

**Status:** PASS

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

### Test 7: T_oci_session_expired — Expired OCI session detected and recovered

**Purpose:** Verify the test procedure correctly exposes an expired OCI session and recovers after token refresh.

**Scenario:** `OCI_CONFIG_PAYLOAD` repo secret holds an expired session token.

Expected Outcome (Run 1 — session expired):

- T0–T5 pass (tooling + workflow dispatch unaffected)
- T6 fails: all SLI-push jobs show `unexpected SLI push outcome`
- T7 fails: 0 events received from OCI
- Exit code: 1

**Recovery step:**

```bash
bash .github/actions/oci-profile-setup/setup_oci_github_access.sh --session-profile-name SLI_TEST
```

Expected Outcome (Run 2 — session refreshed):

- All 44 assertions pass
- Exit code: 0

Run 1 result (2026-04-05 06:51 UTC): `passed: 24  failed: 20` — session expired confirmed.
Run 2 result (2026-04-05 07:20 UTC): `passed: 44  failed: 0` — all green after refresh.

Artifacts:

- Run 1 execution log: `progress/sprint_5/test_run_20260405_065145.log`
- Run 1 OCI log: `progress/sprint_5/oci_logs_20260405_065145.json` (empty array — 0 events)
- Run 2 execution log: `progress/sprint_5/test_run_20260405_072031.log`
- Run 2 OCI log: `progress/sprint_5/oci_logs_20260405_072031.json` (≥12 events)

**Status:** PASS

---

## Integration test runs — 2026-04-05

### Run 1 — OCI session expired (negative test)

Result: 24 passed / 20 failed

```
=== T6: sli-event step emitted to OCI (per-job notice) ===
FAIL: run .../SLI — init → unexpected SLI push outcome
FAIL: run .../Leaf execution → unexpected SLI push outcome
[×12 T6 failures across 4 runs × 3 SLI jobs]

=== T7: OCI Logging received events — query last 15 min ===
FAIL: OCI received at least 12 events (4 runs × 3 jobs)  (got=0 want>=12)
[×8 T7 failures — zero events in OCI]

=== Summary ===
passed: 24  failed: 20
```

Root cause: `OCI_CONFIG_PAYLOAD` secret expired → workflow jobs log `SLI report failed to push to OCI Logging (non-fatal)`.

### Run 2 — After OCI session refresh (positive test)

Result: 44 passed / 0 failed

```
=== T6: sli-event step emitted to OCI (per-job notice) ===
PASS: run 23996731181 / ... / SLI — init → SLI pushed
PASS: run 23996731181 / ... / Leaf execution → SLI pushed
[×12 T6 passes]

=== T7: OCI Logging received events — query last 15 min ===
PASS: OCI received at least 12 events (4 runs × 3 jobs)
PASS: OCI: at least 4 success outcome events
PASS: OCI: at least 4 failure outcome events
[×8 T7 passes]

=== Summary ===
passed: 44  failed: 0
```

---

## Test Summary

| Test | Description | Run 1 (expired) | Run 2 (refreshed) |
|------|-------------|-----------------|-------------------|
| T_exec_log | Execution log created | PASS | PASS |
| T_exec_log_content | Log contains all sections | PASS | PASS |
| T_oci_log | OCI JSON created | PASS | PASS |
| T_oci_log_content | OCI JSON valid array | PASS | PASS |
| T_artifact_paths_printed | Paths printed at end | PASS | PASS |
| T_sprint4_unchanged | Sprint 4 script unmodified | PASS | PASS |
| T_oci_session_expired | Session expiry detected + recovered | PASS (24/44 baseline) | PASS (44/44) |

## Overall Test Results

**Total Tests:** 7 (SLI-8) + 44 (baseline assertions)
**Passed (Run 2):** 44/44 baseline + 7/7 SLI-8 tests
**Failed:** 0
**Success Rate:** 100%

## Test Execution Notes

Two runs executed on 2026-04-05:

- Run 1 (06:51 UTC): captured expected failure due to expired OCI session — confirms test correctly detects the problem.
- Run 2 (07:20 UTC): all green after operator refreshed `OCI_CONFIG_PAYLOAD` via `setup_oci_github_access.sh`.

The execution log artifact (`test_run_*.log`) and OCI JSON capture (`oci_logs_*.json`) were created on both runs, demonstrating the artifact mechanism works regardless of test outcome.
