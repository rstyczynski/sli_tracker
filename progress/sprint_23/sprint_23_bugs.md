# Sprint 23 — Bugs (SLI-36)

Bugs found during post-sprint code review of the router codebase (hardcoded-values audit, 2026-04-12).

---

## SLI-36 — BUG-4: Core library duplicated between `tools/` and `fn/router_passthrough/lib/`

**Severity:** High (maintenance / drift risk)

- **Symptom**: Four source files exist as physically separate, identical copies in two locations:

  | File | tools/ | fn/router_passthrough/lib/ |
  | --- | --- | --- |
  | `json_router.js` | `tools/json_router.js` | `fn/router_passthrough/lib/json_router.js` |
  | `json_transformer.js` | `tools/json_transformer.js` | `fn/router_passthrough/lib/json_transformer.js` |
  | `destination_dispatcher.js` | `tools/adapters/destination_dispatcher.js` | `fn/router_passthrough/lib/destination_dispatcher.js` |
  | `oci_object_storage_adapter.js` | `tools/adapters/oci_object_storage_adapter.js` | `fn/router_passthrough/lib/oci_object_storage_adapter.js` |

  Any fix applied to one copy (e.g., BUG-1 above) must be manually mirrored to the other.
  Currently identical; divergence is a matter of time.

- **Root cause**: OCI Function deployment (`fn deploy`) packages the function directory into a
  Docker image and cannot reference files outside it. There is no shared library layer in the
  project, so the core files were physically copied into `fn/router_passthrough/lib/` to satisfy
  the packaging constraint. The root tools package (`package.json`) and the function package
  (`fn/router_passthrough/package.json`) are independent npm contexts with no workspace
  relationship.

- **Fix**: Extract the four shared files into an npm workspace package (e.g.,
  `packages/router-core/`). Both `sli-tracker-tools` and `sli-router-passthrough-fn` declare it
  as a local dependency. The workspace package is installed into each `node_modules/` at
  `npm install` time, so `fn deploy` picks up a single copy. Promotes to a new backlog item
  because it requires restructuring both package trees and updating all `require()` paths.

- **Interim mitigation**: Add a CI / pre-commit check that diffs the four file pairs and fails
  if they diverge — prevents silent drift while the proper fix is scheduled.

- **Verification**: After restructure, `diff tools/... fn/router_passthrough/lib/...` has no
  matching files to compare (copies removed). Both `tools/` and `fn/` tests pass from the shared
  source. `fn deploy` succeeds and the Function unit tests pass unchanged.

---

## SLI-36 — BUG-1: `'x-github-event'` hardcoded in core router library

**Severity:** High (core library)

- **Symptom**: `headerMatchEquals` in `json_router.js:114` applies case-insensitive header value
  comparison only for the `x-github-event` header. All other headers use strict equality.
  The comparison reads:
  ```js
  if (keyLower === 'x-github-event') {
      return actual.toLowerCase() === expected.toLowerCase();
  }
  return actual === expected;
  ```
  Observed in both copies: `fn/router_passthrough/lib/json_router.js` and `tools/json_router.js`
  (files are identical).

- **Root cause**: A GitHub-specific header name was embedded in the generic routing engine to
  accommodate case variations in `X-GitHub-Event` values sent by the GitHub webhook service.
  The logic is correct for its intent but violates library generality: adding a second webhook
  source (Slack, Stripe, etc.) would require touching the same function again.

- **Fix**: Remove the `x-github-event` special case. Make all header value comparisons
  case-insensitive in `headerMatchEquals` (HTTP header values from webhooks are uniformly
  lower-case or documented as such; the routing definition already normalises header *names*
  to lower-case). Update both copies:
  - `fn/router_passthrough/lib/json_router.js:109–118`
  - `tools/json_router.js:109–118`

- **Verification**: Existing unit tests in `tests/unit/test_json_router.sh` and
  `tests/unit/test_fn_passthrough_router.sh` must still pass. Add a case for a header value
  provided in mixed case to confirm consistent behaviour across all header types.

---

## SLI-36 — BUG-2: `'passthrough.jsonata'` basename hardcoded in `router_core.js`

**Severity:** Medium (deployment adapter)

- **Symptom**: `buildLoadMappingFromRef` in `router_core.js:229` returns `null` for any mapping
  reference whose basename is not exactly `'passthrough.jsonata'`:
  ```js
  if (base !== 'passthrough.jsonata') {
      return null;
  }
  ```
  A routing definition that references a different mapping file name (e.g. `transform.jsonata`)
  silently falls through to a local filesystem lookup and fails at runtime without a clear error.

- **Root cause**: The mapping loader was written for a single-mapping deployment. The filename
  was hard-coded instead of being driven by the routing definition or an environment variable.

- **Fix candidates** (requires design decision — **promotion criteria: scope expansion**):
  - Drop the filename check entirely and load any `mappingRef` basename from Object Storage.
  - Or drive it via `SLI_PASSTHROUGH_OBJECT` (already present for the object path) so any
    basename can be configured without code changes.
  - Promote to a new backlog item if the design needs a broader "multi-mapping from Object
    Storage" solution.

- **Verification**: Unit test that passes a routing definition with a non-`passthrough.jsonata`
  mapping ref and asserts the Object Storage load is attempted (not a silent null).

---

## SLI-36 — BUG-3: `'oci_object_storage:raw_ingest'` adapter key hardcoded in `router_core.js`

**Severity:** Low (deployment adapter, project-specific assumption)

- **Symptom**: `applyIngestBucketToRoutingObject` in `router_core.js:148–159` requires that every
  loaded routing definition contains an adapter entry keyed exactly `'oci_object_storage:raw_ingest'`:
  ```js
  const RAW_INGEST_ADAPTER_KEY = 'oci_object_storage:raw_ingest';
  if (!isObject(obj.adapters[RAW_INGEST_ADAPTER_KEY])) {
      throw new Error(`routing definition must define adapters["${RAW_INGEST_ADAPTER_KEY}"]`);
  }
  ```
  Any routing configuration that renames or removes this catch-all adapter will fail validation
  even if all other routes and adapters are valid.

- **Root cause**: The catch-all fallback destination was given a project-specific adapter key that
  was then encoded as a required invariant in the adapter layer rather than validated through
  the routing schema.

- **Fix candidates** (promotion criteria: low urgency, defer unless routing.json changes):
  - Remove the presence check and rely on the existing routing schema + dead-letter config to
    ensure at least one destination is reachable.
  - Or make the required key configurable via `SLI_RAW_INGEST_ADAPTER` env var.

- **Verification**: Load a valid routing definition that omits `oci_object_storage:raw_ingest`
  but defines other `oci_object_storage:*` adapters; confirm the function starts without error.

---

---

## SLI-36 — BUG-5: Integration pre-cleanup deletes all `sli-*` buckets, destroying live stacks

**Severity:** High (data loss / live deployment destruction)

- **Symptom**: Running `tests/run.sh --integration` (or `--all`) unconditionally invokes
  `tests/cleanup_sli_buckets.sh` before any integration script runs. That script deletes every
  OCI Object Storage bucket in the `/SLI_tracker` compartment whose name starts with `sli-` —
  regardless of which `NAME_PREFIX` the integration test was asked to use.

  Any parallel or manually-deployed stack (e.g. `sli-apigw-router-20260410125446-bucket`) is
  destroyed along with its `config/routing.json` and `config/passthrough.jsonata` objects. The
  function returns `{"status":"error","error":"Failed to load routing definition from Object
  Storage (bucket=sli-router-passthrough-dev-bucket, object=config/routing.json): Either the
  bucket named 'sli-router-passthrough-dev-bucket' does not exist in the namespace ..."}` until
  the stack is manually redeployed.

- **Root cause**: `run.sh` lines 73–81 call `cleanup_sli_buckets.sh` unconditionally on every
  integration run. The cleanup script was designed as a sprint-end manual tool (its own header
  says *"Related (sprint-end / manual only)"*) but was wired as an automatic pre-step with no
  scope guard. The `SLI_FN_APIGW_ROUTER_PREFIX` env var — which selects which stack the
  integration test uses — is not forwarded to or respected by the cleanup step.

- **Fix**: Make the pre-cleanup opt-in via an env var (`SLI_INTEGRATION_PRECLEAN=1`). By
  default the cleanup is skipped; the integration test's own `cycle_apigw_router_passthrough.sh`
  call already handles idempotent stack creation from a clean state. Operators who want a full
  wipe before the test pass `SLI_INTEGRATION_PRECLEAN=1` explicitly.

- **Verification**: Run `tests/run.sh --integration` without `SLI_INTEGRATION_PRECLEAN=1` while
  a second `sli-*` bucket exists; confirm the second bucket survives the run. Then run with
  `SLI_INTEGRATION_PRECLEAN=1`; confirm all `sli-*` buckets are removed as before.

---

## Resolution summary

| Bug | Decision | Status | Verification |
| --- | --- | --- | --- |
| BUG-1 (`x-github-event` in core lib) | Fold-in fix | **Fixed 2026-04-12** | UT-111 + all 16 json_router tests pass |
| BUG-2 (`passthrough.jsonata` hardcode) | Fold-in fix | **Fixed 2026-04-12** | BUG-2 inline test in test_fn_passthrough_router.sh |
| BUG-3 (`raw_ingest` key requirement) | Fold-in fix | **Fixed 2026-04-12** | BUG-3 inline test in test_fn_passthrough_router.sh |
| BUG-4 (duplicate library files) | Symlinks (not sync script) | **Fixed 2026-04-12** | tools/ symlinks resolve; all tests pass from fn/lib/ source |
| BUG-5 (pre-cleanup destroys live stacks) | Opt-in via `SLI_INTEGRATION_PRECLEAN=1` | **Fixed 2026-04-12** | Second bucket survives run without env var; wipe still works with it |

## Fix decisions

### BUG-1

Removed the `x-github-event` special case from `headerMatchEquals` and dropped the now-unused
`keyLower` parameter from the function signature and its call site. All header value comparisons
are now uniformly case-insensitive. Applied to the single authoritative source
(`fn/router_passthrough/lib/json_router.js`) — the `tools/` file is a symlink (see BUG-4).

### BUG-2

Removed the `if (base !== 'passthrough.jsonata') return null` guard.
Default object path is now `config/${base}` (derived from the mapping reference basename).
`SLI_PASSTHROUGH_OBJECT` env var remains as a full-path override for backward compatibility.
No design change needed — the existing bucket/object resolution pattern handles all mapping names.

### BUG-3

Removed the `RAW_INGEST_ADAPTER_KEY` constant and the presence check that required exactly
`oci_object_storage:raw_ingest` in every routing definition. The remaining check validates only
that `adapters` is an object (which the routing schema already enforces). The bucket-injection
loop is unchanged — it still stamps `OCI_INGEST_BUCKET` into all `oci_object_storage:*` entries.

### BUG-4

Used symlinks rather than the originally proposed sync-check script or npm workspace restructure.
`fn/router_passthrough/lib/` is the authoritative location (Docker packages it directly).
`tools/` files that were physical copies are now symlinks:

| Symlink | Target |
| --- | --- |
| `tools/json_router.js` | `fn/router_passthrough/lib/json_router.js` |
| `tools/json_transformer.js` | `fn/router_passthrough/lib/json_transformer.js` |
| `tools/adapters/destination_dispatcher.js` | `fn/router_passthrough/lib/destination_dispatcher.js` |
| `tools/adapters/oci_object_storage_adapter.js` | `fn/router_passthrough/lib/oci_object_storage_adapter.js` |
| `tools/schemas/json_router_definition.schema.json` | `fn/router_passthrough/lib/schemas/json_router_definition.schema.json` |

`fn/router_passthrough/lib/json_transformer.js` was aligned to `tools/json_transformer.js`
(restored sprint comment and JSDoc comment; removed trailing blank line) before creating the symlink.

### BUG-5

Made the integration pre-cleanup opt-in. `run.sh` lines 73–81: the unconditional
`cleanup_sli_buckets.sh` call is now gated on `SLI_INTEGRATION_PRECLEAN=1`. If the env var is
absent or empty the pre-step is skipped entirely; the integration test's own
`cycle_apigw_router_passthrough.sh` call handles idempotent stack creation without a prior wipe.
Operators who need a full compartment wipe before the run set `SLI_INTEGRATION_PRECLEAN=1`.
