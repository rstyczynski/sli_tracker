# install-oci-cli

Installs OCI CLI with all prerequisites on a Linux (Ubuntu/Debian) GitHub-hosted runner. Adds `oci` to `PATH` for subsequent steps.

| File | Role |
| --- | --- |
| `action.yml` | Declares inputs; runs the install script. |
| `install_oci_cli.sh` | Validates OS, installs prerequisites via `apt-get`, installs `oci-cli` via pip (venv by default). |

## Inputs

| Input | Required | Default | Purpose |
| --- | --- | --- | --- |
| `oci-cli-version` | no | latest | Pin a specific OCI CLI version (e.g. `3.40.0`). |
| `use-venv` | no | `true` | Install into a Python virtual environment. Recommended to avoid pip-as-root warnings. |
| `venv-path` | no | `~/.venv/oci-cli` | Virtual environment directory. Only used when `use-venv` is `true`. |
| `verbose` | no | `false` | Show full `apt-get` and `pip` output. |

## Usage

```yaml
- uses: ./.github/actions/install-oci-cli

- uses: ./.github/actions/install-oci-cli
  with:
    oci-cli-version: "3.40.0"   # pin version
    use-venv: "false"            # skip venv, use pip --user
    verbose: "true"              # full install output
```

## Requirements

- Linux (Ubuntu/Debian) — detected automatically; fails fast on Alpine or non-GNU toolchains.
- `sudo` available or script running as root.

## Tests

```bash
bash tests/test_install_oci_cli.sh
```

Requires `podman` with a running machine (`podman machine start`).
