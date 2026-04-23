# Sprint 32 - Setup

## Contract

### Project scope confirmed

SLI Tracker tracks and emits Service Level Indicators from GitHub Actions pipelines to OCI Logging and Monitoring. The router component accepts webhooks, applies JSONata mappings, and forwards to OCI Object Storage, Monitoring, and Logging.

### Sprint objective understood

Sprint 32 delivers an OCI Console dashboard for SLI Tracker metrics (SLI-64) and documents its deployment in MANUAL.md (SLI-65). No code-level changes to pipeline or router components.

### Rules compliance confirmed

- `GENERAL_RULES.md`: Implementor edits only allowed documents; status tokens owned by PO; oci_scaffold submodule is read-only.
- `GIT_RULES.md`: Semantic commit messages; push after every commit.
- `backlog_item_definition.md`: Items state what and why; no design or implementation detail in backlog.
- `sprint_definition.md`: Mode YOLO — self-approve all outputs; no blocking waits; log decisions.
- No hard line wrapping in prose.

### Constraints acknowledged

- `oci_scaffold/` submodule: never edit any file inside it.
- `etc/dashboard_sli_tracker.json`: placeholder `{}` committed; populated on first `ensure_dashboard.sh` run.
- `Test: none` and `Regression: none` — quality gates skipped for this sprint.

### Open questions

None — scope is clear.

## Analysis

### SLI-64: OCI Console Dashboard for SLI Tracker

**Requirement summary:** Deploy an OCI Console dashboard visualizing `outcome` and `sli_ratio` metrics from the `sli_tracker` namespace, scoped to the project compartment. Template stored in `etc/`; deployed via oci_scaffold pattern (`ensure_dashboard.sh` + `teardown_dashboard.sh`).

**Technical approach:** Fetch source dashboard config via `oci dashboard-service dashboard get`, generalize (replace source compartment OCID with `__COMPARTMENT_OCID__` placeholder), save to `etc/dashboard_sli_tracker.json`. Ensure script creates dashboard group then dashboard; idempotent. Teardown script mirrors the delete path.

**Dependencies:** `oci_scaffold.sh` helpers (`_state_get`, `_state_set`, `_require_env`); OCI CLI dashboard-service commands.

**Compatibility:** Follows exact same ensure/teardown pattern as `ensure_fn_resource_principal_os_policy.sh` and `teardown_fn_resource_principal_os_policy.sh`.

### SLI-65: MANUAL.md — OCI Console Dashboard section

**Requirement summary:** Add §7.4 to `docs/MANUAL.md` covering dashboard deployment, verification, and teardown.

**Technical approach:** New section after §7.3 (Monitoring Metric Catalog), before `## 8. Test Suites`. Update TOC. One `ensure` command, one verify step, one `teardown` command.

**Dependencies:** SLI-64 must be implemented first.

### Feasibility: High | Complexity: Simple | Prerequisites: Met
