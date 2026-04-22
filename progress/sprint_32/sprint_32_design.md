# Sprint 32 - Design

## SLI-64: OCI Console Dashboard for SLI Tracker

Status: Accepted

### Requirement Summary

Deploy an OCI Console dashboard in the project compartment that shows `outcome` event volume and `sli_ratio` trend from the `sli_tracker` OCI Monitoring namespace.

### Feasibility Analysis

**API Availability:**
- `oci dashboard-service dashboard-group list/create/delete` — available in OCI CLI ≥ 3.x
- `oci dashboard-service dashboard list/create/delete/get` — available in OCI CLI ≥ 3.x
- `oci dashboard-service dashboard get --dashboard-id <OCID>` — used to fetch source template

**Technical Constraints:**
- Dashboard must belong to a dashboard group (group is a separate resource)
- Template file stores the `config-details` JSON with `__COMPARTMENT_OCID__` placeholder
- `sed` substitution expands placeholder at deploy time

**Risk Assessment:**
- `--config-details` CLI flag format may require `file://` prefix for large JSON — mitigated by using temp file with `file://` path
- Source dashboard OCID may not be accessible if OCI tenant differs from project tenant — mitigated by placeholder `{}` template; operator populates manually if needed

### Design Overview

**Architecture:**
- `etc/dashboard_sli_tracker.json` — versioned template (placeholder `{}` until first ensure run)
- `tools/ensure_dashboard.sh` — idempotent create (group → dashboard); auto-fetches template on first run
- `tools/teardown_dashboard.sh` — delete dashboard then group

**Data Flow:**
1. `ensure_dashboard.sh` reads compartment OCID and NAME_PREFIX from state
2. If template is `{}`: fetch `config-details` from source OCID via OCI CLI; replace source compartment with placeholder; save to `etc/`
3. Ensure dashboard group (`${NAME_PREFIX}-sli-tracker`)
4. Create temp config with placeholder substituted; create dashboard
5. Write OCIDs to state (`.dashboard.group.ocid`, `.dashboard.ocid`)

### Technical Specification

**APIs Used:**
- `oci dashboard-service dashboard-group list --compartment-id`
- `oci dashboard-service dashboard-group create --compartment-id --display-name`
- `oci dashboard-service dashboard list --dashboard-group-id`
- `oci dashboard-service dashboard create --dashboard-group-id --display-name --config-details file://`
- `oci dashboard-service dashboard get --dashboard-id` (template fetch only)
- `oci dashboard-service dashboard delete --dashboard-id --force`
- `oci dashboard-service dashboard-group delete --dashboard-group-id --force`

**State Keys Written:**
- `.dashboard.group.ocid` / `.dashboard.group.name`
- `.dashboard.ocid` / `.dashboard.name`

**Files:**
- `etc/dashboard_sli_tracker.json` — template (placeholder or fetched config)
- `tools/ensure_dashboard.sh`
- `tools/teardown_dashboard.sh`

### Testing Strategy

**Sprint parameters: Test: none, Regression: none** — no tests required for a tooling/documentation sprint.

**Success Criteria:**
- `ensure_dashboard.sh` runs without error; dashboard visible in OCI Console
- `teardown_dashboard.sh` deletes both resources without error
- MANUAL.md §7.4 accurately describes deployment steps

### YOLO Mode Decisions

### Decision 1: Template placeholder is `{}`
**Context:** Cannot fetch source dashboard without OCI credentials at write time.
**Decision Made:** Commit `{}` as placeholder; script auto-fetches on first run.
**Rationale:** Keeps template under version control; first-run fetch generalizes it.
**Risk:** Low — operator can also populate manually from BACKLOG.md OCID reference.

### Decision 2: `file://` for `--config-details`
**Context:** OCI CLI may reject large inline JSON strings.
**Decision Made:** Write substituted config to a temp file; pass `file://$TEMP_CONFIG`.
**Rationale:** Standard OCI CLI pattern for large JSON payloads.
**Risk:** Low.

---

## SLI-65: MANUAL.md — OCI Console Dashboard section

Status: Accepted

### Requirement Summary

Add §7.4 to `docs/MANUAL.md` documenting dashboard deployment, verification, and teardown.

### Design Overview

- New `### 7.4 OCI Console Dashboard` section after §7.3, before `## 8. Test Suites`
- TOC entry added
- Content: description, prerequisites, deploy command, idempotency note, state keys table, verify step, teardown command

### Testing Strategy

**Test: none** — documentation-only item.

---

# Design Summary

## Overall Architecture

Two new shell scripts + one template file implement SLI-64. MANUAL.md §7.4 implements SLI-65. No changes to existing pipeline, router, or emit components.

## Design Approval Status

Accepted (YOLO auto-approve)
