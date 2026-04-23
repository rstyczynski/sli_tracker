# Sprint 32 - Elaboration

## Design Overview

Four shell scripts in `tools/` implement SLI-64. Three (`ensure_dashboard_group.sh`, `teardown_dashboard.sh`, `teardown_dashboard_group.sh`) are copied verbatim from oci_scaffold with only the `source` path adjusted for the `tools/` location. One (`ensure_dashboard.sh`) is a local extension that adds `dashboard_var_*` generic substitution and OCI Console export format unwrapping. MANUAL.md §7.4 implements SLI-65.

## Key Design Decisions

- `etc/dashboard_sli_tracker.json` stores real widget content in OCI Console export format (`{"widgets":[...]}`); not a placeholder
- Template derived from source dashboard `ocid1.consoledashboard.oc1..aaaaaaaaikoqfpryjfhxp2rulyn3t7kgtq3re3ft33kxp52yqymc3ptzqhya`
- Variable substitution driven entirely by `.inputs.dashboard_var_*` state keys — no hardcoded variable names in script
- `ensure_dashboard_group.sh` requires `.inputs.oci_compartment` explicitly (does not fall back to `.compartment.ocid`)
- Log OCIDs (`LOG_GROUP_OCID`, `LOG_OCID`) are not in the state file; must be read from GitHub Actions repo variables
- Dashboard group name: `{name_prefix}-group`; dashboard name: `{name_prefix}-dashboard` (oci_scaffold Path D fallback)
- OCI CLI: `create-dashboard-v1` / `update-dashboard-v1` (v1 API, not legacy `create`)
- All four scripts staged locally; intended for upstream promotion to oci_scaffold once validated

## Feasibility Confirmation

All required OCI CLI commands confirmed available. oci_scaffold submodule updated to `116e1c4` which includes `ensure-dashboard.sh`, `ensure-dashboard_group.sh`, `teardown-dashboard.sh`, `teardown-dashboard_group.sh`.

## Bugs Discovered and Fixed

### Bug 1: Dashboard group created in tenancy root instead of project compartment

**Root cause:** `ensure_dashboard_group.sh` reads compartment from `.inputs.oci_compartment`, which was not set in state. Without it the script fell through to creating the group in the tenancy root.

**Fix:** MANUAL.md deploy block explicitly sets `.inputs.oci_compartment` from `.compartment.ocid` before running the group script.

### Bug 2: Dashboard widgets deployed with empty placeholder values

**Root cause:** `.inputs.dashboard_var_LOG_GROUP_OCID`, `.inputs.dashboard_var_LOG_OCID`, and `.inputs.dashboard_var_REGION_ID` were set to empty strings because `.log_group.ocid` and `.log.ocid` do not exist in the state file — those resources are managed separately via GitHub Actions repo variables.

**Fix:** MANUAL.md deploy block reads `SLI_OCI_LOG_ID` and `SLI_OCI_LOG_GROUP_ID` from `gh variable get` and derives region from the log OCID (`cut -d. -f4`).

## Artifacts Created

- `progress/sprint_32/sprint_32_design.md`
- `progress/sprint_32/sprint_32_elaboration.md`

## Status

Design Accepted — Construction Complete
