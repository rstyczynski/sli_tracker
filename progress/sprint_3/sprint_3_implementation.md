# Sprint 3 — Implementation

**Sprint status:** implemented

## SLI-3 — model-* workflows

| Check | Result |
|-------|--------|
| Call graph | `model-call` / PR / push → `model-reusable-main` → `model-reusable-sub` |
| SLI coverage | `sli-event` at leaf job level; `sli-event` + `sli-failure-reason` at init level |
| Naming | Consistent `MODEL —` prefix; inline comments document each technique |
| Bug fixed | Created `.github/actions/sli-failure-reason/action.yml` (was missing; broke init-failure path) |

## SLI-4 — sli-event

| Check | Result |
|-------|--------|
| `action.yml` | Inputs align with `emit.sh` env vars |
| `emit.sh` | Pure helpers testable; main tolerant; `SLI_SKIP_OCI_PUSH` for local runs |
| Bug fixed | `sli_expand_oci_config_path`: `~/*` glob bug → `"~/"*` + `${p:1}` |
| Bug fixed | `source` field corrected to `"github-actions/sli-tracker"` |
| Bug fixed | Test subshell counter isolation — two silently swallowed failures exposed and fixed |
| Tests | `tests/test_emit.sh` — **19 passed, 0 failed** (was 16 passing with 2 invisible failures) |

## YOLO decisions

1. No new inputs on sli-event; review-only except for bug fixes.
2. `source` rename is safe (no downstream consumers in this repo).
3. `sli-failure-reason` action is intentionally minimal — companion env-var pattern; `sli-event` docs call this optional.

## Code artifacts

| File | Change |
|------|--------|
| `.github/actions/sli-failure-reason/action.yml` | **Created** |
| `.github/actions/sli-event/emit.sh` | `sli_expand_oci_config_path` bug fix; `source` rename |
| `.github/actions/sli-event/tests/test_emit.sh` | Subshell isolation fix; `source` expected value updated; +3 effective assertions |
