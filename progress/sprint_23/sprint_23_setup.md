# Sprint 23 — Setup (YOLO)

## Contract

RUP simplified manager (`rup_manager_simplified.md`): YOLO mode — self-approve design, no blocking waits. Quality gates: Phase A new-code (`Test: unit, integration` with `--new-only` manifest), Phase B regression unit via `progress/sprint_23/regression_tests.manifest`. Logs under `progress/sprint_23/test_run_*.log` and `./logs/`.

Deliver SLI-36: route GitHub webhook deliveries to distinct Object Storage prefixes using the existing `X-GitHub-Event` header and exclusive routes by priority; keep non-GitHub envelopes on the existing `ingest/` prefix. Synthetic bodies live in-repo under `tests/fixtures/github_webhook_samples/`. Operator tooling: `tools/list_github_ingest_prefixes.sh`.

## Analysis

**Feasibility:** Router already supports `match.headers` (normalized to lower-case keys). `router_core` previously injected `OCI_INGEST_BUCKET` only into `oci_object_storage:raw_ingest`; additional adapter keys need the same bucket at runtime — fixed by iterating all `oci_object_storage:*` adapter entries.

**Compatibility:** Default route remains `raw_ingest` / `ingest/` at priority 0 so existing integration payloads without GitHub headers behave as before. `cycle_apigw_router_passthrough.sh` continues to upload `tests/fixtures/fn_router_passthrough/routing.json`.

**Open questions (deferred):** Additional GitHub event types can be added as new routes + adapter entries; unknown `X-GitHub-Event` values still fall through to `ingest/`.
