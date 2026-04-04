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

**Defects found:**
1. **CRITICAL — missing action:** `model-reusable-main.yml` calls `./.github/actions/sli-failure-reason` which did not exist. GitHub workflow would fail when init fails. **Fix:** create `sli-failure-reason/action.yml`.
2. **sli-init OCI push** — `oci: {}` empty in the init SLI context-json; init SLI events print payload but never push to OCI. Intentional (OCI auth runs in sub, not init), documented.

## SLI-4 — sli-event

| Piece | Contract |
|-------|----------|
| Inputs | `outcome`, `inputs-json`, `context-json`, `steps-json` |
| Payload | `sli_build_base_json` + flat merge + `failure_reasons` |
| OCI | `SLI_OCI_LOG_ID` var + `oci` block in context-json |
| Safety | Always `exit 0`; push failures → `::warning::` |

**Defects found:**
1. **`sli_expand_oci_config_path` silent bug:** `case "$p" in "~"|~/*` — unquoted `~/*` is treated as a filesystem glob in bash case patterns, not a literal `~/` prefix. Hidden paths (`.oci/config`) never match. **Fix:** use `"~/"*` pattern + `${p:1}` slice.
2. **Test subshell counter isolation:** both `sli_expand_oci_config_path` and `sli_build_base_json` tests ran inside `(...)` subshells; `passed`/`failed` increments were silently discarded. Two failures were invisible in the summary. **Fix:** save/restore env vars in the parent shell.
3. **Hardcoded `source: "github-actions/terrateam"`** in `emit.sh` base payload — wrong project name. **Fix:** `"github-actions/sli-tracker"`.

## YOLO decisions

1. `sli-failure-reason` is a new file (one action.yml); no tests needed beyond it existing and the action being structurally valid YAML.
2. `source` field rename is a payload schema change — no downstream consumer in the repo yet, safe to rename.
