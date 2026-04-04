# Sprint 3 — Implementation

**Sprint status:** implemented + integration-tested

## SLI-3 — model-* workflows

| Check | Result |
|-------|--------|
| Call graph | `model-call` / PR / push → `model-reusable-main` → `model-reusable-sub` |
| SLI coverage | `sli-event` at leaf job level and init level (`sli-init` job) |
| Naming | Consistent `MODEL —` prefix; inline comments document each technique |
| Refactored | Removed `sli-failure-reason` call from `model-reusable-main.yml`; `steps-json` covers failure reasons without a companion action |

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
3. `sli-failure-reason` action removed — `steps-json` already covers all failure reason cases automatically.

## Code artifacts

| File | Change |
|------|--------|
| `.github/actions/sli-failure-reason/action.yml` | **Deleted** (no-value action; `steps-json` covers failure reasons) |
| `.github/workflows/model-reusable-main.yml` | Removed `sli-failure-reason` step; added OCI setup to `sli-init`; fixed `context-json` for init outputs |
| `.github/workflows/model-reusable-sub.yml` | Added checkout + install-oci-cli + oci-profile-setup; `step-auth` now outputs real OCI config path |
| `.github/actions/sli-event/action.yml` | Removed invalid `vars` context reference; fixed description strings with evaluatable `${{ }}` expressions |
| `.github/actions/sli-event/emit.sh` | `sli_expand_oci_config_path` bug fix; `source` rename; added `--specversion 1.0`; added `source`, `type`, `id` to OCI batch |
| `.github/actions/sli-event/tests/test_emit.sh` | Subshell isolation fix; `source` expected value updated; +3 effective assertions |
| `.github/actions/oci-profile-setup/oci_profile_setup.sh` | Removed `GITHUB_ENV PATH=...` assignment (literal `$PATH` not expanded, breaking runtime PATH) |
| `progress/sprint_3/test_sli_integration.sh` | **New**: executable end-to-end integration test script (41 assertions) |
