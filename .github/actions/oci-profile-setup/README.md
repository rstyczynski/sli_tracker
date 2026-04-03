# OCI profile setup

Composite action that restores `~/.oci` from a single repository secret produced by `setup_oci_github_access.sh` (shipped with this action) on an operator machine.

## Prerequisites

- Run [`install-oci-cli`](../install-oci-cli/) in the same job **before** this action.
- On your laptop or jump host, prepare an OCI CLI profile in `~/.oci/config` and log in with `oci session authenticate`.
- Create secret `OCI_CONFIG_PAYLOAD` (or your chosen name) using the local setup script; session tokens expire—refresh the secret when workflows start failing to authenticate.

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
          # Must match the --session-profile-name you used when running setup_oci_github_access.sh
          profile: SLI_TEST
          # token_based installs an `oci` wrapper that injects --auth security_token
          oci-auth-mode: token_based
```

## Inputs

| Input | Description | Default |
|-------|-------------|---------|
| `oci_config_payload` | Repository secret value containing the base64 tarball (pass `secrets.OCI_CONFIG_PAYLOAD` or your secret name). | (required) |
| `profile` | Session profile name you used when packing the secret (`--session-profile-name`); verifies `~/.oci/sessions/<profile>` after unpack. | `DEFAULT` |
| `oci-auth-mode` | `token_based` installs an `oci` wrapper into `PATH` that injects `--auth security_token` for subsequent `oci` calls. Use `none` for API-key profiles. | `token_based` |

The action default is `DEFAULT` only for repos that really use a session profile named `DEFAULT`. In most cases you should explicitly set `profile` to the same value you pass as `--session-profile-name` when running `setup_oci_github_access.sh` (for example `SLI_TEST`).

GitHub Actions does not allow reading `secrets[dynamicName]` inside a composite action; workflows must pass the secret value explicitly as shown above.
