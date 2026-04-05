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

Workflow tests introduced in Sprint 3 use hardcoded OCI log OCIDs with manual not optimal log/log_group creation step. Tenancy is hardcoded. All of this must be changed. Integrate [oci_scaffold](https://github.com/rstyczynski/oci_scaffold) where log_group and log are handled. Use technique to identify both by compartment nad log / log grpup names - use URI style. The same project discovers tenancy id - apply this technique.

Replace every hardcoded OCID in `test_sli_integration.sh` with values read from scripts using the the sci_scaffold.

### SLI-6. Read SLI_OCI_LOG_ID from repo-level variable without workflow YAML changes

The operator sets `SLI_OCI_LOG_ID` once at repository level:

```bash
gh variable set SLI_OCI_LOG_ID --body "<log-ociSLI-5d>"
```

Workflows must not require any YAML edits to consume it. Currently callers must embed `"log-id": "${{ vars.SLI_OCI_LOG_ID }}"` inside every `sli-event` `context-json` block — a workaround for `vars` not being available in composite action YAML.

Proposed change: reference `vars.SLI_OCI_LOG_ID` once at the top-level `env:` of each reusable workflow file. GitHub Actions propagates top-level env to all jobs and composite action steps automatically, so `emit.sh` reads `$SLI_OCI_LOG_ID` from the environment with no per-step wiring.

```yaml
# top of model-reusable-sub.yml (and main.yml)
env:
  SLI_OCI_LOG_ID: ${{ vars.SLI_OCI_LOG_ID }}
```

After this change:

- Operator sets the variable once via `gh variable set` — no workflow YAML to touch.
- `context-json` contains only OCI credentials (`config-file` + `profile`); no `log-id`.
- `action.yml` comment updated to document env var as the primary delivery path.

### SLI-8. Test procedure execution log and OCI log capture

The integration test script `test_sli_integration.sh` currently prints results to stdout but leaves no durable artifact. Two artifacts are required:

1. **Execution log (proof of execution)** — the full stdout/stderr of the test run, timestamped and written to a file (e.g. `progress/sprint_N/test_run_<timestamp>.log`) so that every test execution is traceable without relying on terminal scrollback.

2. **OCI log capture (proof of work)** — after querying OCI Logging in T7, the raw JSON response from OCI must be saved to a file (e.g. `progress/sprint_N/oci_logs_<timestamp>.json`). This captures what OCI actually received and provides evidence independent of the pass/fail assertions.

Both artifacts must be created automatically by the test script on every run. The test script must print the paths of both files at the end of each run so the operator knows where to find them.

### SLI-9. emit.sh: unescape escaped JSON strings to native JSON in emitted log entries

GitHub Actions outputs are always strings. When a caller passes a JSON array or object (e.g. `environments`), the value arrives in `emit.sh` as an escaped string:

```json
"environments": "[\"model-env-1\",\"model-env-2\"]"
```

This is a bug. Any top-level field whose string value starts with `[` or `{` and is valid JSON must be unescaped to a native JSON value before the log entry is pushed to OCI:

```json
"environments": ["model-env-1", "model-env-2"]
```

Fix in `emit.sh`: after assembling the payload, walk all top-level string values; if a value starts with `[` or `{` and parses as valid JSON, replace the string with the parsed value; otherwise leave as-is.

Also rename all `*-json` outputs in workflow files to clean names — the `-json` suffix was a workaround naming convention with no value:

- `environments-json` → `environments` (model-reusable-main.yml)
- `runs-on-json` → `runs-on` (model-reusable-main.yml)
- `plans-json` → `plans` (model-reusable-sub.yml)

This must be covered by new unit tests in `test_emit.sh`.

### SLI-7. Pluggable emit backend for emit.sh

The current emit.sh is tightly coupled to OCI CLI. Add a configurable backend interface so the caller can select the most appropriate transport without changing emit logic.

Proposed backends:

- oci_cli_emit   — current approach; requires install-oci-cli action (~2-3 min install)
- oci_node_emit  — Node.js script using a single OCI npm package; Node 20 pre-installed on ubuntu-latest (~3 MB install)
- oci_curl_emit  — pure bash with curl + openssl request signing; zero install

Backend selected via input (e.g. emit-backend: oci-cli | node | curl) with oci-cli as default to preserve backward compatibility.

Each backend implements the same contract: accepts log-id, profile, config-file, and the JSON payload; exits 0 on success.
