# Sprint 3 — Design

## SLI-3 — model-* workflows

Status: **Accepted** (YOLO auto-approve)

| Workflow | Role |
|----------|------|
| `model-call.yml` | `workflow_dispatch` + `repository_dispatch` → calls reusable main |
| `model-pr.yml` / `model-push.yml` | PR/push triggers |
| `model-reusable-main.yml` | `workflow_call`: init → sli-init (always) → matrix → sub |
| `model-reusable-sub.yml` | Per-env job; emits via `sli-event` |

**Design notes:** Naming prefix `MODEL —` distinguishes from production. `simulate-failure` drives negative paths. `sli-init` uses `if: always()` for setup-level SLI — matches stated goal (init vs deploy dimensions).

## SLI-4 — sli-event

Status: **Accepted** (YOLO auto-approve)

| Piece | Contract |
|-------|----------|
| Inputs | `outcome`, `inputs-json`, `context-json`, `steps-json` |
| Payload | `sli_build_base_json` + flat merge + `failure_reasons` |
| OCI | `SLI_OCI_LOG_ID` / `vars`; `oci` in context-json for `config-file`, `profile`, `log-id` |
| Safety | `exit 0` always; push failures → `::warning::` |

## YOLO Mode Decisions

1. **No new inputs** on sli-event this sprint — review only.
2. **Diagrams skipped** — table above replaces mermaid (YOLO speed).
3. **Acceptance:** `bash .github/actions/sli-event/tests/test_emit.sh` passes.

## Design Summary

Reviews are documentation-first; implementation changes deferred unless blocking — none found.
