# Sprint 11 Implementation — SLI-16

## Files Created

| File | Purpose |
|------|---------|
| `.github/actions/sli-event-js/action.yml` | JS action declaration: `main: index.js`, `post: post.js` (no `pre` — not supported for local actions) |
| `.github/actions/sli-event-js/index.js` | Main entry point: no-op (required by GitHub Actions JS runner) |
| `.github/actions/sli-event-js/post.js` | Post hook: emits SLI event via `emit.sh` (EMIT_BACKEND=curl) |
| `.github/workflows/model-emit-js.yml` | Proof workflow: `oci-profile-setup` then main work then `sli-event-js` |
| `tests/integration/test_sli_emit_js_workflow.sh` | Integration test (dispatches workflow, verifies OCI Logging) |

## No npm dependencies

All JS files use only Node.js built-ins (`child_process`, `path`, `fs`). No `node_modules`,
no bundling step, no `package.json` needed.

## Key Design Decisions

**Outcome resolution in post.js** (in priority order):
1. `INPUT_OUTCOME` — caller-provided via `with.outcome: ${{ job.status }}`
2. `GITHUB_JOB_STATUS` — set by GitHub runner in post-phase on supported versions
3. `"success"` — safe fallback

**OCI_AUTH_MODE=none** — `model-emit-js.yml` passes this to `oci-profile-setup` so no `oci` CLI wrapper is installed.
The curl backend in `emit.sh` does its own request signing.

**Exit 0 from post hook** — SLI reporting must never break the job. All emit errors
are surfaced as `::notice::` warnings, not failures.

**Path resolution in post.js** — `emit.sh` via `__dirname`:
- `../sli-event/emit.sh`

## Existing Files Not Modified

- `sli-event/action.yml` — unchanged composite action
- `emit.sh`, `emit_curl.sh`, `emit_common.sh` — unchanged
- Other `model-*.yml` workflows — unchanged
