# SLI tracking model

GitHub pipeline execution emits events used to compute Service Level Indicators (SLI). In case of pipeline success event is emitted, and in face of a problem - failure one. Failure message conveys reason to understand if a failure run was because of external or internal service.

Model works on a GitHub repository interacting with OCI tenancy where events are stored.

## Quick start (local `emit.sh`)

1. **Create log group + log with `oci_scaffold` (copy/paste)**  
   This uses the `oci_scaffold/` submodule and writes a state file at the repo root (`./state-<NAME_PREFIX>.json`).

```bash
cd "$(git rev-parse --show-toplevel)"

# Pick a unique prefix (state file becomes ./state-${NAME_PREFIX}.json)
export NAME_PREFIX="sli_quickstart"

# OCI log destination (URI-style: //log-group/log-name)
export SLI_OCI_LOG_URI="//sli-events/github-actions"

# Ensure the OCI log resources exist (uses oci_scaffold under the hood)
# OCI profile defaults to SLI_TEST; override if you use a different local profile name.
source ./tools/ensure_oci_resources.sh
ensure_sli_log_resources "$(pwd)" "${SLI_INTEGRATION_OCI_PROFILE:-SLI_TEST}" "$NAME_PREFIX" "$SLI_OCI_LOG_URI"

export SLI_OCI_LOG_ID="$SLI_LOG_OCID"
echo "COMPARTMENT_OCID=$COMPARTMENT_OCID"
echo "SLI_OCI_LOG_ID=$SLI_OCI_LOG_ID"
```

1. **Authenticate** so `~/.oci/config` has a usable profile (e.g. `SLI_TEST`). Use the packing script to refresh a session token and upload to GitHub if needed:

   ```bash
   bash .github/actions/oci-profile-setup/setup_oci_github_access.sh --repo "$(gh repo view --json nameWithOwner -q .nameWithOwner)"
   ```

   For a local-only test you only need a valid session/API-key profile on disk matching `profile` below.

1. **Emit a success SLI event** via the dispatcher (**`emit.sh`**). Set **`EMIT_BACKEND=curl`** for bash + curl + openssl only (no OCI CLI). Use **`EMIT_BACKEND=oci-cli`** if the OCI CLI is installed and you want the same path as the default GitHub Action.

   By default `EMIT_TARGET=log,metric` — both an OCI Logging entry and an OCI Monitoring `outcome` metric are pushed. Set `EMIT_TARGET=log` for log only, `EMIT_TARGET=metric` for metric only.

   If you run locally (not inside GitHub Actions), the workflow/repo fields are empty. The metric emitter will fall back to a single dimension `emit_env=local` to satisfy OCI Monitoring validation.

   ```bash
   export EMIT_BACKEND=curl
   export EMIT_TARGET=log,metric
   export SLI_OUTCOME=success
   export SLI_METRIC_COMPARTMENT=$COMPARTMENT_OCID
   export SLI_OCI_LOG_ID=$SLI_OCI_LOG_ID
   export SLI_CONTEXT_JSON='{"oci":{"config-file":"~/.oci/config","profile":"SLI_TEST"}}'
   bash .github/actions/sli-event/emit.sh
   ```

1. **Emit a failure SLI event** (same env as above; set `SLI_OUTCOME=failure`). To populate **`failure_reasons`** like in GitHub Actions, pass a minimal `steps-json` with at least one failed step:

   ```bash
   export EMIT_BACKEND=oci-cli
   export EMIT_TARGET=log,metric
   export SLI_OUTCOME=failure
   export SLI_METRIC_COMPARTMENT=$COMPARTMENT_OCID
   export SLI_OCI_LOG_ID=$SLI_OCI_LOG_ID
   export STEPS_JSON='{"test_script":{"outcome":"failure","outputs":{}}}'
   export SLI_CONTEXT_JSON='{"oci":{"config-file":"~/.oci/config","profile":"SLI_TEST"}}'
   bash .github/actions/sli-event/emit.sh
   ```

   `SLI_OCI_LOG_ID` is read from the environment; `oci.log-id` in `SLI_CONTEXT_JSON` is optional if it is set. To build the payload without pushing, set `SLI_SKIP_OCI_PUSH=1`.

1. ***Load simulator***

Reauthenticate and generate test load over 45 minutes. Note that OCI code to create loggoup/log mut be executed in this terminal session.

```bash
bash .github/actions/oci-profile-setup/setup_oci_github_access.sh --repo "$(gh repo view --json nameWithOwner -q .nameWithOwner)"

export EMIT_BACKEND=curl
export EMIT_TARGET=log,metric
export SLI_METRIC_NAMESPACE="sli_tracker"
export SLI_METRIC_COMPARTMENT=$COMPARTMENT_OCID
export SLI_OCI_LOG_ID=$SLI_OCI_LOG_ID
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

1. ***Run GitHub workflow**

```bash
./.github/actions/oci-profile-setup/setup_oci_github_access.sh
./tests/integration/test_sli_integration.sh
```

## Process

This repository is developed using the **RUP Strikes Back** AI-driven development process. The process is managed by the `RUPStrikesBack` git submodule located at `./RUPStrikesBack/`.

Key documents:

- `BACKLOG.md` — full list of backlog items (SLI-1, SLI-2, ...)
- `PLAN.md` — sprint plan; active sprint has `Status: Progress`
- `PROGRESS_BOARD.md` — real-time sprint and item status

To start or continue a development cycle, invoke the RUP Manager:

```text
@RUPStrikesBack/.claude/commands/rup-manager.md
```

All rules, templates, and procedures come from `RUPStrikesBack/`. Sprint artifacts are stored under `progress/sprint_<N>/`.

## Recent updates

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
SLI_OCI_LOG_ID="<log-ocid>" \
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

GitHub workflow lives in GitHub repository holding this code. Interaction with OCI requires OCI CLI (with prerequisite i.e. python) and OCI access profile to be available. Moreover destination OCI log should be specified. Workflow configuration arguments are specified in repository secrets and variables.

```text
GitHub
  \- Workflow
        |- GitHub Secrets
        |       |- OCI Config file
        |       \- Private key
        \- GitHub Variables
                |- OCI config profile name
                \- OCI Logging
```
