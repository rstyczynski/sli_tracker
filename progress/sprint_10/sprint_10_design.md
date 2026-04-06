# Sprint 10 - Design

## SLI-13 + SLI-14: Nest `workflow` and `repo` metadata in emitted events

Status: Accepted

### Requirement Summary

Restructure the SLI event payload: group GitHub Actions runtime metadata under `workflow.*` and repository/git state under `repo.*`. Remove all old top-level flat fields. Breaking schema change.

### Feasibility Analysis

**API Availability:**
Pure in-process change — no external API calls. `sli_build_base_json()` in `emit_common.sh` already uses `jq -nc` to build the payload object. Nesting is trivially expressed in jq by grouping keys under sub-objects.

**Technical Constraints:**
- `sli_unescape_json_fields` operates on top-level string values via `with_entries`. After nesting, `workflow` and `repo` values are objects, not strings — they are not affected by the unescaping logic. No change needed to `sli_unescape_json_fields`.
- `sli_build_log_entry` merges `base + flat_context + failure_reasons` using `. + $ctx`. User-provided context fields overlay the base. If a caller passes `workflow: "string"` in context-json it will override the nested object — acceptable legacy behavior, not in scope.

**Risk Assessment:**
- Breaking change: all consumers asserting old field paths will fail until updated (SLI-15 scope).
- Low implementation risk: single function change, all transports call it.

### Design Overview

**Architecture:**
Single change point: `sli_build_base_json()` in `.github/actions/sli-event/emit_common.sh`. All three transports (`emit.sh`, `emit_oci.sh`, `emit_curl.sh`) call this function — they inherit the new schema automatically.

**New Payload Schema:**

```json
{
  "source":     "github-actions/sli-tracker",
  "outcome":    "<SLI_OUTCOME>",
  "timestamp":  "<ISO-8601>",
  "workflow": {
    "run_id":      "<GITHUB_RUN_ID>",
    "run_number":  "<GITHUB_RUN_NUMBER>",
    "run_attempt": "<GITHUB_RUN_ATTEMPT>",
    "name":        "<GITHUB_WORKFLOW>",
    "ref":         "<GITHUB_WORKFLOW_REF>",
    "job":         "<GITHUB_JOB>",
    "event_name":  "<GITHUB_EVENT_NAME>",
    "actor":       "<GITHUB_ACTOR>"
  },
  "repo": {
    "repository":    "<GITHUB_REPOSITORY>",
    "repository_id": "<GITHUB_REPOSITORY_ID>",
    "ref":           "<GITHUB_REF_NAME>",
    "ref_full":      "<GITHUB_REF>",
    "sha":           "<GITHUB_SHA>"
  },
  "failure_reasons": {},
  "<user-context-fields>": "..."
}
```

**Old → New field mapping:**

| Old top-level field  | New path              | Source env var          |
|----------------------|-----------------------|-------------------------|
| `workflow_run_id`    | `workflow.run_id`     | GITHUB_RUN_ID           |
| `workflow_run_number`| `workflow.run_number` | GITHUB_RUN_NUMBER       |
| `workflow_run_attempt`| `workflow.run_attempt`| GITHUB_RUN_ATTEMPT      |
| `workflow` (string)  | `workflow.name`       | GITHUB_WORKFLOW         |
| `workflow_ref`       | `workflow.ref`        | GITHUB_WORKFLOW_REF     |
| `job`                | `workflow.job`        | GITHUB_JOB              |
| `event_name`         | `workflow.event_name` | GITHUB_EVENT_NAME       |
| `actor`              | `workflow.actor`      | GITHUB_ACTOR            |
| `repository`         | `repo.repository`     | GITHUB_REPOSITORY       |
| `repository_id`      | `repo.repository_id`  | GITHUB_REPOSITORY_ID    |
| `ref`                | `repo.ref`            | GITHUB_REF_NAME         |
| `ref_full`           | `repo.ref_full`       | GITHUB_REF              |
| `sha`                | `repo.sha`            | GITHUB_SHA              |

Unchanged top-level: `source`, `outcome`, `timestamp`, `failure_reasons`, all user context fields.

### Technical Specification

**File to change:** `.github/actions/sli-event/emit_common.sh`

**Function:** `sli_build_base_json()`

Replace current jq expression (flat object) with nested structure:

```bash
sli_build_base_json() {
  local ts="${SLI_TIMESTAMP:-}"
  [[ -z "$ts" ]] && ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  jq -nc \
    --arg ts        "$ts" \
    --arg outcome   "${SLI_OUTCOME:?SLI_OUTCOME required}" \
    --arg run_id    "${GITHUB_RUN_ID:-}" \
    --arg run_num   "${GITHUB_RUN_NUMBER:-}" \
    --arg run_att   "${GITHUB_RUN_ATTEMPT:-}" \
    --arg repo      "${GITHUB_REPOSITORY:-}" \
    --arg repo_id   "${GITHUB_REPOSITORY_ID:-}" \
    --arg ref       "${GITHUB_REF_NAME:-}" \
    --arg ref_full  "${GITHUB_REF:-}" \
    --arg sha       "${GITHUB_SHA:-}" \
    --arg wf        "${GITHUB_WORKFLOW:-}" \
    --arg wf_ref    "${GITHUB_WORKFLOW_REF:-}" \
    --arg job_id    "${GITHUB_JOB:-}" \
    --arg ev        "${GITHUB_EVENT_NAME:-}" \
    --arg actor     "${GITHUB_ACTOR:-}" \
    '{
      source:    "github-actions/sli-tracker",
      outcome:   $outcome,
      timestamp: $ts,
      workflow: {
        run_id:      $run_id,
        run_number:  $run_num,
        run_attempt: $run_att,
        name:        $wf,
        ref:         $wf_ref,
        job:         $job_id,
        event_name:  $ev,
        actor:       $actor
      },
      repo: {
        repository:    $repo,
        repository_id: $repo_id,
        ref:           $ref,
        ref_full:      $ref_full,
        sha:           $sha
      }
    }'
}
```

---

## SLI-15: Update docs/tests/queries for nested schema

Status: Accepted

### Requirement Summary

Update all downstream consumers that reference old flat field paths so all quality gates pass with the new schema.

### Files to Update

**1. `tests/unit/test_emit.sh`** — `sli_build_base_json` test (line ~140)

Update `want` variable from flat schema to nested schema.

**2. `tests/integration/test_sli_integration.sh`** — jq filter updates:

| Line | Old expression | New expression |
|------|---------------|----------------|
| 306 | `(.workflow // "") \| type == "string" and test("API / UI call")` | `(.workflow.name // "") \| test("API / UI call")` |
| 307 | `(.workflow // "") \| type == "string" and test("Push trigger")` | `(.workflow.name // "") \| test("Push trigger")` |
| 314 | `(.job // "") == "sli-init"` | `(.workflow.job // "") == "sli-init"` |
| 317 | `(.job // "") == "leaf"` | `(.workflow.job // "") == "leaf"` |

**3. `tests/integration/test_sli_emit_curl_local.sh`** — line 179:

Old: `select(.workflow != null) | select(.workflow | test("LOCAL — emit_curl"))`
New: `select(.workflow.name != null) | select(.workflow.name | test("LOCAL — emit_curl"))`

**4. `tests/integration/test_sli_emit_curl_workflow.sh`** — line 269:

Old: `select(.workflow != null) | select(.workflow | test("emit_curl"))`
New: `select(.workflow.name != null) | select(.workflow.name | test("emit_curl"))`

**5. Smoke test** — no old flat field references found; no change needed.

### Testing Strategy

#### Recommended Sprint Parameters
- Test: unit, integration (as per PLAN.md)
- Regression: unit, integration (as per PLAN.md)

#### Unit Test Targets
- **Component:** `tests/unit/test_emit.sh` → `sli_build_base_json` test
- **Functions to test:** `sli_build_base_json` — assert `workflow.*` and `repo.*` nested shape
- **Key inputs:** fake GITHUB_* env vars (already established in test)
- **Isolation:** no mocks needed; jq is available

#### Integration Test Scenarios
- **Scenario:** emit_oci workflow dispatched and events verified in OCI Logging via new jq paths
- **Scenario:** emit_curl local run with new schema, verified via jq on OCI log response
- **Scenario:** emit_curl workflow dispatched and events verified via new `.workflow.name` path
- **Infrastructure dependencies:** OCI tenancy, GitHub secrets, `gh` CLI

#### Smoke Test Candidates
- `test_critical_emit.sh` — already passes; verifies emit produces valid JSON. No field-path assertions, so unaffected.

---

# Design Summary

## Overall Architecture

Single implementation change in `emit_common.sh::sli_build_base_json()` propagates new schema to all three transports. SLI-15 updates are mechanical path substitutions in test jq filters.

## Shared Components

`emit_common.sh` is the only file with payload logic. All transports source it.

## Design Risks

- Integration tests query live OCI Logging — test results depend on events having been emitted with new schema. The new-code gate (Phase A) uses `--new-only` manifest; regression gate (Phase B) runs full suite including integration tests, which require GitHub workflow runs to produce events.
- YOLO degradation threshold: integration >=80% acceptable if flaky OCI delays occur.

## Resource Requirements

No new tools. Existing: bash, jq, oci, gh, openssl.

## Design Approval Status

Accepted (YOLO mode — auto-approved after 60s)

## YOLO Mode Decisions

### Decision 1: Implement SLI-13 + SLI-14 atomically
**Context:** Both modify `sli_build_base_json`; separate implementation leaves intermediate broken state.
**Decision Made:** Single atomic change.
**Rationale:** Cleaner git history; tests don't fail between partial implementations.
**Risk:** Low

### Decision 2: Keep `event_name` and `actor` inside `workflow`
**Context:** SLI-13 spec includes them; SLI-14 doesn't move them.
**Decision Made:** `workflow.event_name` and `workflow.actor`.
**Rationale:** Matches SLI-13 spec exactly; consistent grouping of GitHub Actions runtime context.
**Risk:** Low

## LLM Token Statistics

Phase: Elaboration | Tokens: ~20k input (emit_common.sh, all test files, analysis)
