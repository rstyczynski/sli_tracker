# Sprint 30 - Design

## SLI-60: Unified source-adapter interface for routing definition and mapping loading

Status: Proposed

### Requirement Summary

Replace three inconsistent loading mechanisms (hardwired filesystem, bespoke mapping-source interface, Fn-inline OCI loading) with one `ContentSourceAdapter` interface in the core library. Ship filesystem and OCI Object Storage built-in implementations. All routing definition loading, mapping loading paths go through this interface. CLI accepts `oci://bucket/object` URIs; Fn constructs the adapter from env vars.

### Feasibility Analysis

**Technical Constraints**

All affected code is Node.js. OCI SDK is already a dependency in both `tools/` and `fn/`. No external framework changes needed. The `fn/router_passthrough/lib/` files are identical to `tools/` — one set of changes applies to both.

**Risk Assessment**

- Backward compatibility for `loadRoutingDefinition(filePath)`: low risk — wrapper preserved.
- Fn inline loading replaced by shared adapter: medium risk — Fn integration must be tested carefully; existing env-var contract preserved.
- Mapping source interface change: low risk — internal to `mapping_loader.js`; no external callers outside router stack.

### Design Overview

**New interface: `ContentSourceAdapter`**

```
ContentSourceAdapter {
  async readContent(key: string): Promise<string>
}
```

`key` is a storage-backend-specific identifier: a file path for filesystem, an object name for OCI Object Storage. The bucket (for OCI) is configuration bound at construction time, not at call time.

**New files**

`tools/adapters/content_source_adapter.js` — exports `createFileSystemContentSourceAdapter({ basePath? })`. When `basePath` is set, keys are resolved relative to it; otherwise keys are absolute or relative to `process.cwd()`.

`tools/adapters/oci_object_storage_content_source.js` — exports `createOciObjectStorageContentSourceAdapter({ bucket, getObject })`. `getObject` is an injected async function (same pattern as existing adapters) so the adapter is unit-testable without OCI credentials.

**Changed files**

`tools/json_router.js` — `loadRoutingDefinition(filePath)` gains an optional second argument `contentSourceAdapter`. When omitted it constructs a `FileSystemContentSourceAdapter` internally (fully backward-compatible). An async variant `loadRoutingDefinitionAsync(key, contentSourceAdapter)` is added for callers that already have an adapter.

`tools/adapters/oci_object_storage_mapping_source.js` — `createOciObjectStorageMappingSource` option `getObject` is replaced by `contentSourceAdapter`. Internally calls `contentSourceAdapter.readContent(joinPrefix(prefix, mappingKey))`.

`tools/router_runtime.js` — constructs one `OciObjectStorageContentSourceAdapter` per run (passed to both mapping source and routing load).

`tools/json_router_cli.js` — `--routing` flag parses `oci://bucket/object-key` to select OCI adapter; plain path selects filesystem adapter. `buildOciObjectStorageGetObject` is refactored into a shared helper used by the adapter factory.

`fn/router_passthrough/router_core.js` — `loadRoutingDefinitionForRun` and `buildLoadMappingFromRef` are replaced by calls to the shared adapter. The existing env-var contract (`SLI_ROUTING_BUCKET`, `SLI_ROUTING_OBJECT`, `SLI_MAPPING_BUCKET`) is preserved as the source of bucket/key configuration.

**Data flow**

```
CLI --routing oci://bucket/config/routing.json
  → parse URI → OciObjectStorageContentSourceAdapter(bucket)
  → loadRoutingDefinitionAsync("config/routing.json", adapter)
  → adapter.readContent("config/routing.json")
  → OCI getObject → JSON.parse → routing definition object

CLI --routing ./local/routing.json  (no change for existing users)
  → FileSystemContentSourceAdapter()
  → loadRoutingDefinition("./local/routing.json")  (backward compat wrapper)

Fn env: SLI_ROUTING_BUCKET=ingest, SLI_ROUTING_OBJECT=config/routing.json
  → OciObjectStorageContentSourceAdapter("ingest")
  → loadRoutingDefinitionAsync("config/routing.json", adapter)

Mapping load (routing.json declares mapping.type = oci_object_storage)
  → same adapter instance reused
  → OciObjectStorageContentSourceAdapter.readContent(joinPrefix(prefix, mappingKey))
```

**Envelope source adapter (`source_loader.js`)** is out of scope for this sprint. It serves a different purpose (streaming multiple items) and already uses a correct adapter pattern. Unifying it with `ContentSourceAdapter` would require a separate design.

### Implementation Approach

1. Create `tools/adapters/content_source_adapter.js` with `FileSystemContentSourceAdapter`.
2. Create `tools/adapters/oci_object_storage_content_source.js` with `OciObjectStorageContentSourceAdapter`.
3. Refactor `tools/json_router.js`: optional second arg for `loadRoutingDefinition`, add `loadRoutingDefinitionAsync`.
4. Refactor `tools/adapters/oci_object_storage_mapping_source.js`: replace `getObject` option with `contentSourceAdapter`.
5. Refactor `tools/router_runtime.js`: construct and share one adapter instance.
6. Refactor `tools/json_router_cli.js`: URI parsing, adapter selection.
7. Refactor `fn/router_passthrough/router_core.js`: inline loaders replaced.
8. Sync changes to `fn/router_passthrough/lib/json_router.js` (identical to `tools/json_router.js`).

### Testing Strategy

#### Recommended Sprint Parameters

- **Test:** unit — pure adapter logic; no OCI infra needed for unit coverage.
- **Regression:** unit — all existing router unit tests must still pass.
- **Regression scope:** router — changes are confined to router adapters and core.

#### Unit Test Targets

| Component | Functions to Test | Key Inputs & Edge Cases | Isolation |
|-----------|-------------------|-------------------------|-----------|
| `tools/adapters/content_source_adapter.js` | `createFileSystemContentSourceAdapter.readContent` | existing file, missing file, relative path, absolute path | no mocks (real tmp files) |
| `tools/adapters/oci_object_storage_content_source.js` | `createOciObjectStorageContentSourceAdapter.readContent` | success, OCI error, non-string response | mock `getObject` function |
| `tools/json_router.js` | `loadRoutingDefinitionAsync` | valid routing JSON via mock adapter, invalid JSON, adapter read error | mock `ContentSourceAdapter` |
| `tools/adapters/oci_object_storage_mapping_source.js` | `createOciObjectStorageMappingSource.load` | `.jsonata` key, `.json` key, missing object | mock `ContentSourceAdapter` |
| `tools/json_router_cli.js` | URI parsing | `oci://bucket/key`, plain path, malformed URI | none (pure parsing logic) |

#### Integration Test Scenarios

No new integration tests in this sprint. The OCI integration paths are already exercised by `test_json_router_mapping_oci_object_storage.sh` and `test_router_flow_2_file_to_bucket_map_bucket.sh` — once the refactor is in place those tests validate the end-to-end behaviour.

#### Smoke Test Candidates

No new smoke tests. Existing router smoke tests cover basic routing validity.

**Success Criteria**

All unit tests for new adapter files pass. All existing router unit tests pass (regression). `loadRoutingDefinition(filePath)` with a plain string path still works without any adapter argument.

### Integration Notes

**Dependencies:** Sprint 29 (SLI-48) is Done. No further prerequisites.

**Compatibility:** `loadRoutingDefinition(filePath)` signature is unchanged for one-argument callers. Env vars `SLI_ROUTING_BUCKET`, `SLI_ROUTING_OBJECT`, `SLI_MAPPING_BUCKET` in Fn are preserved.

### Documentation Requirements

- Add `--routing oci://bucket/object` URI syntax to CLI usage output.
- Update `fn/router_passthrough/README.md` (if it exists) to note that routing and mapping are loaded via shared `ContentSourceAdapter`.

### Design Decisions

**Decision 1:** Keep `ContentSourceAdapter` interface minimal — single `readContent(key)` method.
**Rationale:** Simple interfaces are easier to implement, mock, and test. Additional methods (e.g. `listContent`) belong in the envelope source adapter, which already serves that role.
**Alternatives considered:** Combining with `SourceAdapter` (streaming) — rejected as over-engineering.

**Decision 2:** Envelope source adapter (`source_loader.js`) is out of scope.
**Rationale:** It serves a fundamentally different purpose (batch streaming, not single-read). Unifying it would enlarge scope without clear benefit.
**Alternatives considered:** Full unification — deferred to a future backlog item if needed.

**Decision 3:** CLI URI scheme is `oci://bucket/object-key`.
**Rationale:** Unambiguous, easy to parse, consistent with URI conventions already familiar to OCI operators.
**Alternatives considered:** Separate `--routing-bucket` / `--routing-object` flags — more verbose with no benefit.

### Open Design Questions

None.

---

# Design Summary

## Overall Architecture

One `ContentSourceAdapter` interface (`readContent(key)`) with two implementations replaces three separate reading mechanisms. Routing definition loading and mapping loading both delegate to the injected adapter. The Fn constructs the adapter from env vars; the CLI selects it from the `--routing` argument URI scheme.

## Shared Components

`OciObjectStorageContentSourceAdapter` is shared across routing definition load, mapping load, and Fn core — constructed once per request/run and passed down.

## Design Risks

Low. No user-facing API changes. All callers get backward-compatible wrappers. The only non-trivial risk is the Fn integration path, which is covered by existing integration tests.

## Resource Requirements

No new npm dependencies. All required OCI SDK packages are already declared.

## Design Approval Status

Awaiting Review
