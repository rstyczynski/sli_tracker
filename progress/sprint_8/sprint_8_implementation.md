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
- Regression (full unit suite): 33/33 passed across 3 test scripts

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
