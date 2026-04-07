# Development plan

SLI Tracker is a set of GitHub Actions and shell scripts that track and emit Service Level Indicators (SLI) to OCI Logging from CI/CD pipelines.

Instruction for the operator: keep the development sprint by sprint by changing `Status` label from Planned via Progress to Done. To achieve simplicity each iteration usually contains one feature; a sprint may bundle more than one item when called out explicitly (see Sprint 3). You may add more backlog Items in `BACKLOG.md` file, referencing them in this plan.

Instruction for the implementor: keep analysis, design and implementation as simple as possible to achieve goals presented as Backlog Items. Remove each not required feature sticking to the Backlog Items definitions.

## Sprint 1 - OCI CLI Setup

Status: Done
Mode: managed

Backlog Items:

* SLI-1. OCI CLI installation script for Linux

## Sprint 2 - OCI Access Configuration

Status: Done
Mode: managed

Backlog Items:

* SLI-2. GitHub repository workflow OCI access configuration script/action

## Sprint 3 - Workflow and emit review

Status: Done
Mode: YOLO

This sprint bundles two review-focused backlog items under one milestone. Formal contract-review gates are skipped: ship working increments with minimal ceremony (short inception/analysis notes only if needed; no blocking review milestones).

Backlog Items:

* SLI-3. Review model-* workflows
* SLI-4. Review sli-event action

## Sprint 4 - Improve workflow tests

Status: Done
Mode: YOLO

Backlog Items:

* SLI-5. Improve workflow tests

## Sprint 5 - Test execution artifacts

Status: Done
Mode: YOLO

Backlog Items:

* SLI-8. Test procedure execution log and OCI log capture

## Sprint 6 - Fix *-json field escaping in emit.sh

Status: Done
Mode: YOLO

Backlog Items:

* SLI-9. emit.sh: unescape *-json fields to native JSON in emitted log entries

## Sprint 7 - Test-first quality gates bootstrap

Status: Done
Mode: managed
Test: smoke, unit, integration
Regression: none

First sprint using the patched RUP process (`rup_manager_patched.md`). Bootstraps the centralized test infrastructure, migrates existing tests, and creates initial smoke tests. Uses `Regression: none` because no prior tests exist in `tests/` yet.

Backlog Items:

* SLI-10. Implement test-first quality gates

## Sprint 8 - curl backend for emit.sh

Status: Done
Mode: YOLO
Test: unit, integration
Regression: unit

**Reopened and completed (2026-04-06):** `emit_curl.sh` validated against OCI Logging with **self-crafted request signing** on the **operator machine** (`tests/integration/test_sli_emit_curl_local.sh`). **Out of scope for this sprint:** GitHub workflow dispatch gates (`gh workflow run`, `model-emit-curl.yml`) and the full model pipeline (`test_sli_integration.sh`). Signing algorithm and test results: `progress/sprint_8/sprint_8_implementation.md`. Manifest: `progress/sprint_8/sprint_8_reopen.manifest`.

Backlog Items:

* SLI-11. Split emit.sh into emit_oci.sh and emit_curl.sh (includes curl integration validation)

## Sprint 9 - emit_curl workflow and integration test

Status: Done
Mode: YOLO
Test: integration
Regression: unit

Adds a minimal GitHub Actions workflow that emits SLI events with `emit-backend: curl` without installing OCI CLI, while still using `oci-profile-setup` for the profile. Adds an integration test that dispatches that workflow and verifies OCI Logging.

**Completed (2026-04-06):** Workflow dispatch integration (`tests/integration/test_sli_emit_curl_workflow.sh`) now passes end-to-end and verifies events landed in OCI Logging. Session-token request signing is aligned with `oci-python-sdk` (see `progress/sprint_8/sprint_8_implementation.md` for the signing algorithm).

Backlog Items:

* SLI-12. Dedicated GitHub Actions workflow for `emit_curl.sh` (no OCI CLI install)

## Sprint 10 - nest workflow metadata in emitted events

Status: Done
Mode: YOLO
Test: unit, integration
Regression: unit, integration

Change the SLI event payload schema so all GitHub Actions metadata is emitted under a single `workflow` object (no top-level `workflow_*` fields). This is a breaking schema change that requires updating unit and integration tests, and any OCI Logging queries that reference old field paths.

Integration testing need to revalidate all the use cases for emit_oci, emit_curl, and all the workflows. After this change full set uf use cases must be validated.

Backlog Items:

* SLI-13. Make `workflow` metadata a nested map in emitted events
* SLI-14. Move repository-related attributes into `repo` map
* SLI-15. Update docs/tests/queries for nested `workflow` + `repo` schema

## Sprint 11 - JavaScript action with pre/post hooks

Status: Progress
Mode: YOLO
Test: integration
Regression: none

Replace the current composite action with a JavaScript GitHub Action that supports native `pre` / `post` hooks. The `pre` hook handles optional OCI authentication setup; the `post` hook emits the SLI event via curl. Callers gain automatic teardown without spelling out setup/report steps in every workflow.

Do not modify other files; just create new workflow. Add integration test for this workflow and execute it. Skip regression as no other files are touched.

Backlog Items:

* SLI-16. JavaScript GitHub Action with pre/post hooks for optional auth and SLI reporting
