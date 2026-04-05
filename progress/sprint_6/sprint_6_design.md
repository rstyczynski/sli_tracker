# Sprint 6 — Design

## SLI-9 — emit.sh: unescape *-json fields to native JSON

Status: Accepted

### Requirement Summary

Fields ending in `-json` in the assembled OCI log payload must contain native JSON values, not escaped strings.

### Feasibility Analysis

**API Availability:** `jq` — already required. `try fromjson catch .` is standard jq.
**Technical Constraints:** None.
**Risk Assessment:** Low — pure transformation, no I/O.

### Design Overview

**New helper:** `sli_unescape_json_fields`

```bash
sli_unescape_json_fields() {
  local payload="${1:?}"
  echo "$payload" | jq -c '
    with_entries(
      if (.key | endswith("-json")) and (.value | type) == "string"
      then .value |= (try fromjson catch .)
      else . end
    )'
}
```

**Integration point:** `sli_build_log_entry` — call after assembling base + flat + failure_reasons:

```bash
sli_build_log_entry() {
  local base flat fr result
  base="${1:?}"; flat="${2:?}"; fr="${3:?}"
  result=$(echo "$base" | jq --argjson ctx "$flat" '. + $ctx' \
           | jq --argjson fr "$fr" '. + {failure_reasons: $fr}')
  sli_unescape_json_fields "$result"
}
```

**Data flow:**
```
inputs-json (string) → sli_merge_flat_context → flat (still has *-json as strings)
                                                      ↓
                                             sli_build_log_entry
                                                      ↓
                                       sli_unescape_json_fields  ← NEW
                                                      ↓
                                             LOG_ENTRY (native JSON)
```

### Technical Specification

**Files changed:**

| File | Change |
|------|--------|
| `.github/actions/sli-event/emit.sh` | Add `sli_unescape_json_fields`; update `sli_build_log_entry` |
| `.github/actions/sli-event/tests/test_emit.sh` | Add 5 unit tests for new helper |

### Testing Strategy

**New unit tests for `sli_unescape_json_fields`:**

| # | Input key | Input value | Expected output value |
|---|-----------|-------------|----------------------|
| 1 | `environments-json` | `"[\"a\",\"b\"]"` | `["a","b"]` (array) |
| 2 | `config-json` | `"{\"k\":\"v\"}"` | `{"k":"v"}` (object) |
| 3 | `note-json` | `"not valid json {"` | `"not valid json {"` (unchanged) |
| 4 | `environment` | `"prod"` (no `-json` suffix) | `"prod"` (untouched) |
| 5 | `environments-json` | `["a","b"]` (already array) | `["a","b"]` (untouched — not a string) |

**Regression:** existing 19 unit tests must pass unchanged.

### YOLO Mode Decisions

#### Decision 1: Apply in `sli_build_log_entry` not `sli_merge_flat_context`
**Rationale:** Keeps merge function single-purpose; unescape is a final-payload concern.
**Risk:** Low.

#### Decision 2: `try fromjson catch .` — leave invalid as-is
**Rationale:** Graceful degradation — a malformed `*-json` field should not break the emit.
**Risk:** Low.
