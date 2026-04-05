# Sprint 6 — Analysis

Status: Complete

## Sprint Overview

Fix `emit.sh` to unescape any top-level field whose name ends with `-json` and whose value is a valid JSON string. After the fix, the OCI log entry contains native JSON values instead of escaped strings.

## Backlog Items Analysis

### SLI-9 — emit.sh: unescape *-json fields to native JSON

**Requirement Summary:**

Any field key matching `*-json` in the assembled payload must have its string value parsed as JSON. If the value is a valid JSON value (object, array, string, number, bool, null), embed it directly. If it is not valid JSON, leave the string as-is.

**Technical Approach:**

Add a new pure helper `sli_unescape_json_fields` that walks the top-level keys of a JSON object using `jq`, identifies keys ending in `-json`, attempts `fromjson` on the string value, and replaces it if successful. Call it in `sli_build_log_entry` (or `sli_merge_flat_context`) before final payload assembly.

`jq` one-liner:
```
with_entries(
  if (.key | endswith("-json")) and (.value | type) == "string"
  then
    .value |= (try fromjson catch .)
  else . end
)
```

**Dependencies:** `jq` — already required everywhere in `emit.sh`.

**Testing Strategy:** New unit tests in `test_emit.sh` for `sli_unescape_json_fields`:
- array value unescaped correctly
- object value unescaped correctly
- non-json string left as-is
- non `-json` key not touched
- already-native value (not a string) left as-is

Regression: existing 19 tests must continue to pass.

**Risks:** Low — pure jq transformation, no side effects.

**Compatibility:** `sli_merge_flat_context` currently receives `inputs-json` which already has `*-json` fields as strings. The unescape step must run after the flat merge so it applies to the final payload.

## YOLO Mode Decisions

### Assumption 1: Where to apply the fix
**Issue:** Apply in `sli_merge_flat_context` or `sli_build_log_entry`?
**Assumption:** Apply as a post-processing step called inside `sli_build_log_entry` after merging base + flat. This keeps each function single-purpose and is easiest to test in isolation.
**Risk:** Low.

## Readiness for Design Phase

Confirmed Ready
