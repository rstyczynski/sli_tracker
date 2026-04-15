# Sprint 29 — Design (SLI-48)

## Problem

Router CLI is not universal. Batch mode and source-driven routing execute real destination adapters, but single-envelope CLI mode only previews transformed routes. Fn always performs delivery. That split violates the intended model where Fn and CLI are wrappers around the same router core.

## Design decisions

### 1. Introduce runtime-managed single-envelope execution

Extend `tools/router_runtime.js` with a helper that:
- loads the same routing definition runtime used by batch/source execution
- accepts one envelope object
- invokes `processEnvelope(...)` with runtime-managed `loadMapping`, `onRoute`, and `onDeadLetter`
- returns the same routed/dead-letter result structure produced by core router processing

This keeps runtime assembly in one place instead of rebuilding adapter logic inside the CLI.

### 2. Expand local runtime adapters to match Fn delivery capabilities

`tools/router_runtime.js` currently assembles only:
- file-system adapter
- OCI Object Storage adapter

It must also assemble:
- OCI Logging adapter
- OCI Monitoring adapter

using the same adapter contracts already used by the Function path. CLI and Fn may still differ in credential/bootstrap decoration, but not in available destination types.

### 3. Make `tools/json_router_cli.js` a thin wrapper

Single-envelope CLI flow will:
- load/parse one envelope from file or `stdin`
- delegate execution to runtime-managed single-envelope processing
- stop calling `routeTransformAll(...)` directly for delivery mode

The existing source-defined and batch flows should also continue to use runtime-managed processing paths.

### 4. Preserve offline operator workflows

Local file-to-file exercises remain valid:
- `file_system` destinations still write under operator-provided output roots
- `dead_letter` still writes local JSON payloads

The behavioral change is that single-envelope CLI now performs those writes instead of only previewing the route list.

### Testing Strategy

- Update unit tests for `json_router_cli` so single-envelope and `stdin` cases assert actual destination writes and routed status.
- Update CLI pipeline tests so transformed input piped into router CLI exercises real delivery, not preview JSON.
- Update the existing CLI OCI integration test to assert real destination execution instead of preview-only output.
- Run router-scoped unit and integration regression after the new CLI path passes its new-code gates.

## Test Specification

### UT-SLI48-1 — Single-envelope CLI executes file destination

Run `tools/json_router_cli.js` with a local routing definition containing a `file_system` destination and one input envelope. Expect:
- command exit success
- JSON result with `status: "routed"`
- file written to the configured local destination

### UT-SLI48-2 — Stdin CLI executes the same file destination path

Pipe the same envelope through `stdin`. Expect the same routed status and output file creation.

### UT-SLI48-3 — Transform CLI piped into router CLI performs delivery

Pipe `json_transform_cli.js` output into `json_router_cli.js`. Expect routed status and a delivered file rather than a preview-only route list.

### IT-SLI48-1 — CLI single-envelope execution honors OCI mapping loader and destination adapter

Run single-envelope CLI with routing that resolves mapping from OCI Object Storage and delivers to an OCI destination. Expect success through the real adapter path, not preview output.
