# Sprint 27 — Implementation (SLI-44)

**`PLAN.md`:** **`Test: unit, integration`** · **`Regression: unit`**. Delivery is not complete until a **live OCI** integration test for the Logging fan-out is in `new_tests.manifest` / `sprint_27_tests.md` and passes **A3**.

## Status: DONE

## Summary

Sprint 27 tracks **SLI-44**: fan-out **`workflow_run`** to **OCI Logging** alongside Object Storage (Sprint 23/36) and Monitoring (Sprint 26). This document lists work packages; merge requests should tick them off.

## OCI Logging resources (provisioning — 2026-04-12)

**Goal:** A **custom** log in compartment **`SLI_tracker`** for **`emit.sh`** / GitHub Actions ingestion (not a Functions SERVICE log).

### URI convention

- Use **`SLI_OCI_LOG_URI=/SLI_tracker/sli-events/github-actions`** so `ensure_sli_log_resources` creates the log group under the **`SLI_tracker`** compartment.
- A URI starting with **`//`** (for example `//sli-events/github-actions`) resolves to the **tenancy root** compartment, not `SLI_tracker`. The README quick start documents this explicitly.

### Script behavior

- **`tools/ensure_oci_resources.sh`** — `ensure_sli_log_resources` sets **`.inputs.log_type`** to **`CUSTOM`** before **`oci_scaffold/resource/ensure-log.sh`**, because GitHub-style payloads are not valid for the default **SERVICE** (Functions invoke) log configuration.
- **`oci_scaffold/resource/ensure-log.sh`** — When **`log_type`** is **`CUSTOM`**, creates or finds a log with **`oci logging log create --log-type CUSTOM`** and no OCISERVICE configuration.

### Idempotent run — OCIDs only from here

From repo root (pick a stable `NAME_PREFIX` per run; state file is `./state-${NAME_PREFIX}.json` in **cwd** while scripts run):

```bash
cd /path/to/SLI_tracker
source ./tools/ensure_oci_resources.sh
export NAME_PREFIX=sli_log_verify
ensure_sli_log_resources "$(pwd)" "${OCI_CLI_PROFILE:-DEFAULT}" "$NAME_PREFIX" "/SLI_tracker/sli-events/github-actions"
```

**Authoritative OCIDs** (do not copy from docs or the console):

1. **Environment** — after the call above, the function exports **`COMPARTMENT_OCID`**, **`LOG_GROUP_OCID`**, **`SLI_LOG_OCID`** (and **`TENANCY`**).
2. **State file** — same values are persisted under **`.compartment.ocid`**, **`.log_group.ocid`**, **`.log.ocid`** in **`./state-${NAME_PREFIX}.json`** (see `oci_scaffold/do/oci_scaffold.sh`).

Example read-back (after provisioning):

```bash
jq -r '"compartment=" + .compartment.ocid, "log_group=" + .log_group.ocid, "log=" + .log.ocid' "./state-${NAME_PREFIX}.json"
```

### GitHub Actions variables — must match deployment output

Use **`ensure_set_github_sli_vars`** in `tools/ensure_oci_resources.sh`, which takes **`owner/repo`** plus the three OCIDs **in the same order as the exports** (compartment, log, log group). Only pass values from the **`ensure_sli_log_resources`** exports or from **`jq`** on **`STATE_FILE`** for that run — never hand-paste OCIDs into the repo or into `gh variable set`.

```bash
REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
ensure_set_github_sli_vars "$REPO" "$COMPARTMENT_OCID" "$SLI_LOG_OCID" "$LOG_GROUP_OCID"
```

### Resource names (not OCIDs)

| Resource     | Name             |
|--------------|------------------|
| Compartment  | `SLI_tracker`    |
| Log group    | `sli-events`     |
| Log (CUSTOM) | `github-actions` |

## Work packages

1. **Adapter** — Implement `oci_logging` (or agreed name) in `fn/router_passthrough` dispatch path; config keys; PutLogEvents (or Logging Ingestion API) via Resource Principal.
2. **Routing fixture** — Update `tests/fixtures/fn_router_passthrough/routing.json`: new adapter + `fanout` route; keep existing routes intact.
3. **JSONata** — Add `workflow_run_log.jsonata` (or passthrough) under fixtures; upload name `config/...` via cycle script.
4. **Cycle / Fn config** — Extend `tools/cycle_apigw_router_passthrough.sh` to merge log OCID (and policies) into Fn `config`.
5. **Tests** — Replace `test_sli44_rup_placeholder.sh` with UT-SLI44-1/2; add IT-SLI44-1 per `sprint_27_design.md`.
6. **Docs** — Update this file, `sprint_27_design.md` if scope shifts, and `README.md` Recent updates when the feature ships end-to-end.

## Deferred to construction

- Exact log JSON schema and redaction rules.
- Whether Logging mirrors metrics filter (completed-only) or logs every delivery.

## References

- `BACKLOG.md` **SLI-44**
- `progress/sprint_27/sprint_27_design.md`
- `fn/router_passthrough/lib/json_router.js` (`selectRoutes` composition)
