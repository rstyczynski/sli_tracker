# GitHub Actions SLI Model

A minimal workflow model that demonstrates all techniques used in this repo's GitOps pipeline, instrumented with SLI event emission for SLA traceability.

## Purpose

Model real pipeline patterns in a self-contained, runnable form — used to develop and test SLI instrumentation before applying it to production workflows.

## Files

### Workflows (`workflows/`)

| File | Represents | Trigger |
|------|-----------|---------|
| `model-pr.yml` | `001-governance.yml`, `010-unit-tests.yml` | Pull request |
| `model-push.yml` | `100-release.yml`, `001-governance.yml` (push) | Push / `workflow_dispatch` |
| `model-call.yml` | External / manual invoke | `workflow_dispatch` (UI) / `repository_dispatch` (API) |
| `model-reusable-main.yml` | `reusable-020-terrateam.yml`, `reusable-900/901-destroy.yml` | `workflow_call` |
| `model-reusable-sub.yml` | terrateam job inside `reusable-020-terrateam.yml` | `workflow_call` |

### Actions (`../actions/`)

Documented in **[`.github/actions/README.md`](../actions/README.md)** — `sli-event` (payload + OCI push).

## Techniques Modelled

1. **PR / push / API / UI** triggers calling reusable workflows
2. **Two-job pattern**: `init` (runner selection) → `main` (matrix over environments)
3. **`if: always() && needs.init.result == 'success'`** — main runs even if init is skipped
4. **Matrix job** calling reusable `sub` per environment (`fail-fast: false`)
5. **`uses:` action** with outputs consumed by next step (simulates `oci-auth`)
6. **`run:` bash** writing `$GITHUB_OUTPUT` (simulates `installator plan`)
7. **Step conditional on prior output**: `if: steps.X.outputs.Y == 'Z'`
8. **Step conditional on input**: `if: inputs.X != ''`
9. **`env:` block** on step (simulates terrateam `ARM_*`, `OCI_*` vars)
10. **`simulate-failure` input** — forces `step-main` to fail for SLI testing

## SLI Instrumentation

### Two independent SLI event streams

| Stream | Job | Typical inputs | Meaning |
|--------|-----|----------------|--------|
| Pipeline health | `sli-init` in `main` | (init outputs) | Was the pipeline setup successful? |
| Deployment health | `sli-event` in `sub` | `inputs-json` + `steps-json` | Per-env run + failed steps |

### SLI event shape (conceptual)

The log entry is one JSON object: **GitHub identity** (run, repo, ref, workflow, job, actor, …), **merged caller fields** from `inputs-json` / `context-json`, and **`failure_reasons`** (from `steps-json` and optional `SLI_FAILURE_REASON_*` env vars).

Example (abbreviated):

```json
{
  "source": "github-actions/sli-tracker",
  "outcome": "failure",
  "workflow_run_id": "…",
  "repository": "owner/repo",
  "workflow": "MODEL — Reusable sub",
  "job": "leaf",
  "ref": "main",
  "sha": "abc123",
  "timestamp": "2026-04-02T10:00:00Z",
  "environment": "model-env-1",
  "run-type": "apply",
  "instance": "1",
  "failure_reasons": {
    "SLI_FAILURE_REASON_STEP_MAIN": "step_id=step-main; outputs={}"
  }
}
```

Keys such as **`run-type`** follow **`toJSON(inputs)`** from the reusable workflow (input ids), not hand-renamed snake_case.

### Failure reasons

- **Default path:** pass **`steps-json: ${{ toJSON(steps) }}`** into `sli-event` — failed step ids appear under `failure_reasons`.
- **Optional:** set **`SLI_FAILURE_REASON_*`** env vars directly in a step before `sli-event` runs; those override the same key derived from `steps-json`.

### Ghost step

```yaml
- uses: ./.github/actions/sli-event
  if: ${{ !cancelled() }}
  continue-on-error: true
```

The action script exits **0** even on internal errors (warnings only). Use **`${{ !cancelled() }}`** so YAML does not treat `!` as a tag.

### OCI destination

Set repo-level variable **`SLI_OCI_LOG_ID`** to the target log OCID. Pass **`oci`** inside **`context-json`** (`config-file`, `profile`) for the CLI. If OCI push is not configured, the payload still appears in the Actions log.

## Testing

1. **Actions → MODEL — Push trigger → Run workflow** (or **MODEL — API / UI call** from the UI).
2. Enable **Force the main step to fail** where offered.
3. Confirm **`step-main`** fails, **`SLI Report`** still runs, log payload includes **`failure_reasons`**, and the workflow result is governed by the real steps, not by `sli-event`.
