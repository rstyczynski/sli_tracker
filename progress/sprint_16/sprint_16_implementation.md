# Sprint 16 — Implementation

Sprint: 16 | Mode: YOLO | Backlog: SLI-24

## Summary

Implemented API-key (“non-session”) OCI profile payload support for CI by extending the OCI GitHub access setup script to pack config plus a Vault Secret OCID (private key stored in OCI Vault), and updating the profile restore action so `oci-auth-mode: none` does not require `~/.oci/sessions/<profile>`.

This enables scheduled workflows and tools to run with config-file authentication without relying on expiring session tokens, while keeping private key material out of GitHub secrets.

## Operator usage

- Create/upload GitHub secret payload for API-key mode (stores only private-key Secret OCID in the payload):

```bash
.github/actions/oci-profile-setup/setup_oci_github_access.sh \
  --profile DEFAULT \
  --session-profile-name SLI_TEST \
  --account-type api_key \
  --private-key-secret-ocid "<vault_secret_ocid>" \
  --secret-name OCI_CONFIG_PAYLOAD
```

## Code artifacts

| File | Purpose |
| --- | --- |
| `.github/actions/oci-profile-setup/setup_oci_github_access.sh` | Add `api_key` packing mode + secret OCID metadata |
| `.github/actions/oci-profile-setup/oci_profile_setup.sh` | Allow `oci-auth-mode: none` payloads without sessions |
