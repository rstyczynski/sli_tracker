# Sprint 9 — Design

## SLI-12. Dedicated GitHub Actions workflow for `emit_curl.sh` (no OCI CLI install)

Status: Proposed

### Requirement Summary

New workflow + integration test proving the curl transport works end-to-end on CI without OCI CLI.

### Feasibility Analysis

**Issue**: `oci_profile_setup.sh` calls `exit 1` when `oci-auth-mode: token_based` and OCI CLI is absent. The existing `SLI_TEST` profile is session-based.

**Resolution**: Use `oci-auth-mode: none` to skip the wrapper creation entirely. The script still unpacks `~/.oci` and fixes paths. The `exit 1` only fires inside the `token_based` branch. A value other than `token_based` skips that branch.

**Issue 2**: Session profiles contain `security_token_file`; OCI REST API requires an `x-security-token` header alongside the signed request to authenticate session keys.

**Resolution**: Enhance `emit_curl.sh` to detect `security_token_file` in the profile and add `x-security-token` header. Without this, the signed request is rejected. This is a minimal, backward-compatible change (API-key-only profiles have no `security_token_file`).

### Design Overview

**Two deliverables:**

1. **`.github/workflows/model-emit-curl.yml`** — dedicated `workflow_dispatch` workflow
2. **Enhancement to `emit_curl.sh`** — session token support
3. **`tests/integration/test_sli_emit_curl_workflow.sh`** — integration test

#### 1. Workflow: `model-emit-curl.yml`

```yaml
name: "MODEL — emit_curl (no OCI CLI)"
on:
  workflow_dispatch:
    inputs:
      simulate-failure:
        description: "Force failure (for SLI testing)"
        type: boolean
        default: false

jobs:
  emit-curl:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      # No install-oci-cli step
      - name: "Restore OCI profile"
        uses: ./.github/actions/oci-profile-setup
        with:
          oci_config_payload: ${{ secrets.OCI_CONFIG_PAYLOAD }}
          profile: SLI_TEST
          oci-auth-mode: none
      - name: "Main step"
        id: step-main
        run: |
          if [[ "${{ inputs.simulate-failure }}" == "true" ]]; then
            echo "::error::Simulated failure"; exit 1
          fi
          echo "Main step completed"
      - name: "SLI Report (curl)"
        if: ${{ !cancelled() }}
        continue-on-error: true
        uses: ./.github/actions/sli-event
        with:
          outcome: ${{ job.status }}
          emit-backend: curl
          steps-json: ${{ toJSON(steps) }}
          context-json: |
            {
              "oci": {
                "log-id":      "${{ vars.SLI_OCI_LOG_ID }}",
                "config-file": "~/.oci/config",
                "profile":     "SLI_TEST"
              }
            }
```

Key differences from model workflows:
- **No `install-oci-cli` step**
- `oci-auth-mode: none` (skips wrapper, avoids exit-on-missing-oci)
- `emit-backend: curl`

#### 2. Enhancement: `emit_curl.sh` session token support

In `sli_emit_main()`, after reading profile fields, also read `security_token_file`. If present and file exists, include its contents as the `x-security-token` header in the curl request.

```bash
SECURITY_TOKEN_FILE="$(_oci_config_field "$OCI_CONFIG" "$OCI_PROFILE" security_token_file)"
SECURITY_TOKEN_FILE="$(sli_expand_oci_config_path "$SECURITY_TOKEN_FILE")"
SECURITY_TOKEN=""
if [[ -n "$SECURITY_TOKEN_FILE" && -f "$SECURITY_TOKEN_FILE" ]]; then
  SECURITY_TOKEN="$(cat "$SECURITY_TOKEN_FILE")"
fi
```

Then in the curl call, conditionally add:

```bash
${SECURITY_TOKEN:+-H "x-security-token: ${SECURITY_TOKEN}"}
```

**Backward compatibility**: API-key profiles have no `security_token_file` → variable is empty → no header added → behavior unchanged.

#### 3. Integration test: `test_sli_emit_curl_workflow.sh`

Pattern mirrors `test_sli_integration.sh` T2→T7:

- **T1**: Dispatch `model-emit-curl.yml` (success + failure)
- **T2**: Wait for runs to complete
- **T3**: Check conclusions (success run → success, failure run → failure)
- **T4**: Check job logs for "SLI log entry pushed to OCI Logging"
- **T5**: Query OCI Logging for events with `emit-backend=curl` indicator
- Reuses OCI scaffold + profile from the same test infrastructure

### Testing Strategy

| Level | Scope |
|-------|-------|
| Integration (new) | `tests/integration/test_sli_emit_curl_workflow.sh` — dispatches workflow, verifies logs + OCI events |
| Regression (existing) | `tests/run.sh --unit` — all unit tests including UT-3..UT-7 for emit_curl |

### YOLO Mode Decisions

#### Decision 1: `oci-auth-mode: none`
**Context**: Need to skip the OCI CLI wrapper without modifying `oci_profile_setup.sh`.
**Decision**: Pass `oci-auth-mode: none` — the if-block only triggers on `token_based`.
**Risk**: Low — profile still unpacks correctly; only the wrapper is skipped.

#### Decision 2: Session token support in emit_curl.sh
**Context**: SLI-12 can't work with the existing session profile without the `x-security-token` header.
**Decision**: Add session token support (~10 lines) to emit_curl.sh rather than requiring a separate API-key profile.
**Risk**: Low — backward compatible; transparent to API-key profiles.
