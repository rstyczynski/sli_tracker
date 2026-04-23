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

## Test Specification

Sprint Test Configuration:
- Test: unit, integration
- Mode: YOLO

### Unit Tests

#### UT-1: Substitution with all vars set correctly
- **Input:** tiles file with `__COMPARTMENT_OCID__` `__LOG_GROUP_OCID__` `__LOG_OCID__` `__REGION_ID__` placeholders; state with all four `dashboard_var_*` keys set to non-empty values
- **Expected Output:** output JSON contains substituted values; no `__...__` patterns remain
- **Edge Cases:** keys with underscores in names (e.g. `LOG_GROUP_OCID`)
- **Isolation:** temp state file + temp tiles file; no OCI CLI calls
- **Target file:** tests/unit/test_dashboard.sh

#### UT-2: Empty value causes _fail and exit 1
- **Input:** state with `dashboard_var_LOG_OCID` set to `""`
- **Expected Output:** script exits non-zero; stderr contains `dashboard_var_LOG_OCID is empty or null`
- **Edge Cases:** empty string vs unset key
- **Isolation:** temp state file; script sourced in subshell
- **Target file:** tests/unit/test_dashboard.sh

#### UT-3: Null value causes _fail and exit 1
- **Input:** state with `dashboard_var_REGION_ID` set to JSON `null`
- **Expected Output:** script exits non-zero; stderr contains `dashboard_var_REGION_ID is empty or null`
- **Isolation:** temp state file; script sourced in subshell
- **Target file:** tests/unit/test_dashboard.sh

#### UT-4: Unsubstituted placeholder detected after sed pass
- **Input:** tiles file with `__UNKNOWN_KEY__`; no matching `dashboard_var_UNKNOWN_KEY` in state
- **Expected Output:** script exits non-zero; stderr contains `Unsubstituted placeholders remain` and `__UNKNOWN_KEY__`
- **Isolation:** temp state file + temp tiles file
- **Target file:** tests/unit/test_dashboard.sh

#### UT-5: OCI export format `{"widgets":[...]}` unwrapped to plain array
- **Input:** tiles file in OCI Console export format `{"widgets":[{"id":"w1"}]}`; all dashboard_var_* set
- **Expected Output:** `WIDGETS_JSON` is `[{"id":"w1"}]` (plain array, not wrapped object)
- **Isolation:** temp state file + temp tiles file; capture WIDGETS_JSON via subshell
- **Target file:** tests/unit/test_dashboard.sh

### Integration Tests

#### IT-1: Full deploy — create group + dashboard, verify via OCI CLI, compare against state
- **Preconditions:** OCI CLI configured (profile DEFAULT); `NAME_PREFIX` set; `SLI_OCI_LOG_ID` and `SLI_OCI_LOG_GROUP_ID` available (gh variables or env); `etc/dashboard_sli_tracker.json` present
- **Steps:**
  1. Source `oci_scaffold/do/oci_scaffold.sh` with a test-scoped `NAME_PREFIX` (e.g. `sli-dash-test`)
  2. Set all required state inputs (oci_compartment, dashboard_tiles_file, dashboard_var_*)
  3. Run `tools/ensure_dashboard_group.sh`; capture exit code
  4. Run `tools/ensure_dashboard.sh`; capture exit code
  5. Read `.dashboard_group.ocid` and `.dashboard.ocid` from state file
  6. Call `oci dashboard-service dashboard-group get --dashboard-group-id <ocid>` — verify `display-name` matches `{NAME_PREFIX}-group`
  7. Call `oci dashboard-service dashboard get-dashboard-v1 --dashboard-id <ocid>` — verify `display-name` matches `{NAME_PREFIX}-dashboard` and `widgets` array is non-empty
  8. Run `tools/teardown_dashboard.sh` then `tools/teardown_dashboard_group.sh`
  9. Verify both resources return 404 after deletion
- **Expected Outcome:** Both ensure scripts exit 0; OCIDs in state match OCI API responses; widgets non-empty; teardown exits 0; resources gone
- **Verification:** jq comparison of state-file OCIDs against OCI CLI get responses
- **Target file:** tests/integration/test_dashboard.sh

### Traceability

| Backlog Item | Unit Tests | Integration Tests |
| --- | --- | --- |
| SLI-64 | UT-1, UT-2, UT-3, UT-4, UT-5 | IT-1 |
| SLI-65 | — | — |

---

# Design Summary

## Overall Architecture

Four shell scripts in `tools/` implement SLI-64. Three are direct copies from oci_scaffold; one (`ensure_dashboard.sh`) is a local extension adding `dashboard_var_*` substitution and OCI export format support. MANUAL.md §7.4 implements SLI-65.

## Design Approval Status

Accepted (YOLO auto-approve)
