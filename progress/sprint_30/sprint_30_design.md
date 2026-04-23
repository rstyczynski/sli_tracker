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

`tools/adapters/mapping_loader.js` — When `mapping` field in the routing definition is a URI string (`oci://bucket/prefix/`), the loader parses the URI and constructs the appropriate `ContentSourceAdapter`. This replaces the verbose `{ "type": "oci_object_storage", "name": "mappings" }` + adapters block pattern with a simple URI.

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

Mapping load — URI form (routing.json declares mapping: "oci://sli-mappings/jsonata/")
  → parse URI → OciObjectStorageContentSourceAdapter("sli-mappings", prefix="jsonata/")
  → route.transform.mapping = "passthrough.jsonata"
  → adapter.readContent("jsonata/passthrough.jsonata")

Mapping load — object form (routing.json declares mapping.type = oci_object_storage)
  → same adapter instance reused (backward compatible)
  → OciObjectStorageContentSourceAdapter.readContent(joinPrefix(prefix, mappingKey))

Mapping load — local path (routing.json declares mapping: "./mappings/")
  → FileSystemContentSourceAdapter(basePath="./mappings/")
  → adapter.readContent("passthrough.jsonata")
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
- **Regression:** integration — all existing router unit AND integration tests must pass.
- **Regression scope:** router — changes are confined to router adapters and core.

#### Unit Test Targets

Test file: `tests/unit/test_content_source_adapter.sh`

| ID | Test Case | Component | Input | Expected | Isolation |
|----|-----------|-----------|-------|----------|-----------|
| T1 | FileSystem reads existing file | `content_source_adapter.js` | tmp file with `{"hello":"world"}` | Returns content string | real tmp file |
| T2 | FileSystem throws on missing file | `content_source_adapter.js` | non-existent path | Error: "Cannot read content" | none |
| T3 | OCI adapter reads object from bucket | `oci_object_storage_content_source.js` | bucket=`test-bucket`, key=`config/routing.json` | Returns object content | mock getObject |
| T4 | OCI adapter propagates bucket error | `oci_object_storage_content_source.js` | bucket=`test-bucket`, key=`missing.json` → OCI 404 | Error: "Object not found" | mock getObject |
| T5 | loadRoutingDefinitionAsync uses adapter | `json_router.js` | FileSystem adapter + routing.json | Parsed definition object | real tmp file |
| T6 | loadRoutingDefinition backward compat | `json_router.js` | single file path argument | Parsed definition object | real tmp file |
| T7 | Mapping source loads from bucket via adapter | `oci_object_storage_mapping_source.js` | adapter reads `passthrough.jsonata` from bucket | Mapping string returned | mock adapter |
| T8 | URI parsing extracts bucket/key | `content_source_adapter.js` | `oci://bucket/config/routing.json` | `{bucket:"bucket", objectKey:"config/routing.json"}` | none |
| T9 | URI parsing for mapping prefix | `content_source_adapter.js` | `oci://sli-mappings/jsonata/` | `{bucket:"sli-mappings", objectKey:"jsonata/"}` | none |
| T10 | isOciUri detects oci:// scheme | `content_source_adapter.js` | `oci://bucket/key`, `./local/path` | true, false | none |
| T11 | FileSystem with basePath | `content_source_adapter.js` | basePath + relative key | Resolved path content | real tmp file |

#### Integration Test Scenarios

Regression tests (existing, must pass after refactor):

| Test Script | What It Validates |
|-------------|-------------------|
| `test_json_router_mapping_oci_object_storage.sh` | Mapping loaded from OCI Object Storage via adapter |
| `test_router_flow_2_file_to_bucket_map_bucket.sh` | End-to-end routing with OCI bucket destination |
| All router component tests via `--component router` | Full router stack unchanged behavior |

#### Smoke Test Candidates

No new smoke tests. Existing router smoke tests cover basic routing validity.

**Success Criteria**

1. All 11 unit tests in `test_content_source_adapter.sh` pass
2. All existing router unit tests pass (regression): `bash tests/run.sh --unit --component router`
3. All existing router integration tests pass: `bash tests/run.sh --integration --component router`
4. `loadRoutingDefinition(filePath)` with a plain string path still works without any adapter argument
5. Existing routing definitions with object-form `mapping` field continue to work

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

**Decision 4:** Mapping source in routing.json supports URI string form `oci://bucket/prefix/` in addition to object form.
**Rationale:** Simplifies routing definitions — replaces verbose `{ "type": "oci_object_storage", "name": "mappings" }` + adapters block with a single URI string. Object form remains supported for backward compatibility.
**Alternatives considered:** Object form only — more verbose, requires separate adapter entry.

**Decision 5:** Compartment path in URI (`oci://comp1/comp2/bucket/key`) is deferred to SLI-61.
**Rationale:** OCI looks up buckets by name within a namespace; bucket names must be unique in a tenancy. Compartment path is optional clarity, not required for API calls.
**Alternatives considered:** Implement now — not critical, adds parsing complexity without functional benefit.

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
