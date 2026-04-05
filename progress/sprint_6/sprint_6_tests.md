# Sprint 6 — Functional Tests

## Test Environment Setup

### Prerequisites

- `jq`
- `bash`

```bash
cd /path/to/SLI_tracker
```

---

## SLI-9 Tests — `sli_unescape_json_fields`

### Test 1: Array string unescaped to native array

**Purpose:** `*-json` field with escaped array value becomes a native JSON array.

**Test Sequence:**

```bash
bash .github/actions/sli-event/tests/test_emit.sh 2>&1 | grep -A1 "unescape_json"
```

**Status:** PASS

---

### Test 2: Object string unescaped to native object

**Purpose:** `*-json` field with escaped object value becomes a native JSON object.

**Status:** PASS

---

### Test 3: Invalid JSON string left as-is

**Purpose:** Malformed string in a `*-json` field is not modified.

**Status:** PASS

---

### Test 4: Non `-json` key not touched

**Purpose:** Fields without the `-json` suffix are never modified.

**Status:** PASS

---

### Test 5: Already-native value left unchanged

**Purpose:** If a `*-json` field already holds a native array/object (not a string), it is unchanged.

**Status:** PASS

---

## Regression

All 19 pre-existing unit tests still pass.

---

## Full unit test run — 2026-04-05

```bash
bash .github/actions/sli-event/tests/test_emit.sh
```

```
== sli_normalize_json_object ==
== sli_expand_oci_config_path ==
== sli_merge_flat_context ==
== sli_extract_oci_json ==
== sli_failure_reasons_from_steps_json ==
== sli_merge_failure_reasons ==
== sli_unescape_json_fields ==
== sli_build_log_entry ==
== sli_build_base_json (fake GITHUB_*) ==
== summary ==
passed: 24  failed: 0
```

---

## Test Summary

| Backlog Item | Total Tests | Passed | Failed | Status |
|--------------|-------------|--------|--------|--------|
| SLI-9        | 5 new + 19 regression | 24 | 0 | PASS |

## Overall Test Results

**Total Tests:** 24
**Passed:** 24
**Failed:** 0
**Success Rate:** 100%

## Test Execution Notes

One construction iteration: initial `catch .` implementation replaced by `catch $orig` after test 3 failed. Final run: 24/24.
