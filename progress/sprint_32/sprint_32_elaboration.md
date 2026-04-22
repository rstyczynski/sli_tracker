# Sprint 32 - Elaboration

## Design Overview

Two new oci_scaffold-pattern shell scripts (`ensure_dashboard.sh`, `teardown_dashboard.sh`) plus a template placeholder (`etc/dashboard_sli_tracker.json`) implement SLI-64. MANUAL.md §7.4 implements SLI-65.

## Key Design Decisions

- Template stored as `{}` placeholder; auto-fetched from source OCID on first `ensure_dashboard.sh` run
- `file://` temp file used for `--config-details` to handle large JSON
- Dashboard group name: `${NAME_PREFIX}-sli-tracker`; dashboard name: same

## Feasibility Confirmation

All required OCI CLI commands (`dashboard-service dashboard*`, `dashboard-service dashboard-group*`) are available. Pattern follows existing `ensure_fn_resource_principal_os_policy.sh`.

## Artifacts Created

- `progress/sprint_32/sprint_32_design.md`

## Status

Design Accepted — Ready for Construction
