# Sprint 8 — Implementation Notes

## Implementation Overview

**Sprint Status:** implemented

**Backlog Items:**
- SLI-11: tested

## SLI-11: Split emit.sh into emit_oci.sh and emit_curl.sh

Status: tested

### Summary

Four files created/modified in `.github/actions/sli-event/`:

| Artifact | Purpose | Status |
| --- | --- | --- |
| `emit_common.sh` | Shared pure helpers (payload assembly) | Complete |
| `emit_oci.sh` | OCI CLI transport backend | Complete |
| `emit_curl.sh` | curl+openssl transport backend (zero install) | Complete |
| `emit.sh` | Thin dispatcher (was monolith) | Modified |
| `action.yml` | Added `emit-backend` input | Modified |

### Design Compliance

- `emit_common.sh`: verbatim copy of all 10 pure helpers — no behavioral change
- `emit_oci.sh`: identical `sli_emit_main` push block to prior `emit.sh`
- `emit_curl.sh`: OCI API-key signing per spec; region read from config profile
- `emit.sh`: sources `emit_common.sh` (preserves test compatibility); dispatches via `exec` when run directly
- `action.yml`: `emit-backend` defaults to `oci-cli` — fully backward compatible

### Testing Results

- Unit (UT-1 to UT-7): 7/7 passed
- Regression (full unit suite): 33/33 passed across 3 test scripts (`tests/run.sh --unit`; PLAN: Regression: unit)
- Integration: all scripts under `tests/integration/` via `tests/run.sh --integration` (PLAN: Test: integration); includes `test_sli_integration.sh` (nested unit gate expects 33 passed in `test_emit.sh`)

### Known Issues

None.

### Usage

**Default (OCI CLI, unchanged):**
```yaml
- uses: ./.github/actions/sli-event
  with:
    outcome: ${{ job.status }}
    context-json: '{"oci": {"config-file": "~/.oci/config", "profile": "SLI_TEST"}}'
```

**Zero-install curl backend:**
```yaml
- uses: ./.github/actions/sli-event
  with:
    outcome: ${{ job.status }}
    emit-backend: curl
    context-json: '{"oci": {"config-file": "~/.oci/config", "profile": "SLI_TEST"}}'
```

The curl backend reads `tenancy`, `user`, `fingerprint`, `key_file`, and `region` from the OCI config profile. No OCI CLI installation required.

### Local snippets: `emit_curl.sh`

Run these from the **repository root** (the directory that contains `.github/`). Requires `bash`, `jq`, `curl`, and `openssl` on `PATH`.

**1. Dry run — build payload and skip OCI push (safe anywhere)**

No valid OCI config or log OCID required; prints the SLI payload and exits after the skip notice.

```bash
cd "$(git rev-parse --show-toplevel)"
export SLI_OUTCOME=success
export SLI_SKIP_OCI_PUSH=1
bash .github/actions/sli-event/emit_curl.sh
```

**2. Same path via the dispatcher (`emit.sh` → `emit_curl.sh`)**

```bash
cd "$(git rev-parse --show-toplevel)"
export SLI_OUTCOME=success
export SLI_SKIP_OCI_PUSH=1
export EMIT_BACKEND=curl
bash .github/actions/sli-event/emit.sh
```

**3. Real push — curl signing + `POST` to Logging (same contract as `oci logging-ingestion put-logs`)**

The custom log used by this project is provisioned with [oci_scaffold](https://github.com/rstyczynski/oci_scaffold) (submodule at `oci_scaffold/`). After `ensure-log.sh` (or a full `tests/integration/test_sli_integration.sh` run), oci_scaffold writes **`./state-${NAME_PREFIX}.json`** in the **current working directory** (see `oci_scaffold/do/oci_scaffold.sh`). The log OCID is at **`.log.ocid`**. Integration tests use `NAME_PREFIX=sli_test_sprint6`, so the file is `state-sli_test_sprint6.json` at the repo root — adjust the filename if your prefix differs.

For a local curl test, read that OCID into `SLI_OCI_LOG_ID`, point `config-file` / `profile` at an OCI profile that defines `tenancy`, `user`, `fingerprint`, `key_file`, and `region`, and omit `SLI_SKIP_OCI_PUSH`. The same OCID is also stored in the GitHub repo variable `SLI_OCI_LOG_ID` for workflows (`vars.SLI_OCI_LOG_ID` / `oci.log-id`).

```bash
cd "$(git rev-parse --show-toplevel)"
STATE_FILE="${PWD}/state-sli_test_sprint6.json"
export SLI_OCI_LOG_ID="$(jq -r '.log.ocid // empty' "$STATE_FILE")"
export SLI_OUTCOME=success
unset SLI_SKIP_OCI_PUSH
export SLI_CONTEXT_JSON="$(jq -nc \
  --arg cf "${HOME}/.oci/config" \
  --arg prof "DEFAULT" \
  '{oci: {"config-file": $cf, profile: $prof}}')"
bash .github/actions/sli-event/emit_curl.sh
```

Equivalent: put the OCID in context JSON instead of the env var — `emit_curl.sh` accepts either (`SLI_OCI_LOG_ID` or `oci.log-id` in `SLI_CONTEXT_JSON`).

Optional: set `GITHUB_REPOSITORY`, `GITHUB_REF_NAME`, `GITHUB_SHA`, etc., before running to populate those fields in the payload when testing outside GitHub Actions.
