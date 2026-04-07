## Contract

Sprint 11 — YOLO mode. Rules understood from prior sprints (contracting executed in Sprint 7).

**Responsibilities:**
- Create new files only; must not modify existing sli-event, emit_curl.sh, or model workflows
- All quality gates require timestamped log files
- Git: semantic commits, push after each phase

**Constraints for SLI-16:**
- Do not modify existing composite action (sli-event)
- Do not modify existing model workflows
- Do not touch emit_*.sh scripts
- YOLO: auto-approve all design decisions, 10-min construction limit

**Open Questions:** None — scope is well-defined.

---

## Analysis

### SLI-16: JavaScript GitHub Action with pre/post hooks

**Requirement Summary:**
Build a JavaScript GitHub Action (not composite) that:
1. `pre` hook: if `oci-config-payload` input provided, restore OCI profile via existing `oci_profile_setup.sh`
2. `main`: no-op (JS actions require a main entry point)
3. `post` hook: emit SLI event to OCI Logging via curl backend (reuse `emit.sh`)

The action replaces the two-step pattern (separate `oci-profile-setup` step + `sli-event` step at end) with a single action declaration that auto-wires setup and reporting.

**Technical Approach:**
- `using: node20` action with `pre: pre.js`, `main: index.js`, `post: post.js`
- `pre.js`: read `INPUT_OCI_CONFIG_PAYLOAD`; if set, call existing `oci_profile_setup.sh` via `spawnSync` with `OCI_AUTH_MODE=none` (curl doesn't need the oci wrapper)
- `index.js`: exits 0 (required main entry point)
- `post.js`: read inputs (log-id, profile, outcome); call `emit.sh` with `EMIT_BACKEND=curl`; outcome sourced from `INPUT_OUTCOME` → `GITHUB_JOB_STATUS` env → `success` fallback
- No npm dependencies — uses only Node.js built-in `child_process` and `path`

**Dependencies:**
- Reuses `.github/actions/oci-profile-setup/oci_profile_setup.sh` (pre hook)
- Reuses `.github/actions/sli-event/emit.sh` (post hook) — path computed via `__dirname`
- No new shared libraries

**Compatibility Notes:**
- Does not replace or modify the existing `sli-event` composite action
- Existing model workflows remain unchanged
- Sprint 11 only adds: new action dir + new model workflow + integration test

**Testing Strategy:**
- Integration test only (per `Test: integration`)
- No regression (per `Regression: none`) — no existing files modified

**Feasibility:** High — minimal JS, no bundling required, reuses all existing bash infra.

**YOLO Decisions:**
1. `GITHUB_JOB_STATUS` env var availability in post hooks: uncertain across runner versions. Mitigation: fall back to `INPUT_OUTCOME` (caller can pass `${{ job.status }}` explicitly), then default `success`.
2. `OCI_AUTH_MODE=none` in pre hook: skips oci wrapper installation (correct for curl-only path).
3. Steps-json not passed in post hook: outcome-only emit (no per-step failure_reasons). Acceptable for proof-of-concept; failure_reasons can be added in a follow-up.
