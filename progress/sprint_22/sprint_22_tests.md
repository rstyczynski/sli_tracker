# Sprint 22 Tests — SLI-35 Public Fn router → Object Storage

## Layout (where things live)

| Piece | Location |
|-------|----------|
| OCI Function sources | `fn/router_passthrough/` (`func.js`, `router_core.js`, `routing.json`, `lib/*`, …) |
| Provisioning cycle (SLI-specific) | `tools/cycle_apigw_router_passthrough.sh` — `cd`s into `oci_scaffold/` and runs stock **`ensure/*.sh`** only (reference); does **not** modify files under `oci_scaffold/` |
| Fn → Object Storage IAM | `tools/ensure_fn_resource_principal_os_policy.sh` (invoked from the cycle when `FN_ROUTER_AUTO_INGEST_BUCKET=true`) |
| Sprint-end stack teardown | **`tests/cleanup_router_apigw_stack.sh`** — same *role* as **`tests/cleanup_sli_buckets.sh`**: manual / end-of-sprint only; does **not** run after each integration test. Implements via `tools/teardown_router_apigw_stack.sh`. |
| Scaffold state file | `oci_scaffold/state-${NAME_PREFIX}.json` (created by ensure scripts) |
| Per-script logs | `logs/<timestamp>_integration_<name>.log` (from `tests/run.sh`) |

**Rule:** SLI-owned scripts under `tools/` must **not** read or write `state.json`’s **`.meta.creation_order`** — only oci_scaffold `ensure-*.sh` resources manage that field. SLI IAM uses **`.fn_rp_os.*`** and **`tools/teardown_fn_resource_principal_os_policy.sh`**.

### Cycle script behavior (`tools/cycle_apigw_router_passthrough.sh`)

Run from **repository root** with `NAME_PREFIX` set:

- **Compartment:** `SLI_COMPARTMENT_PATH` (default **`/SLI_tracker`**) — not `/oci_scaffold`.
- **Fn CLI context name:** `SLI_FN_CONTEXT` (default **`sli_tracker`**); compartment-id is synced each run.
- **Stable stack:** keep the same `NAME_PREFIX` across runs so VCN / API Gateway / DNS are reused; avoids reprovisioning and DNS propagation churn.
- Defaults: `FN_FUNCTION_NAME=router_passthrough`, `FN_FUNCTION_SRC_DIR=../fn/router_passthrough`, `FN_ROUTER_AUTO_INGEST_BUCKET=true`, `CYCLE_APIGW_TEST_EXPECT=router`.
- **Teardown:** **never** runs by default (API GW + networking stay up for repeated Fn deploys). Set **`CYCLE_APIGW_RUN_TEARDOWN=true`** only if provisioning is broken and you must destroy the stack from the cycle script. Normal Fn work: bump **`func.yaml`** + **`FN_FORCE_DEPLOY=true`**. Sprint-end cleanup: **`tests/cleanup_router_apigw_stack.sh`** (same class of action as **`tests/cleanup_sli_buckets.sh`**).
- **DNS flakiness:** optional `CYCLE_APIGW_POST_DNS_SLEEP`, `CYCLE_APIGW_CURL_ATTEMPTS`, `CYCLE_APIGW_CURL_RETRY_SLEEP` (see script header).

Example (manual):

```bash
cd /path/to/SLI_tracker
export NAME_PREFIX="sli-router-passthrough-dev"
export SLI_COMPARTMENT_PATH="/SLI_tracker"
export FN_FORCE_DEPLOY=true   # after bumping func.yaml version
./tools/cycle_apigw_router_passthrough.sh
```

### Integration test script (`tests/integration/test_fn_apigw_object_storage_passthrough.sh`)

- Default **`SLI_FN_APIGW_ROUTER_PREFIX=sli-router-passthrough-dev`** (stable; override if needed).
- **`SLI_COMPARTMENT_PATH=/SLI_tracker`** by default.
- Runs `npm install` in `fn/router_passthrough/`, then **`tools/cycle_apigw_router_passthrough.sh`** (no teardown — stack stays up).
- **`FN_FORCE_DEPLOY` default `false`** — set `true` when you changed Fn code (and bumped `func.yaml`).
- POSTs a second payload with `source_meta.file_name` and verifies the object in the bucket.
- **No API GW teardown** after PASS. When the sprint is done (same idea as bucket cleanup):  
  `./tests/cleanup_router_apigw_stack.sh`  
  (default `NAME_PREFIX` matches this test; optional `NAME_PREFIX=...`). Optionally run **`tests/cleanup_sli_buckets.sh`** for stray `sli-*` buckets in `/SLI_tracker`.

Override prefix: `SLI_FN_APIGW_ROUTER_PREFIX=my-prefix`.

---

## Gate A2 — Unit (new tests)

Command:

```bash
TS="$(date -u '+%Y%m%d_%H%M%S')"
LOG="progress/sprint_22/test_run_A2_unit_${TS}.log"
tests/run.sh --unit --new-only progress/sprint_22/new_tests.manifest 2>&1 | tee "$LOG"
```

Result: **PASS** — 1 script passed, 0 failed (see artifact below).

Coverage:

- `runRouter` with stub `putObject` (pass-through body, random `ingest/fn-*` object name, `source_meta.file_name` override)

## Gate B2 — Unit regression (router/transformer + Fn)

Command:

```bash
TS="$(date -u '+%Y%m%d_%H%M%S')"
LOG="progress/sprint_22/test_run_B2_unit_${TS}.log"
tests/run.sh --unit --manifest progress/sprint_22/regression_tests.manifest 2>&1 | tee "$LOG"
```

Result: **PASS** — 14 scripts passed, 0 failed (see artifact below).

Scope: router/transformer unit surface (sprint 21–style manifest) plus `test_json_router_mapping_source.sh` and `test_fn_passthrough_router.sh`.

## Gate C2 — Integration (live OCI, API Gateway + Fn + bucket)

**Requires:** `oci` + `fn` CLI, valid OCI profile (`SLI_INTEGRATION_OCI_PROFILE` or `DEFAULT`), permission to create resources in **`/SLI_tracker`** (or override `SLI_COMPARTMENT_PATH`). Optional `FN_OS_POLICY_SKIP=true` if IAM already allows Fn → Object Storage.

Command (central runner + manifest):

```bash
TS="$(date -u '+%Y%m%d_%H%M%S')"
LOG="progress/sprint_22/test_run_C2_integration_${TS}.log"
tests/run.sh --integration --manifest progress/sprint_22/integration_tests.manifest 2>&1 | tee "$LOG"
```

Direct script (same test):

```bash
tests/integration/test_fn_apigw_object_storage_passthrough.sh
```

Result and artifact: see **Gate C2 result** below (updated when this gate is executed).

---

## Artifacts (log files under `progress/sprint_22/`)

| Gate | Log file |
|------|----------|
| A2 | `test_run_A2_unit_20260410_122939.log` (historical); latest run overwrites via `tee` command above |
| B2 | `test_run_B2_unit_20260410_122942.log` (historical); latest run via `tee` |
| C2 | See Gate C2 result section |

## Gate C2 result

- Integration **leaves** API GW + Fn + bucket stack running (reuse with stable **`NAME_PREFIX`** / **`SLI_FN_APIGW_ROUTER_PREFIX`**).
- Record **PASS** here when a full run completes; attach `progress/sprint_22/test_run_C2_integration_*.log` and `logs/*_integration_test_fn_apigw_object_storage_passthrough.log` as needed.
- If the cycle POST fails with **curl (6) Could not resolve host**, wait for DNS or tune **`CYCLE_APIGW_POST_DNS_SLEEP`** / **`CYCLE_APIGW_CURL_ATTEMPTS`** (see cycle script header).

*(Operator: fill in date / PASS-FAIL / log paths after a successful tenant run.)*

## Outcome

- Run A2/B2 before merge; run C2 in a tenant with **`/SLI_tracker`** (or chosen `SLI_COMPARTMENT_PATH`) and Functions + API Gateway enabled.
- C2 leaves the stack running; note **PASS** and the `test_run_C2_integration_*.log` path in **Gate C2 result** when recorded.
- Tear down the router stack only when finished: **`tests/cleanup_router_apigw_stack.sh`** (and **`tests/cleanup_sli_buckets.sh`** for stray `sli-*` buckets if needed).
