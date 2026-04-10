# Sprint 22 Implementation — SLI-35 Public Fn router → Object Storage

## Summary

OCI Function **`router_passthrough`** (Node 20) lives under **`fn/router_passthrough/`** in this repository. It uses the same routing contract as `tools/json_router.js`: a single route with pass-through JSONata **`$`** (`passthrough.jsonata`) and delivery through **`createOciObjectStorageAdapter`**. The ingest bucket name is supplied at runtime via function configuration **`OCI_INGEST_BUCKET`** (merged after deploy by **`tools/cycle_apigw_router_passthrough.sh`** when **`FN_ROUTER_AUTO_INGEST_BUCKET=true`**). Authentication to Object Storage inside the function uses the **resource principal** from the Functions runtime.

**`oci_scaffold/`** is used only as a **reference** for generic ensure scripts (`ensure-vcn.sh`, `ensure-fn_function.sh`, etc.); SLI-specific provisioning and IAM glue live under **`tools/`**.

## Files Created

- `fn/router_passthrough/func.js`
- `fn/router_passthrough/router_core.js`
- `fn/router_passthrough/lib/json_router.js` (vendored from `tools/json_router.js`)
- `fn/router_passthrough/lib/destination_dispatcher.js`
- `fn/router_passthrough/lib/oci_object_storage_adapter.js`
- `fn/router_passthrough/lib/json_transformer.js`, `lib/schemas/json_router_definition.schema.json`
- `fn/router_passthrough/routing.json`, `passthrough.jsonata`, `func.yaml`, `package.json`, `package-lock.json`
- `tools/cycle_apigw_router_passthrough.sh` — full APIGW+Fn+bucket+config cycle; default compartment **`/SLI_tracker`** (`SLI_COMPARTMENT_PATH`); **no teardown** unless `CYCLE_APIGW_RUN_TEARDOWN=true`
- `tools/ensure_fn_resource_principal_os_policy.sh` — dynamic group + IAM for Fn → Object Storage; stores OCIDs under `.fn_rp_os` only (**never** touches `.meta.creation_order`)
- `tools/teardown_fn_resource_principal_os_policy.sh` — deletes SLI IAM policy + dynamic group from `.fn_rp_os.*`
- `tools/teardown_router_apigw_stack.sh` — sprint-end / manual: IAM teardown + `oci_scaffold/do/teardown.sh`
- `tests/cleanup_router_apigw_stack.sh` — **`tests/` entry** for stack teardown (same *role* as **`tests/cleanup_sli_buckets.sh`**; not run after each Fn test)
- `tests/unit/test_fn_passthrough_router.sh`
- `tests/integration/test_fn_apigw_object_storage_passthrough.sh`
- `progress/sprint_22/regression_tests.manifest`
- `progress/sprint_22/integration_tests.manifest`

## Files Updated

- `tests/integration/test_fn_apigw_object_storage_passthrough.sh` — calls `tools/cycle_apigw_router_passthrough.sh`, `fn/router_passthrough` for npm install

## Provisioning and IAM

- **`tools/cycle_apigw_router_passthrough.sh`**: `cd oci_scaffold`, run ensure scripts; compartment path **`SLI_COMPARTMENT_PATH`** (default **`/SLI_tracker`**); **`FN_FUNCTION_SRC_DIR=../fn/router_passthrough`**; ingest bucket + **`OCI_INGEST_BUCKET`**; default **no** `do/teardown.sh` (reuse stack).
- **`FN_OS_POLICY_SKIP=true`**: skip **`tools/ensure_fn_resource_principal_os_policy.sh`** if the tenancy already grants equivalent access.
- **`tests/cleanup_router_apigw_stack.sh`**: run when reclaiming the stack after the sprint (same class of action as **`tests/cleanup_sli_buckets.sh`**); calls **`tools/teardown_router_apigw_stack.sh`**.

## Handler Contract

- **Input**: JSON object or array, or envelope `{ "body", "headers?", "endpoint?", "source_meta?" }`.
- **Output**: `processEnvelope` result (`status: "routed"` and `deliveries`, or `dead_letter` / errors as `{ status: "error", error }`).

Object names default to `ingest/fn-<time>-<random>.json`; optional **`source_meta.file_name`** sets a stable name under the adapter prefix.
