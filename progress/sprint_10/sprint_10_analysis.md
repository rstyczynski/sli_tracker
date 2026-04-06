# Sprint 10 - Analysis

Status: Complete

## Sprint Overview

Breaking schema change to the SLI event payload. All GitHub Actions runtime metadata moves from top-level flat fields into two nested objects: `workflow` (run context) and `repo` (repository/git state). Unit and integration tests must be updated to match new field paths. Three tightly coupled Backlog Items: SLI-13 (nest workflow), SLI-14 (nest repo), SLI-15 (update downstream).

## Backlog Items Analysis

### SLI-13: Make `workflow` metadata a nested map in emitted events

**Requirement Summary:**
Move all workflow/GitHub Actions runtime fields out of the top-level payload into a single nested `workflow` object.

**Current flat fields being moved:**
- `workflow_run_id` → `workflow.run_id` (GITHUB_RUN_ID)
- `workflow_run_number` → `workflow.run_number` (GITHUB_RUN_NUMBER)
- `workflow_run_attempt` → `workflow.run_attempt` (GITHUB_RUN_ATTEMPT)
- `workflow` (string) → `workflow.name` (GITHUB_WORKFLOW)
- `workflow_ref` → `workflow.ref` (GITHUB_WORKFLOW_REF)
- `job` → `workflow.job` (GITHUB_JOB)
- `event_name` → `workflow.event_name` (GITHUB_EVENT_NAME)
- `actor` → `workflow.actor` (GITHUB_ACTOR)

**Technical Approach:**
Single change point: `sli_build_base_json()` in `emit_common.sh`. The jq expression that builds the base JSON object must produce nested `workflow` object instead of flat `workflow_*` fields. All other code (emit_oci.sh, emit_curl.sh, emit.sh) calls `sli_build_base_json()` and gets the new schema automatically.

**Dependencies:**
SLI-14 overlaps — repo fields initially part of SLI-13 scope are carved out into `repo.*` by SLI-14. Implement as one atomic change in `emit_common.sh`.

**Testing Strategy:**
Update `sli_build_base_json` unit test in `tests/unit/test_emit.sh` to assert new nested shape. Integration tests (`test_sli_integration.sh`, `test_sli_emit_curl_local.sh`, `test_sli_emit_curl_workflow.sh`) query OCI logs with jq — update filter paths.

**Compatibility Notes:**
Breaking schema change. Any OCI Logging queries referencing `workflow_run_id`, `workflow_run_number`, `workflow_ref`, etc. will need updating. Documented in SLI-15.

---

### SLI-14: Move repository-related attributes into `repo` map

**Requirement Summary:**
Extract git/repository state fields from the flat payload into a nested `repo` object.

**Fields being moved:**
- `repository` → `repo.repository` (GITHUB_REPOSITORY)
- `repository_id` → `repo.repository_id` (GITHUB_REPOSITORY_ID)
- `ref` → `repo.ref` (GITHUB_REF_NAME — branch/tag short name)
- `ref_full` → `repo.ref_full` (GITHUB_REF — full ref path)
- `sha` → `repo.sha` (GITHUB_SHA)

**Technical Approach:**
Same change as SLI-13: modify the jq expression in `sli_build_base_json()`. Implement together with SLI-13 as one atomic payload change.

**Dependencies:**
SLI-13. Both implemented in the same function change.

**Compatibility Notes:**
`ref` currently refers to `GITHUB_REF_NAME` (e.g. `main`). After nesting: `repo.ref` = short name, `repo.ref_full` = full path.

---

### SLI-15: Update docs/tests/queries for nested `workflow` + `repo` schema

**Requirement Summary:**
After SLI-13+14 change the payload, update all downstream consumers: unit test assertions, integration test jq filters, design docs, README examples.

**Scope:**
1. `tests/unit/test_emit.sh` — `sli_build_base_json` test: update `want` variable to nested schema
2. `tests/integration/test_sli_integration.sh` — update `.workflow_run_id` references to `.workflow.run_id`, etc.
3. `tests/integration/test_sli_emit_curl_local.sh` — same jq path updates
4. `tests/integration/test_sli_emit_curl_workflow.sh` — same jq path updates
5. `tests/smoke/test_critical_emit.sh` — check if it references old flat fields
6. Documentation: `progress/sprint_3/sprint_3_design.md` payload example, README

**Technical Approach:**
Systematically grep for old field references across test files and update jq path expressions. Document new schema in design doc.

---

## Overall Sprint Assessment

**Feasibility:** High
The entire change is localized in `sli_build_base_json()` in `emit_common.sh` — one jq expression change propagates everywhere. Downstream update is mechanical search-and-replace of jq paths.

**Estimated Complexity:** Moderate
The implementation is simple (one function). The test update is moderately complex because there are multiple integration test files with jq filter chains.

**Prerequisites Met:** Yes — Sprint 9 complete, test infrastructure in place.

**Open Questions:** None.

## Recommended Design Focus Areas

- Final schema definition (decide field names in `workflow.*` and `repo.*` precisely)
- OCI log query examples using new paths (for documentation and verification)
- Integration test jq filter update strategy (grep-driven, systematic)

## YOLO Mode Decisions

### Assumption 1: Single atomic implementation
**Issue:** SLI-13 and SLI-14 both modify `sli_build_base_json`. Implementing separately would leave tests broken between them.
**Assumption Made:** Implement SLI-13 + SLI-14 together as one atomic change to `sli_build_base_json`.
**Rationale:** Avoids broken intermediate state; simpler git history.
**Risk:** Low

## Readiness for Design Phase

Confirmed Ready
