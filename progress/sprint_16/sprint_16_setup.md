# Sprint 16 — Setup

Sprint: 16 | Mode: YOLO | Backlog: SLI-24

## Contract

- I will implement a dedicated OCI IAM user authenticated via **API key** that is used only by this repo’s GitHub Actions for ingestion to OCI Logging and OCI Monitoring.
- I will keep all emitting “client code” compatible with this auth mode (scheduled workflows + emitter scripts + SLI calculator persistence).
- I will implement user and policy provisioning with an **ensure/teardown** lifecycle consistent with `oci_scaffold` (stateful ensure + reversible teardown). Extending `oci_scaffold` via scripts that source its state helpers is allowed.
- I will update `.github/actions/oci-profile-setup/setup_oci_github_access.sh` to support packing and uploading a GitHub secret payload for the API-key profile type (non-interactive, no session token dependency).

Constraints:

- Must not require interactive browser auth for scheduled workflows.
- GitHub secret must not contain the private key material; it must only contain an OCI Vault Secret OCID used to retrieve the key at runtime.
- Secret payload must stay within GitHub secret size limits.
- Policies should be minimal and scoped to the project’s compartment/log/metrics usage.

## Analysis

- Current OCI GitHub secret workflow is **session-token based**: it requires `oci session authenticate` and packs `~/.oci/sessions/<profile>`; this is brittle (token expiry) and not ideal for unattended schedules.
- `oci-profile-setup` currently **requires** a session directory even when auth mode is not token based; it must be relaxed to support API-key-only payloads.
- The repo already centralizes OCI resource ensures via `oci_scaffold` (`tools/ensure_oci_resources.sh`). We can follow the same pattern to ensure:
  - a dedicated IAM user + group
  - an API key attached to that user (private key stored in OCI Vault Secret; GitHub stores only Secret OCID)
  - a tenancy policy granting only ingestion permissions for the target compartment/log/metrics
- Compatibility impact: scheduled workflows can switch to `oci-auth-mode: none` (or `api_key`) and keep using the restored `~/.oci/config`; tools that use the Node SDK already support config-file auth, so they should work unchanged once config/profile exists.
