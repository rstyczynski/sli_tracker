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
  `no usable key_file for profile [SLI_TEST]` because workflows pass **`profile: SLI_TEST`** while **`setup_oci_github_access.sh --account-type config_profile --profile DEFAULT`** packed only **`[DEFAULT]`**.
- **Root cause**: The packed tarball’s section name must match **`oci-profile-setup` `profile`**. Source operator profile **`[DEFAULT]`** and CI profile **`SLI_TEST`** were not aligned at **pack** time.
- **Fix (supersedes runtime fallback)**: **`setup_oci_github_access.sh`** rewrites the packed stanza from **`--profile` (source)** to **`--session-profile-name` (destination, default `SLI_TEST`)** for **`config_profile`**, so the secret contains **`[SLI_TEST]`** while **`~/.oci/config`** on the laptop still uses **`[DEFAULT]`**. **`oci_profile_setup`** no longer maps SLI_TEST→DEFAULT in **`auto`** mode; workflows keep **`profile: SLI_TEST`** and **`steps.*.outputs.profile`** where needed.
- **Status**: **Fixed** (pack-side rename + workflow wiring on `main`).

### BUG-17-3 — Misleading CI logs: `No DEFAULT profile was specified in the configuration` (oci-common) while using `SLI_TEST`

- **Symptom**: Successful SLI / OCI workflows printed **`No DEFAULT profile was specified in the configuration`** (often twice) to stderr, even though **`profile: SLI_TEST`** and **`--oci-profile SLI_TEST`** were set and the job succeeded.
- **Root cause**: `oci-common` **`ConfigFileReader`** logs `console.info` when **`~/.oci/config` has no `[DEFAULT]` section**, regardless of which profile the SDK constructor uses. Single-profile **`OCI_CONFIG_PAYLOAD`** packs (e.g. only **`[SLI_TEST]`**) therefore always triggered the message.
- **Fix**: After restore in **`oci_profile_setup.sh`**, if **`[DEFAULT]`** is missing, **append a `[DEFAULT]` block** that mirrors the verified profile (`OCI_PROFILE_VERIFY`, e.g. `SLI_TEST`). Integration test **`tests/integration/test_config_profile_payload_roundtrip.sh`** asserts **`[DEFAULT]`** exists after an **`[SLI_TEST]`**-only round-trip.
- **Status**: **Fixed** (commit `05b667e` — `fix(oci-profile-setup): add [DEFAULT] alias to silence oci-common SDK log` on `main`).

**Rationale:** see `progress/sprint_17/sprint_17_notes.md` (SDK profile name vs. parser expecting a `[DEFAULT]` section).
