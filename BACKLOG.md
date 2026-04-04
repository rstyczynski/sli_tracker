# Backlog

version: 1

SLI Tracker is a set of GitHub Actions and shell scripts that track and emit Service Level Indicators (SLI) to OCI Logging from CI/CD pipelines.

This Backlog defines all features to be implemented. Backlog Items selected for implementation are added to iterations detailed in `PLAN.md`.

## Items

### SLI-1. OCI CLI installation script for Linux

Workflow needs access to OCI CLI. The script installs OCI CLI with all
prerequisites (Python 3.6+, pip, OCI CLI package) on a GitHub runner host.

Discover if an existing GitHub Action from Oracle or another provider already covers this. If not, build a new composite action wrapping a standalone shell script (install_oci_cli.sh) so it can also be tested independently.

Test: run the shell script inside a fresh Ubuntu container via podman.
Ubuntu matches the default GitHub-hosted runner image. The script must detect the OS/distro at startup and exit with a clear error
message if the environment is not supported (e.g. non-GNU toolchain).

### SLI-2. GitHub repository workflow OCI access configuration script/action

Workflow needs access to OCI platform. Prepare OCI access configuration script that runs 'oci session authenticate' with home region deducted from current profile - to do it use 'oci iam region-subscription list' with 'is-home-region' true. Generated access details must be packed to be set in GitHub repository secrets. Assume you gave `gh` cli available with proper access in place.

The uploaded profile is consumed by `oci_profile_setup` action that reads the secret to unpack config and associated files to proper places.

Script is supported by a test script that validates correctness of all operations. GitHub action is tested using available regular GitHub test routines.

### SLI-3. Review model-* workflows

Model-* workflows are variations of real-life pipelines used to simulate failures and successes that the SLI monitoring layer will see via the sli-event action. Review them for clarity, naming, and alignment with how events are emitted and interpreted.

### SLI-4. Review sli-event action

The sli-event action emits SLI tracking events to the OCI logging service. Review inputs, emit path, error handling, and tests so the contract is stable for callers.

### SLI-5. Improve workflow tests

Workflow tests introduced in Sprint 3 use hardcoded OCI log OCIDs. Replace every hardcoded OCID in `test_sli_integration.sh` with values read from the `SLI_OCI_LOG_ID` GitHub repo variable so the test script works without modification after an OCI resource recreation.

### SLI-7. Simplify OCI log OCID delivery to emit.sh via job-level env

Currently callers must embed `"log-id": "${{ vars.SLI_OCI_LOG_ID }}"` inside the `context-json` input of every `sli-event` step. This is necessary because `vars` context is not valid inside composite action YAML (bug B1, Sprint 3).

The simpler pattern is to declare `SLI_OCI_LOG_ID` once at the workflow or job `env:` block, where `vars` context is valid. The composite action inherits job-level env vars, so `emit.sh` can read `$SLI_OCI_LOG_ID` directly without it being passed through `context-json`.

Proposed change:

1. In each model-* workflow (or in a shared `env:` at the top), add:
   ```yaml
   env:
     SLI_OCI_LOG_ID: ${{ vars.SLI_OCI_LOG_ID }}
   ```
2. Remove `"log-id"` from every `context-json` block — OCI block shrinks to just `config-file` and `profile`.
3. Update `action.yml` comment to document the preferred delivery path (job env > context-json fallback).
4. Update documentation and the integration test script accordingly.



### SLI-6. Pluggable emit backend for emit.sh

The current emit.sh is tightly coupled to OCI CLI. Add a configurable backend interface so the caller can select the most appropriate transport without changing emit logic.

Proposed backends:

- oci_cli_emit   — current approach; requires install-oci-cli action (~2-3 min install)
- oci_node_emit  — Node.js script using a single OCI npm package; Node 20 pre-installed on ubuntu-latest (~3 MB install)
- oci_curl_emit  — pure bash with curl + openssl request signing; zero install

Backend selected via input (e.g. emit-backend: oci-cli | node | curl) with oci-cli as default to preserve backward compatibility.

Each backend implements the same contract: accepts log-id, profile, config-file, and the JSON payload; exits 0 on success.
