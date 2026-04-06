# Sprint 8 — Reopen (integration: curl + self-crafted signing)

**Status:** In progress  
**Date:** 2026-04-06

## Why reopen

Original Sprint 8 delivered the split (`emit_oci.sh` / `emit_curl.sh`) and unit tests. The older integration script `test_sli_integration.sh` drives **model-call / model-push** and the default **oci-cli** emit path — it does **not** prove that **`emit_curl.sh`** calls OCI Logging with **hand-built** signing.

Signing was corrected to match `oci-python-sdk` `Signer` (header order); HTTP 401 was caused by wrong header sequence, not only session-token format.

## Goal (explicit)

**In scope**

- Unit: UT-1 … UT-7 (`tests/unit/test_emit.sh`); full unit regression via `tests/run.sh --unit` as in PLAN.
- Integration **only**: `tests/integration/test_sli_emit_curl_local.sh` — runs `emit_curl.sh` locally with real `~/.oci` and fake `GITHUB_*` env; asserts curl push notice and an OCI log event — **no `gh`, no workflow dispatch**.

**Out of scope for Sprint 8 reopen**

- Any GitHub Actions workflow execution (`model-emit-curl.yml`, `gh workflow run`, etc.). Use `test_sli_emit_curl_workflow.sh` only outside this sprint scope (e.g. SLI-12).
- `test_sli_integration.sh` (full model pipeline). Not a Sprint 8 exit criterion.

**Gate commands**

```bash
bash tests/run.sh --unit --new-only progress/sprint_8/sprint_8_reopen.manifest
bash tests/run.sh --integration --new-only progress/sprint_8/sprint_8_reopen.manifest
```

## References

- Oracle `oci-python-sdk` `src/oci/signer.py` — `Signer.__init__` header lists.
- Emitter under test: `.github/actions/sli-event/emit_curl.sh`.

## Exit criteria

- `bash tests/unit/test_emit.sh` — all passes (or reopen manifest unit gate).
- `bash tests/integration/test_sli_emit_curl_local.sh` — all passes (operator-run with OCI CLI + valid `~/.oci` profile; no GitHub workflow).
