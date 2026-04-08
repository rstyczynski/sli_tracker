# OCI profile setup

Composite action that restores `~/.oci` from a single repository secret produced by `setup_oci_github_access.sh` (shipped with this action) on an operator machine.

## Prerequisites

- Run [`install-oci-cli`](../install-oci-cli/) in the same job **before** this action.
- On your laptop or jump host, prepare an OCI CLI profile in `~/.oci/config`. Use either **session** login (`oci session authenticate`) or an **API-key** profile (`--account-type config_profile` when packing).
- Create secret `OCI_CONFIG_PAYLOAD` (or your chosen name) using the local setup script. Session tokens expire—refresh the secret when workflows start failing to authenticate.

The action’s **`profile`** input must match the **packed profile name**: the `[SECTION]` you packed (e.g. `SLI_TEST` from `--session-profile-name` / session flow, or `[DEFAULT]` from `--profile DEFAULT` with `config_profile`). Mismatch causes restore or OCI calls to fail.

### Creating the GitHub secret with the bundled setup script

Run this **outside** of GitHub Actions on a machine that has the OCI CLI and GitHub CLI installed:

```bash
# From the repository root
chmod +x .github/actions/oci-profile-setup/setup_oci_github_access.sh

# Show help
.github/actions/oci-profile-setup/setup_oci_github_access.sh --help

# Create or update OCI_CONFIG_PAYLOAD in the current repo.
# Use YOUR actual OCI profile name — the same name as in ~/.oci/config
# (e.g. [MYTENANCY] → --profile MYTENANCY).
# Use --session-profile-name to control the *session* profile name written under ~/.oci/sessions
# (default is SLI_TEST). The action's `profile` input must match this session profile name.
.github/actions/oci-profile-setup/setup_oci_github_access.sh \
  --profile DEFAULT \
  --session-profile-name SLI_TEST \
  --secret-name OCI_CONFIG_PAYLOAD
```

What this does:

- Detects the **home region** via `oci iam region-subscription list`.
- Runs `oci session authenticate` (interactive browser flow).
- Packs `~/.oci/config` and `~/.oci/sessions/<session-profile-name>` into a tarball and base64-encodes it.
- Uploads the payload to the chosen repository as a secret (default `OCI_CONFIG_PAYLOAD`).

## Usage

```yaml
jobs:
  example:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install OCI CLI
        uses: ./.github/actions/install-oci-cli

      - name: Restore OCI profile from secret
        uses: ./.github/actions/oci-profile-setup
        with:
          oci_config_payload: ${{ secrets.OCI_CONFIG_PAYLOAD }}
          # Must match the packed profile (see table below)
          profile: SLI_TEST
          # Optional: default is auto (session dir → token wrapper; else API key on disk → none)
```

### Packing modes vs `profile` in workflows

| How you built the secret | What to set as `profile` |
|--------------------------|---------------------------|
| Session flow: `--session-profile-name SLI_TEST` | `SLI_TEST` |
| `config_profile`: `--profile DEFAULT` (source) + default `--session-profile-name SLI_TEST` | `SLI_TEST` (packed section is `[SLI_TEST]`) |
| `config_profile`: `--profile MYPROF --session-profile-name MYPROF` | `MYPROF` |

## Inputs

| Input | Description | Default |
|-------|-------------|---------|
| `oci_config_payload` | Repository secret value containing the base64 tarball (pass `secrets.OCI_CONFIG_PAYLOAD` or your secret name). | (required) |
| `profile` | Name of the profile section packed in the tarball (`[profile]` in `~/.oci/config` after extract). Used to find the session directory and/or `key_file` line. | `DEFAULT` |
| `oci-auth-mode` | **`auto`**: if `~/.oci/sessions/<profile>` exists → `token_based` (OCI wrapper with `--auth security_token`); else if `key_file` in that profile points to a file on disk → `none`. **`token_based`** / **`none`** skip detection. | `auto` |

In session workflows, set `profile` to the same value as `--session-profile-name` when packing (for example `SLI_TEST`). For **`config_profile`**, `setup_oci_github_access.sh` copies **`--profile` (source, e.g. DEFAULT)** into the tarball as **`--session-profile-name` (destination, default SLI_TEST)**—set **`profile`** in the workflow to that destination name (default **`SLI_TEST`**). After a successful upload (not `--dry-run`), if **`~/.oci/config`** lacks **`[destination]`**, the script appends it as a mirror of the source stanza so local commands can use the same profile name as CI. Use **`steps.<id>.outputs.profile`** in later steps when you need the resolved name.

GitHub Actions does not allow reading `secrets[dynamicName]` inside a composite action; workflows must pass the secret value explicitly as shown above.
