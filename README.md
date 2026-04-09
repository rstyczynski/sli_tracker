# SLI tracking model

GitHub pipeline execution emits events used to compute Service Level Indicators (SLI). In case of pipeline success event is emitted, and in face of a problem - failure one. Failure message conveys reason to understand if a failure run was because of external or internal service.

Model works on a GitHub repository interacting with OCI tenancy where events are stored.

## Quick start (local `emit.sh`)

1. **Create log group + log with `oci_scaffold` (copy/paste)**  
   This uses the `oci_scaffold/` submodule and writes a state file at the repo root (`./state-<NAME_PREFIX>.json`).

```bash
cd "$(git rev-parse --show-toplevel)"

export NAME_PREFIX="sli_quickstart"
export SLI_OCI_LOG_URI="//sli-events/github-actions"
source ./tools/ensure_oci_resources.sh
ensure_sli_log_resources "$(pwd)" "${SLI_INTEGRATION_OCI_PROFILE:-DEFAULT}" "$NAME_PREFIX" "$SLI_OCI_LOG_URI"

repo=$(gh repo view --json nameWithOwner -q .nameWithOwner)
gh variable set SLI_OCI_COMPARTMENT_ID --body "$COMPARTMENT_OCID" -R "$repo"
gh variable set SLI_OCI_LOG_ID --body "$SLI_LOG_OCID" -R "$repo"
gh variable set SLI_OCI_LOG_GROUP_ID --body "$LOG_GROUP_OCID" -R "$repo"
```

1. **Authenticate** so `~/.oci/config` has a usable profile (e.g. `SLI_TEST`). 

Use the packing script to refresh a session token and upload to GitHub if needed. This profile is a one-time-use, and works 60 minutes.

```bash
.github/actions/oci-profile-setup/setup_oci_github_access.sh --repo "$(gh repo view --json nameWithOwner -q .nameWithOwner)"
```

Alternatively use the packing script to upload a regular profile with an API key. This profile has no session expiry, but the script copies your local private key material into the packed secret (treat the secret accordingly).

```bash
.github/actions/oci-profile-setup/setup_oci_github_access.sh \
  --account-type config_profile \
  --profile DEFAULT \
  --session-profile-name SLI_TEST \
  --repo "$(gh repo view --json nameWithOwner -q .nameWithOwner)"
```

After a **successful** secret upload (not `--dry-run`), the script **writes** **`[SLI_TEST]`** in your `~/.oci/config` as a mirror of **`[DEFAULT]`** (same `key_file` paths), **replacing** any existing **`[SLI_TEST]`** block, so local README commands that use **`profile":"SLI_TEST"`** stay aligned with what you just packed for CI.

For a local-only test you only need a valid session/API-key profile on disk matching `profile` below.

1. **Emit a success SLI event** via the dispatcher (**`emit.sh`**). Set **`EMIT_BACKEND=curl`** for bash + curl + openssl only (no OCI CLI). Use **`EMIT_BACKEND=oci-cli`** if the OCI CLI is installed and you want the same path as the default GitHub Action.

By default `EMIT_TARGET=log,metric` — both an OCI Logging entry and an OCI Monitoring `outcome` metric are pushed. Set `EMIT_TARGET=log` for log only, `EMIT_TARGET=metric` for metric only.

If you run locally (not inside GitHub Actions), the workflow/repo fields are empty. The metric emitter will fall back to a single dimension `emit_env=local` to satisfy OCI Monitoring validation.

```bash
repo=$(gh repo view --json nameWithOwner -q .nameWithOwner)
export SLI_METRIC_COMPARTMENT="$(gh variable get SLI_OCI_COMPARTMENT_ID -R "$repo")"
export SLI_OCI_LOG_ID="$(gh variable get SLI_OCI_LOG_ID -R "$repo")"
export EMIT_BACKEND=curl
export EMIT_TARGET=log,metric
export SLI_OUTCOME=success
export SLI_CONTEXT_JSON='{"oci":{"config-file":"~/.oci/config","profile":"SLI_TEST"}}'
bash .github/actions/sli-event/emit.sh
```

1. **Emit a failure SLI event** (same env as above; set `SLI_OUTCOME=failure`). To populate **`failure_reasons`** like in GitHub Actions, pass a minimal `steps-json` with at least one failed step:

```bash
repo=$(gh repo view --json nameWithOwner -q .nameWithOwner)
export SLI_METRIC_COMPARTMENT="$(gh variable get SLI_OCI_COMPARTMENT_ID -R "$repo")"
export SLI_OCI_LOG_ID="$(gh variable get SLI_OCI_LOG_ID -R "$repo")"
export EMIT_BACKEND=oci-cli
export EMIT_TARGET=log,metric
export SLI_OUTCOME=failure
export STEPS_JSON='{"test_script":{"outcome":"failure","outputs":{}}}'
export SLI_CONTEXT_JSON='{"oci":{"config-file":"~/.oci/config","profile":"SLI_TEST"}}'
bash .github/actions/sli-event/emit.sh
```

To build the payload without pushing, set `SLI_SKIP_OCI_PUSH=1`.

1. ***Load simulator***

Reauthenticate and generate test load over 45 minutes. Run the OCI log group / log creation step (`ensure_oci_resources.sh` above) in this same shell session first so compartment and log OCIDs are available.

```bash
repo=$(gh repo view --json nameWithOwner -q .nameWithOwner)
export SLI_METRIC_COMPARTMENT="$(gh variable get SLI_OCI_COMPARTMENT_ID -R "$repo")"
export SLI_OCI_LOG_ID="$(gh variable get SLI_OCI_LOG_ID -R "$repo")"
export EMIT_BACKEND=curl
export EMIT_TARGET=log,metric
export SLI_METRIC_NAMESPACE="sli_tracker"
export SLI_CONTEXT_JSON='{"oci":{"config-file":"~/.oci/config","profile":"SLI_TEST"}}'

tools/sli_ratio_simulator.sh \
  --target-failure-rate 0.95 \
  --ramp-seconds 900 \
  --hold-seconds 300 \
  --teardown-seconds 900 \
  --interval-seconds 5 \
  --ramp-curve logarithmic \
  --teardown-curve exponential \
  --seed 42
```

1. ***Run SLI calculator***

```bash
export COMPARTMENT_OCID="$(gh variable get SLI_OCI_COMPARTMENT_ID -R "$(gh repo view --json nameWithOwner -q .nameWithOwner)")"
export SLI_OCI_LOG_ID="$(gh variable get SLI_OCI_LOG_ID -R "$(gh repo view --json nameWithOwner -q .nameWithOwner)")"

tools/sli_compute_sli_metrics.js \
  --oci-auth config \
  --window-days 30 \
  --mql-resolution 1d \
  --namespace sli_tracker \
  --metric-name outcome \
  --compartment-id "$COMPARTMENT_OCID" \
  --oci-config-file "~/.oci/config" \
  --oci-profile "SLI_TEST" \
  --output json | jq

# Persist computed snapshot (optional):
tools/sli_compute_sli_metrics.js \
  --oci-auth config \
  --window-days 30 \
  --mql-resolution 5m \
  --namespace sli_tracker \
  --metric-name outcome \
  --compartment-id "$COMPARTMENT_OCID" \
  --oci-config-file "~/.oci/config" \
  --oci-profile "SLI_TEST" \
  --persist log,metric \
  --persist-log-id "$SLI_OCI_LOG_ID" \
  --persist-metric-namespace "sli_tracker" \
  --output json | jq

# For “live-moving” numbers while you are actively emitting datapoints:
tools/sli_compute_sli_metrics.js \
  --oci-auth config \
  --window-days 1 \
  --mql-resolution 5m \
  --namespace sli_tracker \
  --metric-name outcome \
  --compartment-id "$COMPARTMENT_OCID" \
  --oci-config-file "~/.oci/config" \
  --oci-profile "SLI_TEST" \
  --dimension emit_env=local \
  --output json | jq
```

1. **Run GitHub workflow**

Trigger GitHub workflows to simulate synthetic successes and failures. First line prepares session profile to store it in GitHub repository secrets; the second one trigger workflows. Test procedure fetches logs and metrics to validate

Open [Repository Actions](https://github.com/rstyczynski/sli_tracker/actions) to observe execution.

Open OCI Console to observe pushed logs and metrics.

```bash
./tests/integration/test_sli_integration.sh
```

## Process

This repository is developed using the **RUP Strikes Back** AI-driven development process. The process is managed by the `RUPStrikesBack` git submodule located at `./RUPStrikesBack/`.

Key documents:

- `BACKLOG.md` — full list of backlog items (SLI-1, SLI-2, ...)
- `PLAN.md` — sprint plan; each sprint has `Status: Planned | Progress | Done` (or `Failed`)
- `PROGRESS_BOARD.md` — real-time sprint and item status

To start or continue a development cycle, invoke the RUP Manager:

```text
@RUPStrikesBack/.claude/commands/rup-manager.md
```

All rules, templates, and procedures come from `RUPStrikesBack/`. Sprint artifacts are stored under `progress/sprint_<N>/`.

## Recent updates

### Sprint 20 — JavaScript adapter API for router processing (SLI-30, SLI-31, SLI-32) (YOLO)

**Status:** implemented + tested

Adds a lightweight handler-based adapter boundary to `tools/json_router.js` so external JavaScript code can supply envelopes and receive routed outputs or dead-letter cases through injected async callbacks instead of going through filesystem adapters only. The new `processEnvelope(...)` and `processEnvelopes(...)` APIs support fanout and mixed route selections while keeping routing and transformation logic transport-agnostic. Sprint 20 also adds `tools/adapters/file_adapter.js` as a concrete example target adapter that writes routed outputs and dead-letter payloads into deterministic filesystem paths, plus `tools/adapters/file_source_adapter.js` as a concrete example source adapter that reads envelope JSON files in deterministic order.

**Quality gates:** Unit PASS. Current Sprint 20 suite coverage is 12 checks across handler injection plus the example filesystem source and target adapters — see `progress/sprint_20/sprint_20_tests.md`.

**Traceability:** `progress/backlog/SLI-30/`, `progress/backlog/SLI-31/`, `progress/backlog/SLI-32/`

---

### Sprint 19 — Source identification and routing to transformer + destination (SLI-27, SLI-28, SLI-29) (YOLO)

**Status:** implemented + tested

Adds a routing layer (`tools/json_router.js`) in front of the Sprint 18 JSON transformer. The router accepts a normalized envelope containing payload body plus optional transport metadata such as headers and endpoint identity, matches that envelope against a declarative routing definition, resolves exclusive routes by priority, and supports explicit fanout so one message can be delivered to multiple destinations such as OCI Logging and OCI Monitoring in one pass. The routing definition itself is validated by AJV against a checked-in JSON Schema before use, so malformed `routing.json` files fail before any routing or transformation starts. A separate CLI wrapper at `tools/json_router_cli.js` supports single-envelope and batch routing. Route matching supports exact headers, exact endpoint, explicit schema marker fields, and required payload fields, so source identification stays explicit instead of being inferred from transformer internals.

**Quality gates:** Unit PASS. Current router suite coverage is 36 checks across single-envelope routing, batch routing, dedicated `routing.json` schema validation, router CLI behavior, and CLI-to-CLI pipeline behavior, including explicit exclusive/fanout modes and AJV-backed schema validation. No separate regression gate is defined for this sprint — see `progress/sprint_19/sprint_19_tests.md`.

**Traceability:** `progress/backlog/SLI-27/`, `progress/backlog/SLI-28/`, `progress/backlog/SLI-29/`

---

### Sprint 18 — JSON-to-JSON transformation library with JSONata (SLI-26) (YOLO)

**Status:** implemented + tested

Adds a Node.js library (`tools/json_transformer.js`) and CLI (`tools/json_transform_cli.js`) that transform any JSON document to another shape using a JSONata expression loaded from a mapping file (`tools/mappings/`). Swapping the mapping file changes the target schema with no code changes. Example mappings ship for GitHub `workflow_run` webhook → OCI log entry and `/health` response → OCI metric datapoint. The module supports both permissive mappings that omit missing fields naturally and strict mappings that fail fast with JSONata `$assert($exists(...), "...")`. It is designed for reuse in an OCI Fn function (next sprint).

**Quality gates:** Unit (new-code manifest) PASS. Current suite coverage is 56 checks across transformer and CLI paths, including strict required-field validation, soft fallback mappings, and UT-tagged fixture datasets — see `progress/sprint_18/sprint_18_tests.md`. Regression: none (independent new module).

**Traceability:** `progress/backlog/SLI-26/`

---

### Sprint 17 — Upload existing OCI config profile to GitHub (SLI-25) (YOLO)

**Status:** Done

Adds **`--account-type config_profile`** to `setup_oci_github_access.sh` so an operator can pack an existing API-key profile from `~/.oci/config`: **`--profile`** selects the **source** stanza (default **`DEFAULT`**), and **`--session-profile-name`** names the **destination** stanza in the tarball (default **`SLI_TEST`**, matching existing workflows). The key file is included as today; no session flow or IAM changes. The **`oci-profile-setup`** action defaults to **`oci-auth-mode: auto`** (session tarball → token wrapper; API-key / `config_profile` pack → **`none`**). Use **`profile: SLI_TEST`** in workflows when using default pack flags (secret contains **`[SLI_TEST]`**). On restore, if the packed file had no **`[DEFAULT]`** section, setup may append a **`[DEFAULT]`** mirror of the verified profile so the Node **`oci-common`** SDK does not log a misleading “no DEFAULT profile” message (auth still uses the profile you pass, e.g. **`SLI_TEST`**).

**Quality gates:** Unit (new-code manifest) PASS, Integration (new-code manifest) PASS, Regression Unit PASS, Regression Integration PASS — see `progress/sprint_17/sprint_17_tests.md`.

**Traceability:** `progress/backlog/SLI-25/`

---

### Sprint 16 — Dedicated OCI ingestion user for CI (API key + minimal policies) (YOLO)

**Status:** failed (blocked)

Adds support for restoring OCI config payloads that do not contain session-token state, enabling CI usage with API-key profiles while keeping private key material out of GitHub secrets. However, the sprint’s primary goal (ensuring a dedicated OCI IAM ingestion user + minimal policies via `oci_scaffold` ensure/teardown) is blocked in the target environment, so the sprint is marked failed.

**Quality gates:** Unit (new-code manifest) PASS, Integration (new-code manifest) PASS, Regression Unit PASS — see `progress/sprint_16/sprint_16_tests.md`.

**Traceability:** `progress/backlog/SLI-24/`

---

### Sprint 14 — Rolling-window SLI from OCI Monitoring (Node.js) (YOLO)

**Status:** implemented + tested

Adds a Node.js CLI (`tools/sli_compute_sli_metrics.js`) to compute SLI over a configurable rolling window (default 30 days) from OCI Monitoring `outcome` metrics, with dimension filtering and audit-friendly counts. The tool supports fixture mode for tests and live query mode via OCI config file + profile, and can optionally persist computed snapshots to OCI Logging and/or OCI Monitoring.

Auth modes supported by `tools/sli_compute_sli_metrics.js`:

- **Config-file auth**: `--oci-auth config` (default) — works with regular API-key profiles and session-token profiles in `~/.oci/config`.
- **Instance Principal**: `--oci-auth instance_principal` — for running on OCI Compute instances with dynamic group + IAM policy (no config file needed).

Note: if you’re actively emitting datapoints and want the computed numbers to update “live”, use a smaller query resolution, e.g. `--mql-resolution 5m` (instead of the default `1d`).

**Quality gates:** Unit (new-code manifest) PASS, Integration (new-code manifest) PASS, Regression Unit PASS — see `progress/sprint_14/sprint_14_tests.md`.

**Traceability:** `progress/backlog/SLI-20/`

---

### Sprint 13 — Controlled success/failure ratio simulator (YOLO)

**Status:** implemented + tested

Adds `tools/sli_ratio_simulator.sh`, a script that can simulate a controlled failure ratio over time (ramp-up → hold → teardown) using selectable curve shapes (linear, exponential, logarithmic, quadratic). It supports a dry-run mode for deterministic testing without OCI credentials and can invoke the existing `sli-event` `emit.sh` for live emission when configured.

**How to run:** `progress/sprint_13/sprint_13_implementation.md` → “Operator usage (how to run the simulator)”.

**Quality gates:** Unit (new-code manifest) PASS, Integration (new-code manifest) PASS, Regression Unit PASS — see `progress/sprint_13/sprint_13_tests.md`.

**Traceability:** `progress/backlog/SLI-18/`

---

### Sprint 12 — OCI Monitoring metric output via `EMIT_TARGET` (YOLO)

**Status:** implemented_partially + tested

Extends `emit_curl.sh` and `emit_oci.sh` with an `EMIT_TARGET` env var (values: `log`, `metric`, `log,metric`; default `log,metric`). When `metric` is included, an `outcome` datapoint (1=success, 0=other) is posted to OCI Monitoring namespace `sli_tracker` (overridable via `SLI_METRIC_NAMESPACE`) using the same RSA-SHA256 request signing already in place for logging. No workflow YAML files were modified.

New helpers in `emit_common.sh`: `sli_outcome_to_metric_value()` and `sli_emit_metric(log_entry, config, profile)`.

Example — metric-only push:

```bash
EMIT_TARGET=metric \
SLI_OUTCOME=success \
SLI_CONTEXT_JSON='{"oci":{"config-file":"~/.oci/config","profile":"SLI_TEST"}}' \
bash .github/actions/sli-event/emit_curl.sh
```

Example — dual push (log + metric):

```bash
EMIT_TARGET=log,metric \
SLI_OUTCOME=success \
SLI_LOG_ID="<log-ocid>" \
SLI_CONTEXT_JSON='{"oci":{"config-file":"~/.oci/config","profile":"SLI_TEST"}}' \
bash .github/actions/sli-event/emit_curl.sh
```

---

### Sprint 11 — JavaScript `sli-event-js` action + `model-emit-js` workflow (YOLO)

**Status:** implemented + tested

**Backlog:**

- **SLI-16:** Added `.github/actions/sli-event-js/` (Node 20): `main` is a no-op; `post` runs `emit.sh` with `EMIT_BACKEND=curl` so SLI events reach OCI Logging without installing the OCI CLI on the runner. GitHub does not execute `pre` hooks for local actions (`./.github/actions/...`), so optional OCI config restore is modeled as an explicit **`oci-profile-setup`** step at the start of `.github/workflows/model-emit-js.yml` (`oci-auth-mode: none` for curl signing).

**Key changes:**

- `.github/workflows/model-emit-js.yml` — checkout → `oci-profile-setup` → main work → `sli-event-js`
- `tests/integration/test_sli_emit_js_workflow.sh` — dispatches the workflow and asserts GitHub logs + OCI Logging

**Documentation:** `progress/sprint_11/sprint_11_implementation.md`, `progress/sprint_11/sprint_11_tests.md`, `progress/sprint_11/sprint_11_design.md`

**Quality gate:** Integration (new-code manifest) PASS — see `progress/sprint_11/sprint_11_tests.md`.

**Traceability:** `progress/backlog/SLI-16/`

---

### Sprint 10 — Nested `workflow` + `repo` schema in SLI events (YOLO)

**Status:** implemented + tested

**Backlog:**

- **SLI-13:** All GitHub Actions runtime metadata (`run_id`, `run_number`, `run_attempt`, `name`, `ref`, `job`, `event_name`, `actor`) now emitted under a single nested `workflow` object instead of separate top-level fields.
- **SLI-14:** Repository and git-state attributes (`repository`, `repository_id`, `ref`, `ref_full`, `sha`) now emitted under a nested `repo` object.
- **SLI-15:** All unit and integration tests updated for the new field paths. Old `workflow_run_id`, `repository`, `ref`, `job`, etc. no longer appear at the top level.

**Breaking change:** OCI Logging queries referencing old top-level paths (`workflow_run_id`, `repository`, `job`, etc.) must be updated to the new nested paths (`workflow.run_id`, `repo.repository`, `workflow.job`, etc.).

**New event shape (excerpt):**

```json
{
  "source": "github-actions/sli-tracker",
  "outcome": "success",
  "timestamp": "2026-04-06T15:45:03Z",
  "workflow": { "run_id": "...", "name": "...", "job": "...", "actor": "...", "event_name": "..." },
  "repo":     { "repository": "...", "ref": "main", "sha": "..." }
}
```

**Key changes:**

- `.github/actions/sli-event/emit_common.sh` — `sli_build_base_json()` now produces nested `workflow.*` and `repo.*`
- `tests/unit/test_emit.sh` — updated `sli_build_base_json` assertion + 3 new Sprint 10 assertions (47 total)
- `tests/integration/test_sli_integration.sh` — updated 4 jq filters + hardcoded unit count
- `tests/integration/test_sli_emit_curl_local.sh` — updated jq filter to `.workflow.name`
- `tests/integration/test_sli_emit_curl_workflow.sh` — updated jq filter to `.workflow.name`

**Quality gates:** Unit 58/58, Integration 67/67. All passed.

**Artifacts:** `progress/sprint_10/`. Traceability: `progress/backlog/SLI-13/`, `progress/backlog/SLI-14/`, `progress/backlog/SLI-15/`.

---

### Sprint 9 — emit_curl workflow and integration test (YOLO)

**Status:** implemented + tested

**Backlog:**

- **SLI-12:** Added `model-emit-curl.yml` GitHub Actions workflow that emits SLI events via the curl backend (no OCI CLI install). Added `tests/integration/test_sli_emit_curl_workflow.sh` end-to-end integration test that dispatches the workflow and verifies events landed in OCI Logging.

**Key changes:**

- `.github/workflows/model-emit-curl.yml` — curl-backend workflow (no `install-oci-cli`)
- `tests/integration/test_sli_emit_curl_workflow.sh` — workflow dispatch + OCI verification

**Artifacts:** `progress/sprint_9/`. Traceability: `progress/backlog/SLI-12/`.

---

### Sprint 8 — curl backend for emit.sh (YOLO)

**Status:** implemented + tested

**Backlog:**

- **SLI-11:** `emit.sh` split into `emit_oci.sh` (OCI CLI transport), `emit_curl.sh` (pure bash+curl+openssl, zero install), and `emit_common.sh` (shared helpers). `emit.sh` becomes a thin dispatcher via `emit-backend: oci-cli | curl` input.

**Key changes:**

- `.github/actions/sli-event/emit_common.sh` — shared payload helpers
- `.github/actions/sli-event/emit_oci.sh` — OCI CLI transport
- `.github/actions/sli-event/emit_curl.sh` — curl transport with self-crafted HTTP request signing
- `.github/actions/sli-event/emit.sh` — dispatcher
- `tests/integration/test_sli_emit_curl_local.sh` — local emit_curl.sh validation against live OCI

**Artifacts:** `progress/sprint_8/`. Traceability: `progress/backlog/SLI-11/`.

---

### Sprint 7 — Test-first quality gates bootstrap (managed)

**Status:** implemented + tested

**Backlog:**

- **SLI-10:** Bootstrapped the centralized test infrastructure defined in `agent_qualitygate.md`. First sprint using the patched RUP process with Phase 3.1 (Test Specification) and Phase 4.1 (Test Execution).

**Key changes:**

- `tests/run.sh` — centralized test runner with `--smoke`, `--unit`, `--integration`, `--all`, `--new-only <manifest>` flags
- `tests/smoke/test_critical_emit.sh` — smoke test verifying emit.sh core JSON output
- `tests/unit/test_emit.sh` — migrated from `.github/actions/sli-event/tests/`
- `tests/unit/test_install_oci_cli.sh` — migrated from `.github/actions/install-oci-cli/tests/`
- `tests/unit/test_oci_profile_setup.sh` — migrated from `.github/actions/oci-profile-setup/tests/`
- `tests/integration/test_sli_integration.sh` — migrated from `progress/sprint_6/`
- Old test locations replaced with backward-compatible wrapper scripts

**Quality gates:** Smoke 7/7, Unit 35/35, Integration 46/46. All passed.

**Artifacts:** `progress/sprint_7/`. Traceability: `progress/backlog/SLI-10/`.

---

### Sprint 6 — Fix *-json field escaping in emit.sh (YOLO)

**Status:** implemented + tested

**Backlog:**

- **SLI-9:** `emit.sh` now unescapes any top-level field ending in `-json` from an escaped string to native JSON before pushing to OCI Logging. `environments-json` and similar fields now appear as native arrays/objects in OCI log entries instead of escaped strings.

**Key changes:**

- `.github/actions/sli-event/emit.sh` — new `sli_unescape_json_fields` helper; called at end of `sli_build_log_entry`
- `.github/actions/sli-event/tests/test_emit.sh` — 5 new unit tests; total 24/24 passing

**Artifacts:** `progress/sprint_6/`. Traceability: `progress/backlog/SLI-9/`.

---

### Sprint 5 — Test execution artifacts (YOLO)

**Status:** implemented + tested

**Backlog:**

- **SLI-8:** `test_sli_integration.sh` now auto-creates two durable artifacts on every run: a timestamped execution log (`test_run_<ts>.log`) as proof of execution, and a raw OCI Logging JSON capture (`oci_logs_<ts>.json`) as proof of work. Both file paths are printed at the end of each run.

**Key changes:**

- `progress/sprint_5/test_sli_integration.sh` — extended sprint_4 script; exec tee redirect + OCI JSON write
- Sprint 4 script untouched

**Artifacts:** `progress/sprint_5/` (contract, analysis, design, implementation, tests, documentation). Traceability: `progress/backlog/SLI-8/`.

---

### Sprint 4 — Improve workflow tests (YOLO)

**Status:** implemented + tested

**Backlog:**

- **SLI-5:** Replaced hardcoded OCIDs in `test_sli_integration.sh` with URI-style dynamic resolution via `oci_scaffold` techniques. Vendored `lib/oci_scaffold.sh`. New repo variable `SLI_OCI_LOG_URI = log_group_name/log_name`.

**Key changes:**

- `lib/oci_scaffold.sh` — vendored from [oci_scaffold](https://github.com/rstyczynski/oci_scaffold)
- `progress/sprint_3/test_sli_integration.sh` — zero hardcoded OCIDs; tenancy via `oci os ns get-metadata`, log group + log via display-name lookup
- `SLI_OCI_LOG_URI` repo variable added (`sli-events/github-actions`)
- `.gitignore` — excludes `state*.json` (oci_scaffold state files)

**After OCI resource recreation:** update `SLI_OCI_LOG_URI` with new names; all OCIDs resolve automatically.

**Artifacts:** `progress/sprint_4/` (analysis, design, implementation, tests). Traceability: `progress/backlog/SLI-5/`.

---

### Sprint 3 — Workflow and emit review (YOLO)

**Status:** implemented (review-only; no workflow code changes)

**Backlog:**

- **SLI-3:** Reviewed `model-*.yml` — call graph, `MODEL —` naming, `sli-event` usage; see `progress/sprint_3/sprint_3_implementation.md`.
- **SLI-4:** Reviewed `sli-event` (`action.yml`, `emit.sh`); unit tests: `bash .github/actions/sli-event/tests/test_emit.sh`.

**Artifacts:** `progress/sprint_3/` (analysis, design, implementation, tests, documentation). Traceability: `progress/backlog/SLI-3/`, `progress/backlog/SLI-4/`.

---

## Goals

1. track SLI for a GitHub pipeline
2. track SLI for a GitHub pipeline steps

## Environment

GitHub workflows in this repository talk to OCI using a profile restored on the runner. Scheduled and model workflows that install the OCI CLI use **`./.github/actions/oci-profile-setup`**, which unpacks a **single repository secret** — typically **`OCI_CONFIG_PAYLOAD`** — a base64-encoded gzip tarball of a minimal **`~/.oci`** tree (config plus any bundled key or session files). Operators create or refresh that secret with **`setup_oci_github_access.sh`** (session mode, **`api_key`**, or **`config_profile`**). Workflows set **`profile:`** on the action to match the stanza name inside the packed config (commonly **`SLI_TEST`** when using the script’s default **`--session-profile-name`**).

Repository **variables** (not secrets) usually hold **`SLI_OCI_COMPARTMENT_ID`**, **`SLI_OCI_LOG_ID`**, and optionally **`SLI_METRIC_NAMESPACE`**, **`SLI_OCI_LOG_GROUP_ID`**, etc., depending on the workflow.

```text
GitHub
  \- Workflow
        |- GitHub Secrets
        |       \- OCI_CONFIG_PAYLOAD (packed ~/.oci tree; see oci-profile-setup)
        \- GitHub Variables
                |- SLI_OCI_COMPARTMENT_ID, SLI_OCI_LOG_ID, …
                \- (optional) SLI_METRIC_NAMESPACE, SLI_OCI_LOG_URI / LOG_GROUP_ID, …
```
