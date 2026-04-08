# Sprint 17 — Implementation

**Sprint status:** **Done** (closed). `PLAN.md` marks Sprint 17 `Status: Done`; `PROGRESS_BOARD.md` uses sprint status `tested` and backlog item SLI-25 `tested`.

## Summary

Extended `.github/actions/oci-profile-setup/setup_oci_github_access.sh` with **`--account-type config_profile`** (SLI-25).

## Behavior

- Validates `ACCOUNT_TYPE` ∈ `{session, api_key, config_profile}`.
- **`config_profile`:** packs the `[PROFILE]` stanza from `--profile` (default `DEFAULT`), copies the resolved `key_file` into the temp tree, normalizes `$HOME/.oci/` to `${{HOME}}/.oci/` like other modes, and builds `tar` over `.oci/` (config + key material). No session directory, no Vault OCID metadata.
- **`config_profile`:** rejects `--private-key-secret-ocid` if set; does not run `oci session authenticate` or home-region lookup.
- **Keys under `$HOME`:** preserve relative path from `$HOME` in the tarball.
- **Keys outside `$HOME`:** copy to `.oci/keys/<basename>` and rewrite `key_file` in the packed config to `${{HOME}}/.oci/keys/<basename>`.

## Tests

- `tests/unit/test_setup_oci_github_access_config_profile_help.sh`
- `tests/unit/test_setup_oci_github_access_config_profile_dry.sh`
- `tests/integration/test_config_profile_payload_roundtrip.sh`

## Files touched

- `.github/actions/oci-profile-setup/setup_oci_github_access.sh`
- `.github/actions/oci-profile-setup/oci_profile_setup.sh` (follow-up: `[DEFAULT]` mirror for oci-common log noise; see `sprint_17_bugs.md` BUG-17-3, `sprint_17_notes.md`)
- `BACKLOG.md` (SLI-25 section aligned with plan)

## Notes

- **`[DEFAULT]` vs `SLI_TEST`:** See `sprint_17_notes.md` — why the restore script may duplicate the active stanza as `[DEFAULT]` even though the Node SDK is given the **`SLI_TEST`** profile name.
