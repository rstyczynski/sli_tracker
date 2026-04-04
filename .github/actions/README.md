# GitHub Actions (SLI)

Composite actions used by the model workflows under [`.github/workflows`](../workflows/).

## `sli-event`

Builds one JSON log entry (GitHub execution identity + caller context + `failure_reasons`) and optionally pushes it to **OCI Logging** via `oci logging-ingestion put-logs`. The composite step should use **`continue-on-error: true`** so reporting never fails the job.

| Piece | Role |
|--------|------|
| [`sli-event/action.yml`](sli-event/action.yml) | Declares inputs and runs [`sli-event/emit.sh`](sli-event/emit.sh). |
| [`sli-event/emit.sh`](sli-event/emit.sh) | All `jq` / merge logic; reads **GitHub default env** (`GITHUB_*`) plus `SLI_*` inputs. |

### Inputs

| Input | Required | Purpose |
|-------|----------|---------|
| `outcome` | yes | Reported outcome (e.g. `${{ job.status }}` or a step outcome). |
| `inputs-json` | no | `${{ toJSON(inputs) }}` for `workflow_call` inputs — merged flat into the payload. |
| `context-json` | no | Extra JSON; **`oci`** is used only for the CLI (`config-file`, `profile`, optional `log-id`). Other keys merge on top of `inputs-json`. |
| `steps-json` | no | `${{ toJSON(steps) }}` — failed steps become `failure_reasons` keys `SLI_FAILURE_REASON_<STEP_ID>`. |

Repo variable **`SLI_OCI_LOG_ID`** selects the log (OCID). If unset or OCI config is missing, the payload is still printed to the step log; push is skipped.

Optional env for local checks: **`SLI_SKIP_OCI_PUSH`** (skip `oci` push).

### Payload (summary)

- **Identity:** `source`, `outcome`, `workflow_run_id`, `workflow_run_number`, `workflow_run_attempt`, `repository`, `repository_id`, `ref`, `ref_full`, `sha`, `workflow`, `workflow_ref`, `job`, `event_name`, `actor`, `timestamp` (from `GITHUB_*` + `SLI_OUTCOME`).
- **Domain:** merged from `inputs-json` and non-`oci` fields in `context-json` (keys follow workflow input ids, e.g. `"run-type"`).
- **`failure_reasons`:** from `steps-json` (failed step ids) and any **`SLI_FAILURE_REASON_*`** env vars (env wins on key clash).

### Tests

```bash
bash .github/actions/sli-event/tests/test_emit.sh
```

Requires `bash`, `jq`, and `date` on `PATH`.

---

## `install-oci-cli`

Installs OCI CLI on a Linux (Ubuntu/Debian) runner. See [`install-oci-cli/README.md`](install-oci-cli/README.md).

