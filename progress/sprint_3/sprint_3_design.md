# Sprint 3 — Design

Status: **Accepted** (YOLO auto-approve)

## SLI-3 — model-* workflows

| Workflow | Role |
|----------|------|
| `model-call.yml` | `workflow_dispatch` + `repository_dispatch` → calls reusable main |
| `model-pr.yml` | PR event trigger (hardcoded plan run, no simulate-failure input) |
| `model-push.yml` | Push + `workflow_dispatch` trigger (simulate-failure available) |
| `model-reusable-main.yml` | `workflow_call`: init → sli-init (always) → matrix → sub |
| `model-reusable-sub.yml` | Per-env leaf job; demonstrates 7 step techniques; emits via `sli-event` |

**Defects found during code review:**

1. **CRITICAL — spurious action call:** `model-reusable-main.yml` called `./.github/actions/sli-failure-reason` which added no value — `steps-json` already captures all failed step reasons automatically. **Fix:** remove the companion step and the action entirely.
2. **sli-init OCI push** — `oci: {}` empty in the init SLI context-json; init SLI events print payload but never push to OCI. Initially documented as intentional.

**Defects found during integration testing (B1–B6):**

3. **B1 — `vars` context in composite action YAML:** `vars.SLI_OCI_LOG_ID` referenced in `action.yml` env block; `vars` context is not valid inside composite action YAML. Template validation error at runtime. **Fix:** remove from action.yml; callers pass `oci.log-id` in `context-json`.
4. **B2 — `${{ }}` in YAML description strings:** `${{ toJSON(inputs) }}` in input `description:` fields is evaluated as a template expression, causing validation errors for `inputs` and `steps` contexts. **Fix:** rewrite descriptions to plain text.
5. **B3 — `GITHUB_ENV PATH` not expanded:** `oci_profile_setup.sh` wrote `PATH=<wrap_dir>:\$PATH` to `$GITHUB_ENV`. GitHub Actions reads this literally — `$PATH` is never expanded — leaving the runtime PATH as just the wrapper dir. `bash` becomes unfindable in subsequent steps. **Fix:** remove the GITHUB_ENV line; `GITHUB_PATH` correctly prepends.
6. **B4 — `--specversion` now required:** OCI CLI 3.77 made `--specversion` required for `logging-ingestion put-logs`. **Fix:** add `--specversion "1.0"`.
7. **B5 — OCI batch missing required fields:** OCI Logging requires `source`, `type`, and `id` inside each log-entry-batch. **Fix:** add `source: "github-actions/sli-tracker"`, `type: "sli-event"`, `id: "<ts>-sli"` to the batch JSON.
8. **B6 — sli-init context-json invalid JSON:** `context-json` in `sli-init` embedded `needs.init.outputs.environments-json` (a raw JSON array) inside a double-quoted YAML string, producing invalid JSON. `sli_normalize_json_object` silently falls back to `{}`; the `oci` block is lost and push is skipped. **Fix:** move init outputs to `inputs-json: ${{ toJSON(needs.init.outputs) }}`; keep only the OCI block in `context-json`.

## SLI-4 — sli-event

| Piece | Contract |
|-------|----------|
| Inputs | `outcome`, `inputs-json`, `context-json`, `steps-json` |
| Payload | `sli_build_base_json` + flat merge + `failure_reasons` |
| OCI | `oci.log-id` in context-json + `oci.config-file` + `oci.profile` |
| Safety | Always `exit 0`; push failures → `::warning::` |

**Defects found during code review:**

1. **`sli_expand_oci_config_path` silent bug:** `case "$p" in "~"|~/*` — unquoted `~/*` is treated as a filesystem glob in bash case patterns, not a literal `~/` prefix. Hidden paths (`.oci/config`) never match. **Fix:** use `"~/"*` pattern + `${p:1}` slice.
2. **Test subshell counter isolation:** both `sli_expand_oci_config_path` and `sli_build_base_json` tests ran inside `(...)` subshells; `passed`/`failed` increments were silently discarded. Two failures were invisible in the summary. **Fix:** save/restore env vars in the parent shell.
3. **Hardcoded `source: "github-actions/terrateam"`** in `emit.sh` base payload — wrong project name. **Fix:** `"github-actions/sli-tracker"`.

## YOLO decisions

1. `sli-failure-reason` removed entirely — `steps-json` pattern is sufficient and cleaner.
2. `source` field rename is a payload schema change — no downstream consumer in the repo yet, safe to rename.
3. Integration bugs B1–B6 were fixed as found; no design rework required — all fixes were localised to the affected file.
