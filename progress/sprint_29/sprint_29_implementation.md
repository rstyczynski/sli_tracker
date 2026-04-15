# Sprint 29 — Implementation (SLI-48)

## Status: DONE

## Delivered changes

- Added runtime-managed single-envelope execution in `tools/router_runtime.js` via `runEnvelope(...)`.
- Extended local runtime assembly to include `oci_monitoring` and `oci_logging` destination adapters in addition to file-system and OCI Object Storage delivery.
- Changed `tools/json_router_cli.js` single-envelope mode to execute the runtime delivery path instead of preview-only `routeTransformAll(...)`.
- Updated router CLI unit tests to assert real file delivery for single-envelope and `stdin` execution.
- Updated pipeline CLI unit tests to assert transformed input is routed and written through file-system destinations.
- Updated the CLI OCI integration test to verify real routed delivery into OCI Object Storage after loading the mapping from OCI Object Storage.

## Notes

- Batch `--source-dir/--output-dir` behavior was left intact for local bulk exercises.
- The parity fix closes the main functional gap that made single-envelope CLI a preview-only special case.
