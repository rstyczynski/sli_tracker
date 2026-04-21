# Sprint 30 - Setup

## Contract

### Project scope confirmed

SLI Tracker is a set of GitHub Actions, shell scripts, and OCI Function components that track and emit Service Level Indicators to OCI Logging and Monitoring from CI/CD pipelines. The router component accepts webhooks, applies JSONata mappings, and forwards to OCI Object Storage, Monitoring, and Logging.

### Sprint objective understood

Sprint 30 introduces a unified source-adapter interface so that routing definition loading, mapping loading, and envelope source loading all go through one pluggable abstraction backed by filesystem and OCI Object Storage built-in implementations. CLI and Fn configuration selects the adapter; no code change is needed to switch storage backends.

### Rules compliance confirmed

- `GENERAL_RULES.md`: Implementor only edits allowed documents; status tokens are owned by Product Owner; all changes to the plan go through proposed-changes process.
- `GIT_RULES.md`: Semantic commit messages without text before the colon; push after every commit.
- `backlog_item_definition.md`: Backlog items state what and why; no design or architecture.
- `sprint_definition.md`: Sprint 30 Mode is managed — design approval is required before construction.
- `testing_strategy_template.md` and `test_procedures.md`: Test-first gates A1→A2→A3, B1→B2→B3; log artifacts per gate; register new tests in manifests.

### Constraints acknowledged

- `oci_scaffold` is a submodule — no edits to any file inside it.
- No hard line wrapping in prose.
- Commit and push every file change immediately.
- PLAN.md is read-only except for the Status field transition.

### Open questions

None — scope is clear.

---

## Analysis

### SLI-60: Unified source-adapter interface for routing definition and mapping loading

**Requirement summary**

Three distinct loading mechanisms exist today for the three types of configuration the router reads at runtime:

1. Routing definition (`routing.json`): `loadRoutingDefinition(filePath)` in `tools/json_router.js` reads directly from the local filesystem with `fs.readFileSync`. There is no extension point.
2. Mappings (JSONata / JSON): `oci_object_storage_mapping_source.js` implements a bespoke `{ supports(destination), async load({mappingKey, target}) }` interface assembled by `mapping_loader.js`. The OCI SDK `getObject` function is injected as a raw closure, not via a named interface.
3. Envelope source (input data): `source_loader.js` dispatches on `definition.source.type` to `file_source_adapter.js` or `oci_object_storage_source_adapter.js` — this is the only path that already uses a proper adapter pattern.

In the Fn (`fn/router_passthrough/router_core.js`) the routing definition and mapping are loaded inline via a different ad-hoc OCI Object Storage implementation that is not shared with the CLI. Both the CLI and Fn duplicate OCI SDK client construction.

The item asks for a single `ContentSourceAdapter` interface in the router core library with two built-in implementations (filesystem, OCI Object Storage). All three loading paths (routing definition, mappings, envelope source) are refactored to go through this interface. CLI and Fn select the adapter from configuration.

**Technical approach**

Define `ContentSourceAdapter` with one method: `async readContent(key)` returning a string. Ship `FileSystemContentSourceAdapter` (wraps `fs.readFile`) and `OciObjectStorageContentSourceAdapter` (wraps OCI SDK `getObject` with retry). Refactor `loadRoutingDefinition` to accept an optional adapter; the existing file-path signature stays as a convenience wrapper that uses `FileSystemContentSourceAdapter`. Refactor `oci_object_storage_mapping_source.js` to accept a `ContentSourceAdapter` instead of a raw `getObject` closure. Refactor the Fn `router_core.js` to construct an `OciObjectStorageContentSourceAdapter` and pass it to the shared loading functions rather than duplicating inline loading logic. Add `--routing-source` flag to the CLI (or extend `--routing` to accept `oci://bucket/...` URIs) to select the adapter.

**Dependencies**

Depends on Sprint 29 (CLI and Fn execution parity, SLI-48) which is Done.

**Compatibility notes**

`loadRoutingDefinition(filePath)` must remain callable with a single string argument (backward-compatible). Existing callers in tests and CLI should not require changes unless they test the loading path directly. The Fn `router_core.js` inline loading is replaced by the shared adapter; the env-var contract (`SLI_ROUTING_BUCKET`, `SLI_ROUTING_OBJECT`, `SLI_MAPPING_BUCKET`) is preserved.

**Testing strategy**

Unit tests verify each adapter implementation in isolation (filesystem read, OCI adapter with injected mock), and verify that `loadRoutingDefinition`, `oci_object_storage_mapping_source`, and the Fn loader all correctly delegate to the injected adapter. Existing unit tests must continue to pass (regression scope: router).

**Risks / concerns**

The Fn `router_core.js` copies of `loadRoutingDefinitionFromObject` and the mapping functions come from `fn/router_passthrough/lib/` which are separate copies of the tools library. The refactor must be applied to both `tools/` and `fn/router_passthrough/lib/`. Scope may expand if the lib copies have diverged significantly — this should be assessed during design elaboration.

**Feasibility**

High. All affected code is in JavaScript/Node.js with no external framework coupling. The interface surface is small (`readContent(key)`). The main risk is the dual-copy library in `fn/router_passthrough/lib/`.

**Estimated complexity:** Moderate.

**Prerequisites met:** Yes. Sprint 29 is Done.

**Open questions**

1. Are `fn/router_passthrough/lib/` files in sync with `tools/`? If they have diverged, should we synchronise them as part of this sprint or raise a separate backlog item?

**Recommended design focus areas**

- Define the `ContentSourceAdapter` interface contract precisely before coding.
- Decide whether `source_loader.js` (envelope source) is refactored to use the same interface or kept separate (its API is different: streaming multiple items, not single reads).
- Clarify CLI flag design: new `--routing-source oci://...` flag vs extended `--routing oci://...` URI handling.

**Readiness for design phase:** Ready, pending answer to open question 1 above.
