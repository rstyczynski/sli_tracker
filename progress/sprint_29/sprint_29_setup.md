# Sprint 29 — Setup (SLI-48)

## Status: IN PROGRESS

## Sprint parameters

| Field | Value |
|-------|-------|
| Sprint | 29 |
| Mode | YOLO |
| Test | unit, integration |
| Regression | unit, integration |
| Regression scope | router |
| Backlog item | SLI-48 |

## Contract

- Work only on router CLI/runtime parity for `SLI-48`.
- Keep existing user edits in unrelated files intact.
- Treat the current CLI/Fn mismatch as the defect to remove, not as API to preserve.
- Limit behavior changes to making CLI execute the same delivery path as Fn for equivalent routing definitions.

## Analysis

### Problem

- `tools/json_router_cli.js` has two modes:
  - source-driven runtime path using `runFromRoutingFile(...)`
  - single-envelope preview path using `routeTransformAll(...)`
- `fn/router_passthrough/router_core.js` always uses `processEnvelope(...)` plus destination handlers.
- Result: the same routing definition behaves differently depending on whether it is invoked from the CLI or from Fn.

### Compatibility constraints

- Existing batch CLI behavior must keep working.
- Local file-system destinations remain the main offline execution technique.
- OCI-backed mappings and OCI destinations must still work when the routing definition requires them.
- Error handling must continue to honor `dead_letter` configuration.

### Expected outcome

1. Single-envelope CLI execution uses the same routed delivery path as the Function wrapper.
2. CLI returns routed delivery results instead of preview-only route/output lists.
3. Router tests move from preview assertions to actual delivery assertions.
