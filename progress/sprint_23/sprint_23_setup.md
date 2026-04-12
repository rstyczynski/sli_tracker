# Sprint 23 — Setup (YOLO)

## Contract

RUP simplified manager (`rup_manager_simplified.md`): YOLO mode — self-approve design, no blocking waits. Quality gates: Phase A new-code (`Test: unit, integration` with `--new-only` manifest), Phase B regression unit via `progress/sprint_23/regression_tests.manifest`. Logs under `progress/sprint_23/test_run_*.log` and `./logs/`.

Deliver SLI-36: route GitHub webhook deliveries to distinct Object Storage prefixes using the existing `X-GitHub-Event` header and exclusive routes by priority (each event family is a **static** adapter + route in `routing.json`, including **`check_suite`** → **`ingest/github/check_suite/`**); route POSTs **without** `X-GitHub-Event` to **`ingest/no_github_event/`** via **`match.headers_absent`** (priority 5); keep unlisted GitHub event types that still send the header on **`ingest/`** via **`raw_ingest`** (priority 0). Synthetic bodies live in-repo under `tests/fixtures/github_webhook_samples/`. Operator tooling: `tools/list_github_ingest_prefixes.sh`.

## Analysis

**Feasibility:** Router already supports `match.headers` (normalized to lower-case keys). `router_core` previously injected `OCI_INGEST_BUCKET` only into `oci_object_storage:raw_ingest`; additional adapter keys need the same bucket at runtime — fixed by iterating all `oci_object_storage:*` adapter entries.

**Compatibility:** Integration POSTs without `X-GitHub-Event` now land under **`ingest/no_github_event/`** (re-upload **`routing.json`** after deploy). **`raw_ingest` / `ingest/`** remains for envelopes that carry **`x-github-event`** but do not match a named GitHub route. `cycle_apigw_router_passthrough.sh` continues to upload `tests/fixtures/fn_router_passthrough/routing.json`.

**Open questions (deferred):** Additional GitHub event types can be added as new routes + adapter entries; unknown `X-GitHub-Event` values still fall through to **`ingest/`**.
