# Sprint 17 — Setup (contract + analysis)

## Contract

- **Backlog:** SLI-25 — Package an **existing** OCI CLI profile (default `[DEFAULT]`) for GitHub Actions as `OCI_CONFIG_PAYLOAD`, reusing the profile’s current `key_file` on disk.
- **Constraints:** Do **not** create a new API key, do **not** change IAM policies, do **not** require `oci session authenticate` for this mode.
- **Touchpoint:** `.github/actions/oci-profile-setup/setup_oci_github_access.sh` gains an explicit account type (alongside `session` and `api_key`).
- **Consumer:** Existing `oci_profile_setup.sh` with `OCI_AUTH_MODE=none` must restore tarball into `$HOME` so workflows can use the same profile name as packed (e.g. `DEFAULT`).
- **RUP:** YOLO mode — self-approved progression; tests: unit + integration, regression: unit.
- **Acceptance (backlog):** A workflow using the uploaded payload authenticates and can push one log entry and one metric datapoint (validated at integration level by payload shape + restore; live OCI calls remain environment-dependent).

## Analysis

- **Current script behavior:** `session` packs `[SESSION_PROFILE_NAME]` + `.oci/sessions/...`; `api_key` packs that section + Vault OCID metadata, not the PEM on disk.
- **Gap:** Operators with a fully working local API-key profile need a path that copies the **verbatim stanza** for `--profile` (default `DEFAULT`) and **bundles the resolved `key_file`** into the tarball, with `${{HOME}}` normalization consistent with other modes.
- **Feasibility:** Parse `key_file=` from the extracted section, expand `~` and relative paths against `$HOME`, copy the key into the temp tree (preserve path under `$HOME` when the key lives under `$HOME`; otherwise place under `.oci/keys/<basename>` and rewrite `key_file` in the packed copy only).
- **Compatibility:** No change to `oci_profile_setup.sh` required if tarball layout remains `$HOME`-relative after extract (`.oci/config` + key paths under `.oci/...`).
- **Risks:** Large or non-file `key_file` values should fail fast; GitHub secret size limit (64 KiB base64) already enforced.
