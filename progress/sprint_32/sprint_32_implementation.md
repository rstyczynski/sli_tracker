# Sprint 32 - Implementation

## SLI-64: OCI Console Dashboard for SLI Tracker

Status: Implemented

### Main Features

- `etc/dashboard_sli_tracker.json` — versioned template placeholder (`{}`); auto-populated from source dashboard on first ensure run
- `tools/ensure_dashboard.sh` — creates dashboard group + dashboard; idempotent; auto-fetches template if empty
- `tools/teardown_dashboard.sh` — deletes dashboard then group; matches teardown pattern of existing scripts

### Code Artifacts

| File | Purpose |
| --- | --- |
| `etc/dashboard_sli_tracker.json` | Generalized dashboard template (4 placeholders) |
| `tools/ensure_dashboard.sh` | Ensure script (create group + dashboard) |
| `tools/teardown_dashboard.sh` | Teardown script (delete dashboard + group) |

### Template

Template derived from `oci dashboard-service dashboard get --dashboard-id ocid1.consoledashboard.oc1..aaaaaaaaikoqfpryjfhxp2rulyn3t7kgtq3re3ft33kxp52yqymc3ptzqhya`. Source-specific OCIDs and region replaced with:

- `__COMPARTMENT_OCID__` → `.inputs.oci_compartment`
- `__LOG_GROUP_OCID__` → `.log_group.ocid`
- `__LOG_OCID__` → `.log.ocid`
- `__REGION_ID__` → home region (OCI API)

### Usage

```bash
export NAME_PREFIX="<your-prefix>"
bash tools/ensure_dashboard.sh
```

Teardown:

```bash
bash tools/teardown_dashboard.sh
```

### Prerequisites

- OCI CLI installed with a valid profile
- `state-${NAME_PREFIX}.json` with `.inputs.oci_compartment`, `.inputs.name_prefix`, `.log_group.ocid`, `.log.ocid`

### YOLO Mode Decisions

#### Decision 1: Retroactive construction

**Context:** Code was delivered before RUP process artifacts were created.
**Decision Made:** Document as-built; no code changes required.
**Rationale:** Implementation matches design exactly; no divergence detected.
**Risk:** Low.

---

## SLI-65: MANUAL.md — OCI Console Dashboard section

Status: Implemented

### Main Features

- TOC entry added: `[7.4 OCI Console Dashboard](#74-oci-console-dashboard)`
- New `### 7.4 OCI Console Dashboard` section in `docs/MANUAL.md` after §7.3
- Covers: description, prerequisites, deploy command, idempotency note, state key table, verify step, teardown command
