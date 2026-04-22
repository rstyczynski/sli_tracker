# Sprint 32 - Implementation

## SLI-64: OCI Console Dashboard for SLI Tracker

Status: Implemented

### Code Artifacts

| File | Purpose |
| --- | --- |
| `etc/dashboard_sli_tracker.json` | OCI Console export format tiles file (`{"widgets":[...]}`) with 4 `__KEY__` placeholders |
| `tools/ensure_dashboard_group.sh` | Copied from `oci_scaffold/resource/ensure-dashboard_group.sh`; source path adjusted |
| `tools/ensure_dashboard.sh` | Local extension of oci_scaffold version; adds `dashboard_var_*` substitution + OCI export format unwrap |
| `tools/teardown_dashboard.sh` | Copied from `oci_scaffold/resource/teardown-dashboard.sh`; source path adjusted |
| `tools/teardown_dashboard_group.sh` | Copied from `oci_scaffold/resource/teardown-dashboard_group.sh`; source path adjusted |

### Template

Template derived from:

```bash
oci dashboard-service dashboard get \
  --dashboard-id ocid1.consoledashboard.oc1..aaaaaaaaikoqfpryjfhxp2rulyn3t7kgtq3re3ft33kxp52yqymc3ptzqhya
```

Source-specific OCIDs replaced with `__KEY__` placeholders, driven by `.inputs.dashboard_var_*` state keys:

| Placeholder | State key |
| --- | --- |
| `__COMPARTMENT_OCID__` | `.inputs.dashboard_var_COMPARTMENT_OCID` |
| `__LOG_GROUP_OCID__` | `.inputs.dashboard_var_LOG_GROUP_OCID` |
| `__LOG_OCID__` | `.inputs.dashboard_var_LOG_OCID` |
| `__REGION_ID__` | `.inputs.dashboard_var_REGION_ID` |

### Key Extension in `tools/ensure_dashboard.sh`

Added over the oci_scaffold base:

1. **`dashboard_var_*` substitution** — iterates all `.inputs.dashboard_var_*` state keys, builds `sed` args array, applies to tiles file before passing to OCI CLI
2. **OCI export format unwrap** — `jq 'if type == "object" and has("widgets") then .widgets else . end'` converts `{"widgets":[...]}` to plain array

### State Keys Written

| Key | Value |
| --- | --- |
| `.dashboard_group.ocid` | Dashboard group OCID |
| `.dashboard_group.name` | `{name_prefix}-group` |
| `.dashboard_group.created` | `true` (created) / `false` (adopted) |
| `.dashboard.ocid` | Dashboard OCID |
| `.dashboard.name` | `{name_prefix}-dashboard` |
| `.dashboard.created` | `true` (created) / `false` (adopted) |
| `.dashboard.deployed` | `true` when widgets were applied |

### Usage

```bash
export NAME_PREFIX="sli-step6"
source oci_scaffold/do/oci_scaffold.sh

_state_set '.inputs.dashboard_tiles_file' "$(pwd)/etc/dashboard_sli_tracker.json"
_state_set '.inputs.oci_compartment' "$(_state_get '.compartment.ocid')"

repo="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
LOG_ID="$(gh variable get SLI_OCI_LOG_ID       -R "$repo")"
LOG_GROUP_ID="$(gh variable get SLI_OCI_LOG_GROUP_ID -R "$repo")"
OCI_REGION="$(echo "$LOG_ID" | cut -d. -f4)"

_state_set '.inputs.dashboard_var_COMPARTMENT_OCID' "$(_state_get '.compartment.ocid')"
_state_set '.inputs.dashboard_var_LOG_GROUP_OCID'   "$LOG_GROUP_ID"
_state_set '.inputs.dashboard_var_LOG_OCID'         "$LOG_ID"
_state_set '.inputs.dashboard_var_REGION_ID'        "$OCI_REGION"

bash tools/ensure_dashboard_group.sh
bash tools/ensure_dashboard.sh
```

Teardown:

```bash
export NAME_PREFIX="sli-step6"
source oci_scaffold/do/oci_scaffold.sh

bash tools/teardown_dashboard.sh
bash tools/teardown_dashboard_group.sh
```

### YOLO Mode Decisions

#### Decision 1: Local copy over direct oci_scaffold call

**Context:** oci_scaffold `ensure-dashboard.sh` lacks `dashboard_var_*` substitution and OCI export format support.
**Decision Made:** Copy all four scripts locally; extend only `ensure_dashboard.sh`; promote upstream after validation.
**Rationale:** No submodule changes; diff reviewable before upstream PR.
**Risk:** Low.

---

## SLI-65: MANUAL.md — OCI Console Dashboard section

Status: Implemented

### Changes to `docs/MANUAL.md`

- TOC entry: `[7.4 OCI Console Dashboard](#74-oci-console-dashboard)`
- `### 7.4 OCI Console Dashboard` section added after §7.3
- Content: script overview, placeholder table, full deploy block, state keys table, verify step, teardown block
- Deploy block sources oci_scaffold, sets `.inputs.oci_compartment`, reads log OCIDs from `gh variable get`, sets all `dashboard_var_*` keys, runs both ensure scripts
- Teardown block runs teardown in correct order (dashboard first, then group)
