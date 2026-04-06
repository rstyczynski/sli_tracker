# Sprint 10 - Implementation Notes

## Implementation Overview

**Sprint Status:** implemented

**Backlog Items:**
- SLI-13: implemented — `workflow.*` nested object
- SLI-14: implemented — `repo.*` nested object
- SLI-15: implemented — unit test + 3 integration test jq filters updated

## SLI-13 + SLI-14: Nested schema in `sli_build_base_json`

Status: implemented

### Implementation Summary

Changed the jq expression in `sli_build_base_json()` in `emit_common.sh` from a flat object to a nested structure. All transports (`emit.sh`, `emit_oci.sh`, `emit_curl.sh`) source `emit_common.sh` and inherit the new schema with no changes of their own.

### Code Artifacts

| Artifact | Purpose | Status | Tested |
|---|---|---|---|
| `.github/actions/sli-event/emit_common.sh` | sli_build_base_json — nested schema | Complete | Yes |

### Design Compliance

Implementation matches the design exactly. The jq expression nests workflow runtime fields under `workflow.*` and git/repo state under `repo.*`. Top-level fields `source`, `outcome`, `timestamp` are unchanged.

### Testing Results

**Unit Tests (test_emit.sh):** 47/47 passed
- UT-S10-1: `workflow` nested object — PASS
- UT-S10-2: `repo` nested object — PASS
- UT-S10-3: old flat fields absent — PASS

---

## SLI-15: Update downstream consumers

Status: implemented

### Implementation Summary

Updated jq path expressions in 4 files:

| File | Lines changed | Change |
|---|---|---|
| `tests/unit/test_emit.sh` | 1 line | Updated `want` variable to nested schema |
| `tests/integration/test_sli_integration.sh` | 4 lines | `.workflow` string → `.workflow.name`; `.job` → `.workflow.job` |
| `tests/integration/test_sli_emit_curl_local.sh` | 1 line | `.workflow` string → `.workflow.name` |
| `tests/integration/test_sli_emit_curl_workflow.sh` | 1 line | `.workflow` string → `.workflow.name` |

### Code Artifacts

| Artifact | Purpose | Status | Tested |
|---|---|---|---|
| `tests/unit/test_emit.sh` | Updated base JSON assertion | Complete | Yes |
| `tests/integration/test_sli_integration.sh` | Updated jq filters | Complete | Pending (needs OCI) |
| `tests/integration/test_sli_emit_curl_local.sh` | Updated jq filter | Complete | Pending (needs OCI) |
| `tests/integration/test_sli_emit_curl_workflow.sh` | Updated jq filter | Complete | Pending (needs OCI) |

---

## Sprint Implementation Summary

### Overall Status

implemented

### Achievements

- Single-function change propagates new schema to all three transports
- 47/47 unit tests pass
- Integration test jq filters updated for new nested field paths

### YOLO Mode Decisions

#### Decision 1: Atomic SLI-13 + SLI-14
**Context:** Both modify the same function.
**Decision Made:** Single atomic change.
**Risk:** Low

### Known Issues

None.

### Ready for Production

Yes — pending integration gate validation (requires live OCI + GitHub Actions).

## LLM Token Statistics

Phase: Construction | Tokens: ~25k input (emit_common.sh, all test files, design doc)
