# Sprint 16 — Design

Sprint: 16 | Mode: YOLO | Backlog: SLI-24

## Overview

Introduce a dedicated OCI IAM user intended only for CI ingestion from GitHub Actions, authenticated via API key and governed by minimal policies for pushing to OCI Logging and OCI Monitoring used by this project. Extend the operator bootstrap script (`.github/actions/oci-profile-setup/setup_oci_github_access.sh`) to support packaging a non-session API-key profile payload, and update the profile restore action (`oci-profile-setup`) to accept payloads without `~/.oci/sessions`.

## Scope

- Provisioning:
  - Ensure a dedicated IAM user and a group, attach the user to the group.
  - Generate an API keypair and upload the public key to the OCI user.
  - Ensure a tenancy policy granting the group ingestion rights scoped to the configured compartment.
  - Provide teardown to remove created resources (policy, api key, user-group membership, user, group).
- Bootstrap:
  - Update `setup_oci_github_access.sh` to support an `api_key` account type that produces a tarball payload containing:
    - `.oci/config` with a single profile section
    - an OCI Vault Secret OCID that holds the private key referenced by `key_file` in that profile
    - no `~/.oci/sessions/...` directory requirement
  - Update `oci_profile_setup.sh` so `oci-auth-mode: none` (API key) does not require sessions.
- Client compatibility:
  - Existing emit paths (`emit_curl.sh`, `emit_oci.sh`, Node SDK tools) must continue to work when provided an API-key profile in `~/.oci/config`.

## Inputs / configuration

Operator-time (local machine running setup):

- OCI profile with permissions to manage IAM in the tenancy (for ensure/teardown).
- Target ingestion compartment OCID (policy scope).
- GitHub repo identifier + secret name to upload payload.

Runtime (GitHub Actions):

- Secret payload (base64 tarball) restored by `oci-profile-setup`.
- `oci-auth-mode: none` for API key profiles (no wrapper, no session token).

## Policy intent (minimal)

Grant only what is needed to:

- Push log entries to a specific log (via logging ingestion API).
- Post metric datapoints to Monitoring in the configured compartment/namespace.

(Exact OCI policy verbs/resources will be validated during implementation; keep minimal and compartment-scoped.)

### Testing Strategy

We will validate correctness without requiring live OCI access in tests:

- **Unit**: validate that `oci_profile_setup.sh` can restore API-key payloads without requiring sessions when `OCI_AUTH_MODE=none`, and still requires sessions for `token_based`.
- **Unit**: validate that `setup_oci_github_access.sh --help` documents the new account type and that `--dry-run` works for api_key mode without calling interactive `oci session authenticate`.
- **Integration**: run a non-interactive “pack/unpack round-trip” locally (generate a dummy payload tree with config+key, restore with `oci_profile_setup.sh`, assert files exist and placeholders expand).
  For vault mode, the integration test validates that the Secret OCID metadata is restored and exposed for a downstream step to fetch and write the key file at runtime.

## Test Specification

### UT-1 — `oci_profile_setup.sh` accepts api_key payload without sessions

Traceability: SLI-24

Test: restore payload containing `.oci/config` + Secret OCID metadata, set `OCI_AUTH_MODE=none`, and assert it does not require `~/.oci/sessions/<profile>`.

### UT-2 — `oci_profile_setup.sh` still requires sessions for token_based

Traceability: SLI-24

Test: restore payload without sessions with `OCI_AUTH_MODE=token_based` and assert it fails with a clear error.

### UT-3 — `setup_oci_github_access.sh` supports api_key mode dry-run (non-interactive)

Traceability: SLI-24

Test: run with `--help` and with `--dry-run` + `--account-type api_key` using a prepared config section and key path; assert it does not invoke `oci session authenticate`.

### IT-1 — pack/unpack round-trip for api_key payload

Traceability: SLI-24

Test: create a temporary HOME with a minimal single-profile `.oci/config` + Secret OCID metadata, unpack via `oci_profile_setup.sh`, and assert restored files exist and `${{HOME}}` placeholders expand.

