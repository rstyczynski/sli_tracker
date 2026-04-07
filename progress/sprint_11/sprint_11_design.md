# Sprint 11 Design — SLI-16: JS Action with pre/post hooks

## Overview

Create `.github/actions/sli-event-js/` — a JavaScript GitHub Action that uses native
`pre`/`post` hooks to wire OCI profile setup (pre) and SLI event emission (post) into
a single action declaration. Callers no longer need separate `oci-profile-setup` and
`sli-event` steps.

## File Structure

```
.github/actions/sli-event-js/
├── action.yml      — declares pre/main/post entry points + inputs
├── pre.js          — OCI profile restore (calls existing oci_profile_setup.sh)
├── index.js        — noop main (required by GitHub Actions JS runner)
└── post.js         — SLI emit via curl (calls existing emit.sh)

.github/workflows/
└── model-emit-js.yml   — proof-of-concept workflow using the new action

tests/integration/
└── test_sli_emit_js_workflow.sh   — dispatches model-emit-js.yml, verifies OCI
```

## action.yml Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `oci-config-payload` | no | `""` | Base64 OCI config payload. If empty, pre hook is a no-op. |
| `profile` | no | `SLI_TEST` | OCI profile name. |
| `log-id` | no | `""` | OCI log OCID. Falls back to `SLI_OCI_LOG_ID` env var. |
| `outcome` | no | `""` | SLI outcome override. Falls back to `GITHUB_JOB_STATUS` env, then `success`. |
| `oci-api-domain` | no | `oraclecloud.com` | OCI API domain override. |

## Execution Flow

```
Job starts
  ↓
[pre hook: pre.js]
  • if oci-config-payload set → run oci_profile_setup.sh (OCI_AUTH_MODE=none)
  • else → debug log and exit 0
  ↓
[main: index.js]   — exits 0 immediately
  ↓
[user's steps run]  e.g. checkout, build, test
  ↓
[post hook: post.js]  — runs even if steps failed (post-if: always())
  • resolve outcome: INPUT_OUTCOME → GITHUB_JOB_STATUS → "success"
  • build SLI_CONTEXT_JSON with oci block (config-file, profile, log-id)
  • exec emit.sh with EMIT_BACKEND=curl
```

## Key Implementation Details

**No npm dependencies** — uses only Node.js built-ins (`child_process`, `path`).
No bundling or `node_modules` directory needed.

**Path resolution** — `pre.js` and `post.js` resolve sibling action scripts using `__dirname`:
- `oci_profile_setup.sh`: `path.join(__dirname, '../oci-profile-setup/oci_profile_setup.sh')`
- `emit.sh`: `path.join(__dirname, '../sli-event/emit.sh')`

**`OCI_AUTH_MODE=none`** in pre hook — skips the `oci` CLI wrapper installation
(curl backend does its own request signing; OCI CLI not needed).

**Outcome resolution in post.js:**
1. `INPUT_OUTCOME` — caller-provided override (supports `${{ job.status }}` when passed explicitly)
2. `GITHUB_JOB_STATUS` — set by runner in post-phase on supported runner versions
3. `"success"` — safe fallback

**`STEPS_JSON`** not passed — this sprint emits outcome-only (no per-step failure_reasons).
Enhancement left for a future sprint.

## model-emit-js.yml Design

```yaml
on:
  workflow_dispatch:
    inputs:
      simulate-failure: { type: boolean, default: false }

jobs:
  emit-js:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ./.github/actions/sli-event-js
        with:
          oci-config-payload: ${{ secrets.OCI_CONFIG_PAYLOAD }}
          profile: SLI_TEST
          log-id: ${{ vars.SLI_OCI_LOG_ID }}
      - name: "Main step"
        id: step-main
        run: |
          [[ "${{ inputs.simulate-failure }}" == "true" ]] && exit 1
          echo "Main step completed"
```

## Testing Strategy

**Test level:** Integration only (per Phase 0 banner: `Test: integration`).
**Regression:** None (per Phase 0 banner: `Regression: none` — no existing files modified).

Integration test `test_sli_emit_js_workflow.sh` validates:
- IT-JS-1: Workflow dispatch (success + failure runs)
- IT-JS-2: Both runs complete
- IT-JS-3: Expected workflow conclusions (success/failure)
- IT-JS-4: No OCI CLI install in job logs (pre hook, not oci-profile-setup composite)
- IT-JS-5: Pre hook notice present in job logs
- IT-JS-6: SLI events arrive in OCI Logging with correct outcome
- IT-JS-7: Events carry `workflow.name` matching `emit_js`

## Test Specification

### IT-JS-1: Workflow dispatch
**Purpose:** Verify `model-emit-js.yml` can be triggered via `gh workflow run`.
**Setup:** `gh workflow run model-emit-js.yml -f simulate-failure=false` and `=true`.
**Assert:** Both dispatch calls succeed and return run IDs.

### IT-JS-2: Run completion
**Purpose:** Both dispatched runs complete within timeout.
**Assert:** `gh run view` shows `completed/*` for both run IDs.

### IT-JS-3: Expected conclusions
**Purpose:** Success run concludes `success`; failure run concludes `failure`.
**Assert:** `gh run view --json conclusion` matches expected value.

### IT-JS-4: No OCI CLI install
**Purpose:** pre hook must NOT trigger `install-oci-cli` — credentials come from `oci-config-payload`.
**Assert:** Job logs do NOT contain `install-oci-cli` or `Installing OCI CLI`.

### IT-JS-5: Pre hook notice
**Purpose:** Confirm pre hook ran and restored the OCI profile.
**Assert:** Job logs contain `OCI profile` (from `oci_profile_setup.sh` notice output or pre.js).

### IT-JS-6: OCI events arrive
**Purpose:** SLI events emitted by post hook reach OCI Logging.
**Assert:** At least 2 events (one success, one failure) found in OCI Logging.

### IT-JS-7: Correct workflow.name
**Purpose:** Events are tagged with the correct workflow name.
**Assert:** Events have `workflow.name` containing `emit_js`.
