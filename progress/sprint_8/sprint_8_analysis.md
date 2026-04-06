# Sprint 8 — Analysis

Status: Complete

## Sprint Overview

Split `emit.sh` into a shared helper library (`emit_common.sh`), an OCI CLI backend (`emit_oci.sh`), and a zero-install curl backend (`emit_curl.sh`). `emit.sh` becomes a thin dispatcher. Add `emit-backend` input to `action.yml`.

## Backlog Item Analysis — SLI-11

**Requirement Summary:**
Current `emit.sh` mixes payload assembly (pure bash/jq, testable) with OCI CLI transport (~2 min install). Split so callers can choose `oci-cli` (default) or `curl` (zero install).

**Technical Approach:**

1. `emit_common.sh` — all pure helpers moved from `emit.sh`: `sli_normalize_json_object`, `sli_build_base_json`, `sli_merge_flat_context`, `sli_extract_oci_json`, `sli_expand_oci_config_path`, `sli_failure_reasons_from_steps_json`, `sli_merge_failure_reasons`, `sli_failure_reasons_from_env`, `sli_unescape_json_fields`, `sli_build_log_entry`.

2. `emit_oci.sh` — sources `emit_common.sh`; contains `sli_emit_main` with OCI CLI push block (current behavior). When run directly calls `sli_emit_main`.

3. `emit_curl.sh` — sources `emit_common.sh`; contains `sli_emit_main` using curl + openssl for OCI API-key request signing. Same env var contract. When run directly calls `sli_emit_main`.

4. `emit.sh` — thin dispatcher: sources `emit_common.sh`, reads `EMIT_BACKEND` env var (`oci-cli` | `curl`, default `oci-cli`), delegates to `emit_oci.sh` or `emit_curl.sh`.

5. `action.yml` — adds optional input `emit-backend` (default `oci-cli`); passes as `EMIT_BACKEND` env var to `emit.sh`.

**OCI curl signing:** OCI requires HTTPS request signing per [OCI Request Signing](https://docs.oracle.com/en-us/iaas/Content/API/Concepts/signingrequests.htm). Signed headers: `(request-target) date host x-content-sha256 content-type content-length`. Private key from `key_file` field in OCI config profile. RSA-SHA256 via `openssl dgst -sha256 -sign`. Key ID: `<tenancy_ocid>/<user_ocid>/<key_fingerprint>` from config.

**Dependencies:** `curl`, `openssl` (pre-installed on ubuntu-latest). `jq` already required.

**Testing:** Unit tests for `emit_curl.sh` using a mock `curl` function that captures the signed request and verifies Authorization header structure and payload.

**Compatibility:** `emit.sh` default is `oci-cli` — zero behavioral change for existing callers. `test_emit.sh` sources `emit.sh` (the dispatcher); since `emit_common.sh` is sourced by the dispatcher the helpers remain available in test scope.

**Risks:**
- OCI curl signing is non-trivial; openssl syntax must be exact. Mitigated by unit test with mock curl.
- Config file parsing (tenancy, user, fingerprint, key_file per profile) needs careful awk/grep. Mitigated by unit test with mock config.

## Overall Assessment

**Feasibility:** High — all components are standard bash/curl/openssl.
**Complexity:** Moderate — curl signing is precise but well-documented.
**Prerequisites Met:** Yes.

## Readiness for Design Phase

Confirmed Ready
