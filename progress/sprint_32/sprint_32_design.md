# Sprint 32 - Design

## SLI-64: OCI Console Dashboard for SLI Tracker

Status: Accepted

### Requirement Summary

Deploy an OCI Console dashboard in the project compartment that shows `outcome` event volume and `sli_ratio` trend from the `sli_tracker` OCI Monitoring namespace.

### Feasibility Analysis

**API Availability:**
- `oci dashboard-service dashboard-group list-dashboard-groups/create/delete` — available in OCI CLI ≥ 3.x
- `oci dashboard-service dashboard list-dashboards/create-dashboard-v1/update-dashboard-v1/delete/get` — available in OCI CLI ≥ 3.x
- `oci dashboard-service dashboard get --dashboard-id <OCID>` — used to fetch source template

**Technical Constraints:**
- Dashboard must belong to a dashboard group (separate OCI resource)
- oci_scaffold `ensure-dashboard.sh` uses `--widgets` JSON array (plain array, not full config-details object)
- OCI Console dashboard export format is `{"widgets":[...]}` — needs unwrapping before passing to OCI CLI
- Variable substitution must be generic (no hardcoded variable names) to keep scripts project-agnostic for future oci_scaffold promotion
- `ensure-dashboard_group.sh` reads compartment from `.inputs.oci_compartment` — must be set explicitly; does not fall back to `.compartment.ocid`
- Log OCIDs (`LOG_GROUP_OCID`, `LOG_OCID`) are managed separately via GitHub Actions repo variables, not present in the state file

**Risk Assessment:**
- oci_scaffold `ensure-dashboard.sh` supports only 3 hardcoded substitutions (`__COMPARTMENT_OCID__`, `__TENANCY_OCID__`, `__OCI_REGION__`) — does not cover `__LOG_GROUP_OCID__` or `__LOG_OCID__`. Mitigated by local extension script.

### Design Overview

**Architecture:**
- `etc/dashboard_sli_tracker.json` — OCI Console export format (`{"widgets":[...]}`) with 4 `__KEY__` placeholders
- `tools/ensure_dashboard.sh` — local extension of oci_scaffold `ensure-dashboard.sh`; adds `dashboard_var_*` generic substitution and OCI export format unwrapping
- `tools/ensure_dashboard_group.sh` — copied verbatim from `oci_scaffold/resource/ensure-dashboard_group.sh`
- `tools/teardown_dashboard.sh` — copied verbatim from `oci_scaffold/resource/teardown-dashboard.sh`
- `tools/teardown_dashboard_group.sh` — copied verbatim from `oci_scaffold/resource/teardown-dashboard_group.sh`
- All four scripts staged locally for future upstream promotion to oci_scaffold

**Data Flow:**
1. Operator sets state inputs: `dashboard_tiles_file`, `oci_compartment`, `dashboard_var_*` keys
2. `ensure_dashboard_group.sh` reads `.inputs.oci_compartment` and `.inputs.name_prefix`; creates `{name_prefix}-group`
3. `ensure_dashboard.sh` reads `dashboard_tiles_file`, applies `dashboard_var_*` substitutions, unwraps `{"widgets":[...]}` to plain array, creates `{name_prefix}-dashboard`
4. State records `.dashboard_group.ocid`, `.dashboard.ocid`, `.dashboard.deployed`

**Variable Substitution:**
- All `.inputs.dashboard_var_*` state keys are iterated; `__KEY__` → value in the tiles file
- No hardcoded variable names in scripts

### Technical Specification

**APIs Used:**
- `oci dashboard-service dashboard-group list-dashboard-groups --compartment-id`
- `oci dashboard-service dashboard-group create --compartment-id --display-name`
- `oci dashboard-service dashboard list-dashboards --dashboard-group-id`
- `oci dashboard-service dashboard create-dashboard-v1 --dashboard-group-id --display-name --widgets`
- `oci dashboard-service dashboard update-dashboard-v1 --dashboard-id --widgets`
- `oci dashboard-service dashboard delete --dashboard-id --force`
- `oci dashboard-service dashboard-group delete --dashboard-group-id --force`

**State Keys Written:**
- `.dashboard_group.ocid` / `.dashboard_group.name` / `.dashboard_group.created`
- `.dashboard.ocid` / `.dashboard.name` / `.dashboard.created` / `.dashboard.deployed`

**Files:**
- `etc/dashboard_sli_tracker.json` — OCI export format tiles file
- `tools/ensure_dashboard_group.sh`
- `tools/ensure_dashboard.sh`
- `tools/teardown_dashboard.sh`
- `tools/teardown_dashboard_group.sh`

### Testing Strategy

**Sprint parameters: Test: none, Regression: none** — no tests required for a tooling/documentation sprint.

**Success Criteria:**
- `ensure_dashboard_group.sh` + `ensure_dashboard.sh` run without error; dashboard visible in OCI Console in the correct compartment
- All widget placeholders correctly substituted; charts render
- Teardown scripts delete both resources without error
- MANUAL.md §7.4 accurately describes deployment steps

### YOLO Mode Decisions

#### Decision 1: Local copy over direct oci_scaffold call
**Context:** oci_scaffold `ensure-dashboard.sh` lacks `dashboard_var_*` substitution and does not handle OCI Console export format.
**Decision Made:** Copy scripts locally and extend `ensure_dashboard.sh`; promote upstream later.
**Rationale:** Avoids modifying the submodule; keeps the diff reviewable before upstream PR.
**Risk:** Low — oci_scaffold is a submodule pinned by commit; divergence is intentional and documented.

#### Decision 2: Generic `dashboard_var_*` substitution
**Context:** Multiple project-specific OCIDs (`LOG_GROUP_OCID`, `LOG_OCID`, `REGION_ID`) need substitution but must not be hardcoded.
**Decision Made:** Iterate all `.inputs.dashboard_var_*` state keys dynamically; replace `__KEY__` for each.
**Rationale:** Makes `ensure_dashboard.sh` project-agnostic — suitable for upstream oci_scaffold promotion.
**Risk:** Low.

---

## SLI-65: MANUAL.md — OCI Console Dashboard section

Status: Accepted

### Requirement Summary

Add §7.4 to `docs/MANUAL.md` documenting dashboard deployment, verification, and teardown using the four new `tools/` scripts.

### Design Overview

- New `### 7.4 OCI Console Dashboard` section after §7.3, before `## 8. Test Suites`
- TOC entry added
- Content: description, placeholder table, full deploy block (source oci_scaffold + set all inputs + run both ensure scripts), state keys table, verify step, teardown block

### Testing Strategy

**Test: none** — documentation-only item.

---

# Design Summary

## Overall Architecture

Four shell scripts in `tools/` implement SLI-64. Three are direct copies from oci_scaffold; one (`ensure_dashboard.sh`) is a local extension adding `dashboard_var_*` substitution and OCI export format support. MANUAL.md §7.4 implements SLI-65.

## Design Approval Status

Accepted (YOLO auto-approve)
