# Sprint 18 Setup — SLI-26 JSON Transformer

## Contract

Rules understood: YOLO mode — all outputs self-approved, no review gates, 10-min per phase limit.

**Responsibilities:**
- Deliver a Node.js library (`tools/json_transformer.js`) and CLI (`tools/json_transform_cli.js`) that apply a JSONata mapping file to transform any source JSON document to a target JSON document.
- Scope is strictly the library + CLI + unit tests. No OCI calls, no GitHub API calls, no integration tests.

**Constraints:**
- Use the `jsonata` npm package (add to `package.json`).
- Mapping definition stored in a JSON file; swapping the file changes the schema — no code changes needed.
- CLI reads source JSON from a file or stdin; writes result to stdout; errors to stderr with non-zero exit.
- Library is a pure synchronous module exportable for reuse in an OCI Fn function (next sprint).

**Open questions:** None.

## Analysis

**Backlog item SLI-26 analysed:**

The item asks for a library + CLI that uses JSONata to map one JSON shape to another. The canonical use cases are:
1. `/health` or `/status` API response → OCI metric datapoint
2. GitHub `workflow_run` webhook payload → OCI log entry

**Feasibility:** Straightforward. JSONata is a mature JS library. The mapping file wraps a single JSONata expression in a small JSON envelope (`version`, `description`, `expression`). The library has two public functions: `loadMapping(file)` and `transform(source, mapping)`. The CLI is a thin shell around those two.

**Compatibility:** `package.json` currently has `"type": "commonjs"` — use `require()`/`module.exports` consistent with other tools. JSONata `v2.x` uses a Promise-based `evaluate()`; all async handling is internal to the library; the CLI awaits the result.

**Open questions:** None. Item is well-scoped. No design decisions deferred.
