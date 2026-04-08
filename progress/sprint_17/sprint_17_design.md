# Sprint 17 — Design

## Goal

Deliver **SLI-25**: extend `setup_oci_github_access.sh` with a third `--account-type`, **`config_profile`**, that:

1. Packs **only** the `[PROFILE]` stanza from `~/.oci/config`, where `PROFILE` comes from `--profile` (default `DEFAULT`).
2. Resolves `key_file` from that stanza, requires it to exist, and **includes the key material** in the tarball (no Vault OCID indirection, no new API key).
3. Skips `oci session authenticate` and any `oci iam region-subscription` lookup needed solely for session bootstrap.
4. Normalizes paths in the packed copy with the existing `${{HOME}}` placeholder rules so `oci_profile_setup.sh` + `OCI_AUTH_MODE=none` work on the runner.

## Behavior

| Aspect | `config_profile` |
|--------|------------------|
| Config section | `[PROFILE]` from `--profile` |
| Session dir | Not included |
| Meta / Vault | Not included |
| `key_file` | Required; file must exist; copied into temp tree |
| Key under `$HOME` | Preserve relative path from `$HOME` (e.g. `.oci/keys/x.pem`) |
| Key outside `$HOME` | Copy to `.oci/keys/<basename>` in temp tree; rewrite `key_file` in packed config only |
| Tarball layout | `tar -C $tmpdir .oci` (entire `.oci` subtree created for this pack) |
| GitHub limit | Existing base64 length check unchanged |

## CLI

- `--account-type config_profile`
- `--profile` selects which stanza to pack (default `DEFAULT`).
- `--session-profile-name` is **ignored** for this account type (document in help).
- `--private-key-secret-ocid` invalid / error if set together with `config_profile` (optional hardening).

## Errors

- Unknown `--account-type` → exit 1.
- Missing or empty `key_file` in the stanza → exit 1.
- `key_file` path missing or not a regular file → exit 1.

### Testing Strategy

- **Unit:** Help documents `config_profile` and constraints; dry-run with isolated `HOME` and minimal `.oci` tree exercises packing without `gh secret set` or session auth.
- **Integration:** Build a tarball matching the restored layout (single-profile config + key under `.oci`), run `oci_profile_setup.sh` with `OCI_AUTH_MODE=none`, assert config and key file exist and placeholders expand.

## Test Specification

| ID | Level | Script | Traceability |
|----|-------|--------|--------------|
| UT-17-1 | unit | `test_setup_oci_github_access_config_profile_help.sh` | Help lists `config_profile` |
| UT-17-2 | unit | `test_setup_oci_github_access_config_profile_dry.sh` | Dry-run pack for isolated `DEFAULT` profile |
| IT-17-1 | integration | `test_config_profile_payload_roundtrip.sh` | Restore + `OCI_AUTH_MODE=none` |

Manifest: `progress/sprint_17/new_tests.manifest`.
