# Sprint 8 — Implementation Notes

## Implementation Overview

**Sprint Status:** implemented (completed 2026-04-06, including reopen: local `emit_curl` signing validation)

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
| `emit_curl.sh` | curl + openssl transport backend (zero install) | Complete |
| `emit.sh` | Thin dispatcher (was monolith) | Modified |
| `action.yml` | Added `emit-backend` input | Modified |

### HTTP signing algorithm (`emit_curl.sh`)

Implementation aligns with **Oracle `oci-python-sdk`** `Signer` / `AbstractBaseSigner` and **`oci.signer._PatchedHeaderSigner`** (same wire format as `oci logging-ingestion put-logs`).

1. **Endpoint**  
   - Host: `ingestion.logging.<region>.oci.<api_domain>` (default `oraclecloud.com` or `api_domain` / `OCI_API_DOMAIN`).  
   - URL path: `POST /20200831/logs/<log-ocid>/actions/push`.

2. **Body**  
   - JSON: `specversion`, `logEntryBatches` (same shape as OCI Logging ingestion API).  
   - **`x-content-sha256`**: Base64-encoded SHA-256 over the **exact UTF-8 bytes** of the body (`printf '%s' "$BATCH" | openssl dgst -binary -sha256 | openssl base64 -A`).  
   - **`content-length`**: **Byte** length of the body (`wc -c` on UTF-8 bytes), not bash `${#BATCH}` (character count breaks signatures when the JSON contains non-ASCII, e.g. Unicode punctuation in workflow names).

3. **Headers included in the signing string (fixed order)**  
   One line each, lowercase header names, separated by `\n` only (no trailing newline on the last line beyond what `printf` produces for the final line):

   ```
   date: <RFC 7231 date, GMT>
   (request-target): post <path>
   host: <host>
   content-length: <byte length as decimal string>
   content-type: application/json
   x-content-sha256: <base64 sha256>
   ```

   This order matches the SDK: generic headers `date`, `(request-target)`, `host`, then body headers `content-length`, `content-type`, `x-content-sha256`.

4. **Signature**  
   - Algorithm: **RSA-SHA256** over the signing string (above).  
   - `printf '%s' "$SIGNING_STRING" | openssl dgst -sha256 -sign "$KEY_FILE" | openssl base64 -A`  
   - **Private key**: PEM at `key_file` from the named profile (session key for token auth, API key PEM for API-key auth).

5. **`keyId` (identity)**  
   - **Session token** (`security_token_file` present and non-empty): `keyId="ST$<token>"` (literal prefix `ST$` + JWT string; same as `SecurityTokenSigner` in the SDK).  
   - **API key** (no session token): `keyId="<tenancy-ocid>/<user-ocid>/<fingerprint>"`.

6. **`Authorization` header (parameter order)**  
   Must match **`_PatchedHeaderSigner.HEADER_SIGNER_TEMPLATE`**:

   ```
   Signature algorithm="rsa-sha256",headers="date (request-target) host content-length content-type x-content-sha256",keyId="...",signature="...",version="1"
   ```

   (Order is `algorithm`, `headers`, `keyId`, `signature`, `version` — not `version` first.)

7. **Profile fields (named profile only; no `[DEFAULT]` merge)**  
   - **Session token:** `key_file`, `region`, readable `security_token_file`.  
   - **API key:** `tenancy`, `user`, `fingerprint`, `key_file`, `region`.

### Design Compliance

- `emit_common.sh`: verbatim copy of all 10 pure helpers — no behavioral change
- `emit_oci.sh`: identical `sli_emit_main` push block to prior `emit.sh`
- `emit_curl.sh`: signing as above; profile reads from the configured profile only
- `emit.sh`: sources `emit_common.sh` (preserves test compatibility); dispatches via `exec` when run directly
- `action.yml`: `emit-backend` defaults to `oci-cli` — backward compatible

### Testing Results (2026-04-06)

- **Unit (UT-1 to UT-7):** 33 assertions passed (`tests/unit/test_emit.sh`)
- **Sprint 8 reopen gate:** `tests/run.sh --unit --new-only progress/sprint_8/sprint_8_reopen.manifest` — PASS  
- **Sprint 8 reopen gate:** `tests/run.sh --integration --new-only progress/sprint_8/sprint_8_reopen.manifest` — PASS (`test_sli_emit_curl_local.sh`: curl push + OCI log query)
- **Full unit regression:** `tests/run.sh --unit` — PASS (3 scripts)

Integration scope for this sprint: **local** `emit_curl` only (`test_sli_emit_curl_local.sh`). Full model pipeline (`test_sli_integration.sh`) and workflow-dispatch tests are out of scope for Sprint 8 reopen; see PLAN / `sprint_8_reopen.md`.

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

The curl backend reads profile fields as described under “Profile fields” above. No OCI CLI installation required for `emit_curl.sh` itself.

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

For a local curl test, read that OCID into `SLI_OCI_LOG_ID`, point `config-file` / `profile` at an OCI profile that satisfies the field rules above, and omit `SLI_SKIP_OCI_PUSH`. The same OCID is also stored in the GitHub repo variable `SLI_OCI_LOG_ID` for workflows (`vars.SLI_OCI_LOG_ID` / `oci.log-id`).

**Sprint 8 integration script:** `bash tests/integration/test_sli_emit_curl_local.sh` (synthetic `GITHUB_*`, real OCI profile, no workflow dispatch).

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

### Sprint conclusion (reopen)

- `emit_curl.sh` request signing validated end-to-end against OCI Logging ingestion (local process + `logging-search`).  
- Documented constraints: UTF-8 body length, `Authorization` field order, `ST$` session `keyId`, SDK header order.  
- OCI config packing for GitHub: session profile section only, verbatim (`setup_oci_github_access.sh`); no `[DEFAULT]` field merge in `emit_curl.sh`.
