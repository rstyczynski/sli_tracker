# Sprint 17 — Bugs

Sprint: 17 | Mode: YOLO | Backlog: SLI-25

## Bugs / regressions

### BUG-17-1 — Workflows failed: `token_based` restore expected session dir for `config_profile` secret

- **Symptom**: GitHub Actions failed in `oci_profile_setup.sh` with  
  `Error: Expected session directory missing after extract: /home/runner/.oci/sessions/SLI_TEST`  
  when `OCI_CONFIG_PAYLOAD` was produced with **`--account-type config_profile`** (no `.oci/sessions/` in the tarball).
- **Root cause**: The composite action defaulted **`oci-auth-mode: token_based`**, which always requires `~/.oci/sessions/<profile>` after unpack. Sprint 17 tests covered **`oci_profile_setup.sh`** with explicit **`OCI_AUTH_MODE=none`** but did **not** run the **workflow** path with the action’s previous default, so the mismatch was not caught in CI.
- **Fix**: Default **`oci-auth-mode` to `auto`** in `oci-profile-setup` and resolve after extract: session directory present → `token_based`; else resolvable `key_file` for the profile → `none`. Workflows that hardcoded `token_based` were updated to rely on `auto`. Documented that **`profile`** must match the packed `[SECTION]` (e.g. `DEFAULT` vs `SLI_TEST`).
- **Status**: **Fixed** (commit `fix(oci-profile-setup): default auth mode auto for session vs API-key packs` on `main`).

### BUG-17-2 — `profile: SLI_TEST` + `config_profile` pack with only `[DEFAULT]`

- **Symptom**: After BUG-17-1 fix, restore still failed with  
  `no usable key_file for profile [SLI_TEST]` because workflows pass **`profile: SLI_TEST`** while **`setup_oci_github_access.sh --account-type config_profile --profile DEFAULT`** packs only **`[DEFAULT]`**.
- **Root cause**: Auto mode looked up `key_file` under `[SLI_TEST]`; none exists. Downstream steps also hardcoded **`SLI_TEST`** in `SLI_CONTEXT_JSON` / `--oci-profile`, so even a manual `profile: DEFAULT` fix would have broken emit/metrics unless outputs were wired.
- **Fix**: (1) In **`oci-auth-mode auto`**, if the workflow asks for **`SLI_TEST`** but only **`[DEFAULT]`** has a usable `key_file`, fall back to **`DEFAULT`** and emit a **`::warning`**. (2) Workflows that run OCI after restore now use **`steps.<id>.outputs.profile`** (or **`OCI_PROFILE_RESTORED`**) so the effective profile matches the restored config.
- **Status**: **Fixed** (follow-up commit on `main`).
