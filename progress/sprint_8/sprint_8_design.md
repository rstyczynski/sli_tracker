# Sprint 8 — Design

## SLI-11: Split emit.sh into emit_oci.sh and emit_curl.sh

Status: Accepted

### Requirement Summary

Rename `emit.sh` OCI CLI logic to `emit_oci.sh`, introduce `emit_curl.sh` (zero-install), extract shared helpers to `emit_common.sh`, make `emit.sh` a dispatcher controlled by `EMIT_BACKEND`.

### File Map

```
.github/actions/sli-event/
  emit_common.sh    NEW  — pure helpers (no transport)
  emit_oci.sh       NEW  — sources emit_common.sh; OCI CLI push
  emit_curl.sh      NEW  — sources emit_common.sh; curl+openssl push
  emit.sh           MOD  — thin dispatcher (was monolith)
  action.yml        MOD  — adds emit-backend input
```

### emit_common.sh

Contains all pure helpers moved verbatim from current `emit.sh`:
- `sli_normalize_json_object`
- `sli_build_base_json`
- `sli_merge_flat_context`
- `sli_extract_oci_json`
- `sli_expand_oci_config_path`
- `sli_failure_reasons_from_steps_json`
- `sli_merge_failure_reasons`
- `sli_failure_reasons_from_env`
- `sli_unescape_json_fields`
- `sli_build_log_entry`

No `sli_emit_main`. Not executable directly (no `if BASH_SOURCE == 0` block).

### emit_oci.sh

```bash
source "$(dirname "${BASH_SOURCE[0]}")/emit_common.sh"

sli_emit_main() {
  # ... identical to current emit.sh sli_emit_main ...
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  sli_emit_main "$@" || echo "::warning::SLI emit script error (non-fatal)"
  exit 0
fi
```

### emit_curl.sh

```bash
source "$(dirname "${BASH_SOURCE[0]}")/emit_common.sh"

# Parse a field from an OCI config file for a given profile.
# Usage: _oci_config_field <file> <profile> <field>
_oci_config_field() { ... awk ... }

# Sign and POST the log entry via curl.
sli_emit_main() {
  # 1. Build BASE, IJ, CTX, FLAT, FAILURE_REASONS, LOG_ENTRY  (same as emit_oci.sh)
  # 2. Extract OCI_LOG_ID, OCI_CONFIG, OCI_PROFILE
  # 3. Parse config: TENANCY, USER_OCID, FINGERPRINT, KEY_FILE
  # 4. Build BATCH JSON (same format as emit_oci.sh)
  # 5. Sign request:
  #    - DATE=$(date -u "+%a, %d %b %Y %H:%M:%S GMT")
  #    - BODY_HASH=$(echo -n "$BATCH" | openssl dgst -binary -sha256 | openssl base64 -A)
  #    - HOST=ingestion.logging.<region>.oci.oraclecloud.com
  #    - REQUEST_TARGET="put /20200831/logs/${OCI_LOG_ID}/actions/push"
  #    - SIGNING_STRING="(request-target): ${REQUEST_TARGET}\ndate: ${DATE}\nhost: ${HOST}\nx-content-sha256: ${BODY_HASH}\ncontent-type: application/json\ncontent-length: ${#BATCH}"
  #    - SIGNATURE=$(printf '%s' "$SIGNING_STRING" | openssl dgst -sha256 -sign "$KEY_FILE" | openssl base64 -A)
  #    - KEY_ID="${TENANCY}/${USER_OCID}/${FINGERPRINT}"
  #    - AUTH="Signature version=\"1\",keyId=\"${KEY_ID}\",algorithm=\"rsa-sha256\",headers=\"(request-target) date host x-content-sha256 content-type content-length\",signature=\"${SIGNATURE}\""
  # 6. curl -s -X PUT "https://${HOST}/20200831/logs/${OCI_LOG_ID}/actions/push" \
  #      -H "Authorization: ${AUTH}" -H "Date: ${DATE}" ...
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  sli_emit_main "$@" || echo "::warning::SLI emit script error (non-fatal)"
  exit 0
fi
```

**Region:** read from OCI config field `region` for the profile. Endpoint pattern: `ingestion.logging.<region>.oci.oraclecloud.com`.

### emit.sh (dispatcher)

```bash
#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/emit_common.sh"

EMIT_BACKEND="${EMIT_BACKEND:-oci-cli}"
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "$EMIT_BACKEND" in
    curl)    exec bash "$SCRIPT_DIR/emit_curl.sh" "$@" ;;
    oci-cli) exec bash "$SCRIPT_DIR/emit_oci.sh"  "$@" ;;
    *)       echo "::error::Unknown EMIT_BACKEND: $EMIT_BACKEND"; exit 1 ;;
  esac
fi
```

When sourced (by tests), `emit_common.sh` helpers are available directly.

### action.yml change

Add input:
```yaml
  emit-backend:
    description: "Transport backend: oci-cli (default) or curl"
    required: false
    default: "oci-cli"
```

Pass to run step:
```yaml
      env:
        EMIT_BACKEND: ${{ inputs.emit-backend }}
```

### Testing Strategy

#### Recommended Sprint Parameters
- Test: unit — all logic is pure bash, no infrastructure needed
- Regression: unit — existing 24 unit tests must still pass

#### Unit Test Targets

**emit_common.sh sourcing:**
- Verify all 10 helpers are available after `source emit_common.sh`

**emit_curl.sh — `_oci_config_field`:**
- Parses correct field from multi-profile config file
- Returns empty for missing field
- Handles profile with spaces around `=`

**emit_curl.sh — signing:**
- Mock `curl` captures Authorization header
- Header matches pattern: `Signature version="1",keyId=".../.../...",algorithm="rsa-sha256",...`
- Payload (body) is valid JSON matching expected batch structure
- `SLI_SKIP_OCI_PUSH` causes skip without calling curl

**emit.sh dispatcher:**
- `EMIT_BACKEND=curl` invokes `emit_curl.sh`
- `EMIT_BACKEND=oci-cli` invokes `emit_oci.sh`
- Unknown backend exits nonzero

#### Smoke Test Candidates
None for this sprint — unit tests are sufficient and fast.

### YOLO Mode Decisions

**Decision 1: Dispatcher via exec vs source**
- Decision: dispatcher calls `exec bash emit_oci.sh` rather than sourcing — clean process separation, no function name collision risk.
- Risk: Low — both backends have `sli_emit_main`; exec avoids double-definition.

**Decision 2: Region from config, not separate input**
- Decision: `emit_curl.sh` reads `region` from the OCI config profile (same file as key_file).
- Risk: Low — consistent with how OCI CLI itself resolves the endpoint.
