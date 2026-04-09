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

### SLI-7. Pluggable emit backend for emit.sh

The current emit.sh is tightly coupled to OCI CLI. Add a configurable backend interface so the caller can select the most appropriate transport without changing emit logic.

Proposed backends:

- oci_cli_emit   — current approach; requires install-oci-cli action (~2-3 min install)
- oci_node_emit  — Node.js script using a single OCI npm package; Node 20 pre-installed on ubuntu-latest (~3 MB install)
- oci_curl_emit  — pure bash with curl + openssl request signing; zero install

Backend selected via input (e.g. emit-backend: oci-cli | node | curl) with oci-cli as default to preserve backward compatibility.

Each backend implements the same contract: accepts log-id, profile, config-file, and the JSON payload; exits 0 on success.

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

### SLI-10. Implement test-first quality gates

Implement the test-first quality gate process defined in `agent_qualitygate.md` and orchestrated by `rup_manager_patched.md`. This sprint bootstraps the centralized test infrastructure and migrates existing tests.

**Deliverables:**

1. **Centralized test tree** -- Create `tests/run.sh` runner with working `--smoke`, `--unit`, `--integration`, `--all`, and `--new-only <manifest>` flags. The runner must discover and execute `test_*.sh` scripts in the corresponding subdirectories and return nonzero on any failure.

2. **Test migration** -- Move existing tests to the centralized tree:
   - `.github/actions/sli-event/tests/test_emit.sh` -> `tests/unit/test_emit.sh`
   - `.github/actions/install-oci-cli/tests/test_install_oci_cli.sh` -> `tests/unit/test_install_oci_cli.sh`
   - `.github/actions/oci-profile-setup/tests/test_oci_profile_setup.sh` -> `tests/unit/test_oci_profile_setup.sh`
   - `progress/sprint_6/test_sli_integration.sh` (latest) -> `tests/integration/test_sli_integration.sh`
   - Replace old locations with one-line wrappers delegating to the new paths.

3. **Initial smoke tests** -- Create at least one smoke test in `tests/smoke/` that covers the most critical path (e.g. `test_critical_emit.sh` verifying emit.sh produces valid JSON).

4. **Validation** -- Run `tests/run.sh --all` and confirm all migrated tests pass from the new locations. Run `tests/run.sh --smoke` and confirm smoke tests pass.

Test: smoke, unit, integration
Regression: none (this is the migration sprint -- no prior tests in `tests/` to regress against)

### SLI-11. Split emit.sh into emit_oci.sh and emit_curl.sh

The current `emit.sh` is a single file mixing payload assembly with OCI CLI transport. Rename it to `emit_oci.sh`, extract shared helpers to `emit_common.sh`, and add `emit_curl.sh` as a zero-install backend (pure bash + curl + openssl) so SLI events can be pushed without the ~2-min OCI CLI install step. `emit.sh` becomes a thin dispatcher selecting the backend via an `emit-backend: oci-cli | curl` input (default `oci-cli`).

Test: unit test for `emit_curl.sh` using a mock `curl` that verifies the signed Authorization header and correct payload. Integration (Sprint 8 reopen): `test_sli_emit_curl_local.sh` (local emit, no workflow dispatch); not `test_sli_integration.sh`.

### SLI-12. Dedicated GitHub Actions workflow for `emit_curl.sh` (no OCI CLI install)

Add a **workflow** whose only purpose is to validate the **curl** transport (`emit-backend: curl` → `emit_curl.sh`) end-to-end on GitHub-hosted runners. The workflow **must not** use the `install-oci-cli` action (or otherwise install the OCI CLI); the emit path must rely on bash, `curl`, and `openssl` only.

The workflow **still needs a normal OCI profile**: use `oci-profile-setup` (or the same secret/config pattern as model workflows) so `~/.oci/config` and the configured profile exist for API-key request signing and log push. Document that this path proves the zero-install backend under real CI conditions.

**Integration test:** extend the centralized test tree with a script (e.g. `tests/integration/test_sli_emit_curl_workflow.sh`) that dispatches this workflow (via `gh workflow run`), waits for completion, checks job logs for a successful curl emit, and queries OCI Logging (same style as `test_sli_integration.sh` T6–T7) to confirm events landed. This is distinct from the existing integration test, which runs model workflows and therefore exercises the default **oci-cli** backend only.

### SLI-13. Make workflow metadata a nested map in emitted events

The SLI event payload currently emits GitHub Actions metadata as many top-level fields (e.g. `workflow_run_id`, `workflow_run_number`, `workflow_run_attempt`, `workflow`, `workflow_ref`, etc.). This should be changed so **all workflow/GitHub metadata is grouped under a single nested object**:

- New: `workflow: { run_id, run_number, run_attempt, name, ref, job, event_name, actor, repository, repository_id, ref_name, ref_full, sha }`
- Remove the old top-level `workflow_*` fields and move the remaining GitHub fields into `workflow.*` (breaking schema change).

Test: update unit tests asserting payload shape (`tests/unit/test_emit.sh`) and update integration queries that filter by workflow name/run id (`tests/integration/test_*.sh`) so all gates remain green.

### SLI-14. Move repository-related attributes into `repo` map

The SLI event payload includes repository identity and git-ref state attributes (e.g. `repository`, `repository_id`, `ref`, `ref_full`, `sha`). These should be grouped under a dedicated nested object:

- New: `repo: { repository, repository_id, ref, ref_full, sha }`
- Remove these fields from their prior locations and emit them only under `repo.*` (breaking schema change).

Test: update unit and integration tests to use the new nested paths (`repo.repository`, `repo.ref_full`, etc.).

### SLI-15. Update docs/tests/queries for nested `workflow` + `repo` schema

After SLI-13 and SLI-14 restructure the payload, update all repository documentation and tests that reference the old field paths so regressions remain green:

- Update `tests/unit/test_emit.sh` schema assertions.
- Update integration test jq filters in `tests/integration/test_*.sh`.
- Update design docs describing the payload shape (`progress/sprint_3/sprint_3_design.md`) and any READMEs/examples that show the old schema.

### SLI-16. JavaScript GitHub Action with pre/post hooks for optional auth and SLI reporting

Composite actions cannot use GitHub’s `runs.pre` / `runs.post` hooks; only JavaScript (and Docker) actions can. We need a small JS action so a job can run **optional** OCI setup at the start and **SLI emit at the end** in the real post phase—same product goal as today’s `model-emit-curl.yml` flow, without spelling every setup/report step in each workflow. When the pipeline already provides credentials, the pre hook must do nothing.

Test: a workflow using the new action proves SLI events reach OCI Logging the same way the existing curl workflow integration test does.

### SLI-17. emit.sh: send an OCI Monitoring metric in addition to (or instead of) the OCI Logging entry

`emit.sh` only pushes log entries; SLI ratios (successes/failures over a window) cannot be computed natively in OCI Monitoring without a companion metric. Add a configurable `EMIT_TARGET` (values: `log`, `metric` or combination; default `log,metric`) that posts an `outcome` metric (1=success, 0=failure) to OCI Monitoring with namespace `sli_tracker` (overridable via `SLI_METRIC_NAMESPACE`) and dimensions derived from the workflow/repo fields. Changes are limited to the emit scripts; no workflow YAML files are touched.

Test: integration test runs the emit scripts directly (no workflow dispatch) with `EMIT_TARGET=metric` and `EMIT_TARGET=log,metric` and queries OCI Monitoring to confirm datapoints arrived; regression unit tests cover `EMIT_TARGET` defaulting and outcome→value mapping.

### SLI-18. Controlled success/failure ratio simulator script

We need a script that emits SLI events with a configurable success/failure ratio that changes over time in a controlled way so dashboards and alerts can be validated. It must support ramping from 0 to a target failure rate over a configured duration using a selectable curve (linear, exponential, logarithmic, quadratic), holding the achieved level for a configured duration, then tearing down back to baseline using a selectable curve over a configured duration. This provides deterministic “failure budget burn” scenarios without relying on real pipeline instability. Cycle repeats number of time.

Script uses defined method to emit SLI events: emit.sh. On this stage does not trigger workflows; just emit.sh

Test: running the script with a known configuration produces event outcomes whose observed failure ratio over time matches the configured ramp/hold/teardown behavior within an acceptable tolerance.

### SLI-19. GitHub `workflow_run` webhook ingestion via OCI Functions queue batching

We need an OCI-hosted ingestion path for GitHub `workflow_run` events that accepts public webhooks and reliably emits SLI data to OCI Logging and OCI Monitoring. A public API Gateway endpoint should invoke an ingress Function that validates the GitHub webhook signature and writes a normalized event to a queue/stream, and a separate consumer Function should batch and retry emissions to Logging/Monitoring ingestion APIs. This decouples webhook delivery from OCI ingestion latency and improves resilience during spikes.

Test: posting a signed sample `workflow_run` payload to the public endpoint results in a corresponding log entry and metric datapoint being ingested into OCI.

### SLI-20. Compute rolling-window SLI from OCI Monitoring metrics by dimensions

We need a Node.js tool that queries OCI Monitoring for the emitted `outcome` metric over a configurable rolling time window (default 30 days) and computes SLI as a success ratio, parameterized by selected metric dimensions (for example repository/workflow/job) so operators can compute SLI per slice. The tool must support choosing namespace, compartment, and window length and return the computed ratio plus supporting counts (success/total) for auditability. The computed value must optionally be persisted to OCI Logging and/or OCI Monitoring as configurable outputs so operators can record SLI snapshots for dashboards and audits. This enables fast SLI computation without scanning raw logs.

Test: running the tool against a known test stream returns an SLI value matching the expected ratio and prints the counts and the exact dimension filter used; when persistence is enabled, a corresponding log entry and/or metric datapoint appears in OCI.

### SLI-21. Compute rolling-window SLI from OCI Logging search by dimensions

We need a Node.js tool that queries OCI Logging for SLI event entries over a configurable rolling time window (default 30 days) and computes SLI as a success ratio, parameterized by selected dimensions so operators can compute SLI per slice even when metrics are unavailable. The tool must support choosing log group/log, window length, and time range and return the computed ratio plus supporting counts (success/total) for auditability. The computed value must optionally be persisted to OCI Logging and/or OCI Monitoring as configurable outputs so operators can record SLI snapshots for dashboards and audits. This provides a fallback computation path using the raw event source of truth.

Test: running the tool against a known log stream returns an SLI value matching the expected ratio and prints the counts and the exact dimension filter used; when persistence is enabled, a corresponding log entry and/or metric datapoint appears in OCI.

### SLI-22. Scheduled SLI snapshot every 5 minutes (GitHub Actions)

We need a scheduled GitHub Actions workflow (cron every 5 minutes) that computes the current rolling-window SLI from OCI Monitoring and persists the computed snapshot to both OCI Logging and OCI Monitoring for dashboards/audits. The workflow must reuse the existing auth and resource references already stored at the repo level, so it can run unattended. Reuses `tools/sli_compute_sli_metrics.js` which is repackaged to an action.

Test: after enabling the schedule, within 10 minutes there is at least one new snapshot entry in the configured OCI Log and at least one new `sli_ratio` datapoint in OCI Monitoring.

### SLI-23. Hourly scheduled synthetic SLI emitter (GitHub Actions)

We need a scheduled GitHub Actions workflow (cron hourly) that runs the existing local-style synthetic emitter flow (`tools/sli_ratio_simulator.sh`) to generate test SLI traffic to OCI Logging and Monitoring for dashboards. It must use the token-based `SLI_TEST` OCI profile restored from `secrets.OCI_CONFIG_PAYLOAD` and use repo variables for the OCI log and compartment IDs.

Test: after enabling the schedule, within 2 hours the workflow has run at least once successfully and new `outcome` datapoints and log events are visible in OCI for that run.

### SLI-24. Dedicated OCI ingestion user for CI (API key + minimal policies)

We need a dedicated OCI IAM user intended only for GitHub Actions in this project, authenticated via API key and granted the minimal policies required to ingest into the OCI Logging log and OCI Monitoring metric namespace used by SLI Tracker. This reduces operational risk versus reusing interactive session tokens and makes scheduled workflows stable and auditable. The setup flow must support producing and uploading the correct GitHub secret payload for this account type via `actions/oci-profile-setup/setup_oci_github_access.sh`.

Test: a fresh repository can be configured using the dedicated user and then a workflow run can successfully push one log entry and one metric datapoint using that configuration.

### SLI-25. Upload an existing OCI config profile to GitHub (API key, no IAM changes)

We need a way to upload an existing OCI CLI config profile (default `DEFAULT`) to GitHub as a secret payload for CI use, without creating a new API key and without touching IAM policies. This supports environments where the operator already has a fully privileged OCI user configured locally and only wants to package that profile for workflows. The `actions/oci-profile-setup/setup_oci_github_access.sh` script must support this mode and include any referenced key file material already used by the profile.

Test: using the uploaded payload, a GitHub workflow run can authenticate with the given profile and successfully push one log entry and one metric datapoint.

### SLI-26. JSON-to-JSON transformation library with file-based mapping and CLI

A Node.js library that transforms one JSON document into another by applying a JSONata mapping definition loaded from a file, so source payloads such as `/health`/`/status` API responses or GitHub `workflow_run` webhooks can be converted to target structures such as OCI log or OCI metric without code changes. The mapping definition is a JSON file that describes field projections and expressions; swapping the file changes the target schema. A CLI wrapper lets operators test any transformation interactively against real input.

Test: given a sample `workflow_run` webhook payload and a mapping file targeting the OCI log entry structure, the CLI outputs the correctly shaped OCI document with all mapped fields populated.

### SLI-28. Explicit routing modes for exclusive and fanout delivery

The router needs an explicit way to distinguish between "pick one destination" and "send the same message to multiple destinations" so operators can route one source document to both OCI Logging and OCI Monitoring without relying on accidental ambiguity. Route definitions must declare whether a matching rule is exclusive or fanout, and the router must keep the behavior deterministic when both kinds of rules match the same message. This item is constrained to declarative routing semantics and offline testability; it does not introduce live transport integration.

Test: a single input envelope can be routed by configuration either to one selected destination or to multiple destinations in one pass, with invalid route modes rejected at definition load.

### SLI-29. Validate routing definition JSON with schema before router use

The router should reject malformed `routing.json` documents before any route selection or transformation starts so operator mistakes are caught early and consistently. The routing definition needs a formal JSON Schema validated by the router library, including route structure, match structure, transform mapping reference, destination shape, dead-letter shape, and supported route modes. This validation is a library responsibility and must remain testable offline through fixture-based negative cases.

Test: malformed routing definitions fail during router definition load with clear schema-validation errors, while valid definitions continue to route messages successfully.

### SLI-30. Pluggable JavaScript source and destination adapters for router processing

The router should be usable as a transport-agnostic processing engine instead of only through file and directory adapters. JavaScript code must be able to provide envelopes from in-memory batches, queues, HTTP handlers, or other sources and receive routed outputs and dead-letter cases through injected async handlers, so OCI Logging, OCI Monitoring, queues, and custom delivery code can be attached without changing routing logic. This item keeps the adapter boundary lightweight and library-focused; it does not introduce a framework or live OCI integration.

Test: unit-tested handler-based processing can route successful envelopes to injected JavaScript callbacks and send no-match or transform-failure cases to an injected dead-letter callback without using filesystem reads or writes.

### SLI-31. Example filesystem target adapter for router handler API

The new handler-based adapter API needs at least one concrete example target adapter so its intended usage is visible in code and not only in tests. Provide a small filesystem adapter module that writes routed outputs into destination-specific directories and writes dead-letter payloads into a configured dead-letter directory using deterministic file names. This remains a local example adapter only; it does not introduce OCI-specific delivery logic.

Test: a unit-tested file adapter writes routed outputs and dead-letter payloads to the expected directory structure when used through the handler-based router API.

### SLI-32. Example filesystem source adapter for router handler API

The handler-based router API also needs a concrete source-side example so external JavaScript code can see how envelope ingestion should be structured, not only delivery. Provide a small filesystem source adapter module that reads JSON files from a directory in deterministic order and exposes them as an async iterable suitable for `processEnvelopes(...)`. Malformed JSON in source files must stop processing with a clear critical error because the source adapter is responsible for producing valid envelope objects.

Test: a unit-tested file source adapter reads JSON files in deterministic order, can feed `processEnvelopes(...)`, and fails clearly on malformed source JSON.

### SLI-33. Separate logical destination model from adapter-specific delivery metadata

The router destination contract should remain universal across filesystem, queue, HTTP, OCI, and other adapters. Fields such as `directory` are filesystem-specific and should not live in the generic `destination` object used by routing definitions. Refactor the destination model so routing definitions keep only logical destination identity, such as `type` and `name`, while transport-specific realization details are supplied by adapters through their own configuration or adapter-scoped metadata. This keeps routing definitions transport-agnostic and makes the same route usable across multiple delivery adapters.

Test: unit-tested adapters can resolve the same logical destination to transport-specific targets without relying on filesystem-only fields in the top-level `destination` definition, and existing route selection behavior remains unchanged.
