# Sprint 22 — Bug Fixes

## Status: Fixed

Post-delivery defects against **SLI-35** (public router Fn): router configuration was embedded in the Function image instead of **Object Storage**, which blocks operator updates without redeploying the image and violated the agreed deployment contract.

---

## SLI-35-1 — `routing.json` bundled in Function image

**Root cause:** The handler read `routing.json` from the local filesystem inside the deployed image (`fs.readFileSync` under `fn/router_passthrough/`), so routing was not operator-updatable from Object Storage.

**Fix:** Load the routing definition with Resource Principal via `getObject` using `SLI_ROUTING_BUCKET` / `SLI_ROUTING_OBJECT` (defaults aligned with ingest bucket and `config/routing.json`). `tools/cycle_apigw_router_passthrough.sh` uploads the seed from `tests/fixtures/fn_router_passthrough/routing.json` and merges Fn configuration. Unit tests inject `options.routingDefinition` and omit Object Storage.

**Files:** `fn/router_passthrough/router_core.js`, `tools/cycle_apigw_router_passthrough.sh`, `tests/fixtures/fn_router_passthrough/routing.json`, `tests/integration/test_fn_apigw_object_storage_passthrough.sh`, `tests/unit/test_fn_passthrough_router.sh`, `fn/router_passthrough/func.yaml` (version bump for redeploy); removed `fn/router_passthrough/routing.json`.

**Verification:** `bash tests/unit/test_fn_passthrough_router.sh` — **PASS**; full gate `tests/run.sh --all` after integration — **PASS** (recorded in `test_run_full_all_20260410_134908.log` prior to subsequent Fn config iterations).

**Status:** Fixed

---

## SLI-35-2 — `passthrough.jsonata` bundled in Function image

**Root cause:** The pass-through JSONata mapping was shipped as `fn/router_passthrough/passthrough.jsonata` and resolved via filesystem `loadMapping`, so mapping text could not be owned in Object Storage like the routing document.

**Fix:** Added optional handler `loadMappingFromRef` in `json_router.js` (Fn vendored copy and `tools/json_router.js`): when `transform.mapping` resolves to basename `passthrough.jsonata`, `router_core.js` loads body text from Object Storage (`SLI_PASSTHROUGH_OBJECT`, default `config/passthrough.jsonata`; bucket `SLI_MAPPING_BUCKET` or routing/ingest bucket). Cycle script uploads seed from `tests/fixtures/fn_router_passthrough/passthrough.jsonata`. Unit tests pass `options.loadMappingFromRef` reading the fixture.

**Files:** `fn/router_passthrough/router_core.js`, `fn/router_passthrough/lib/json_router.js`, `tools/json_router.js`, `tools/cycle_apigw_router_passthrough.sh`, `tests/fixtures/fn_router_passthrough/passthrough.jsonata`, `tests/unit/test_fn_passthrough_router.sh`, `tests/integration/test_fn_apigw_object_storage_passthrough.sh`, `fn/router_passthrough/func.yaml`; removed `fn/router_passthrough/passthrough.jsonata`.

**Verification:** `bash tests/unit/test_fn_passthrough_router.sh` — **PASS**; `bash tests/unit/test_json_router.sh` — **PASS** (regression on `loadMappingFromRef` hook).

**Status:** Fixed

---

## Fix Summary

| Bug       | Description                                              | Primary files                                                                 | Status |
|-----------|----------------------------------------------------------|-------------------------------------------------------------------------------|--------|
| SLI-35-1  | Routing definition must load from Object Storage, not image | `router_core.js`, `cycle_apigw_router_passthrough.sh`, fixtures, unit test    | Fixed  |
| SLI-35-2  | JSONata mapping must load from Object Storage, not image    | `router_core.js`, `json_router.js` (fn + tools), cycle script, fixtures, tests | Fixed  |
