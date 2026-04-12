# Sprint 23 — Design (YOLO)

## Goal

Persist GitHub webhook traffic under `ingest/github/<event>/` when `X-GitHub-Event` matches a configured route; all other envelopes continue to use `ingest/` (same bucket).

## Routing rules

- **Match:** `match.headers` with `x-github-event` (any casing in JSON; router compares lower-cased envelope headers).
- **Mode:** `exclusive` with **priority 40** for GitHub-specific routes and **priority 0** for the catch-all passthrough route so the highest-priority matching route wins without ambiguity.
- **Transform:** unchanged `./passthrough.jsonata` for every route.
- **Destinations:** separate logical names (`github_ping`, `github_push`, `github_workflow_run`, `github_pull_request`, `raw_ingest`) each mapped to an `oci_object_storage:*` adapter with its own `prefix`.

## Runtime

`applyIngestBucketToRoutingObject` sets `bucket` on **every** `oci_object_storage:*` adapter from `OCI_INGEST_BUCKET`.

## Operator experience

Document in `sprint_23_implementation.md` how to list recent objects per prefix using `tools/list_github_ingest_prefixes.sh`.

### Testing Strategy

- **Unit:** Extend `tests/unit/test_fn_passthrough_router.sh` to assert object key prefixes for `ping`, `push`, `workflow_run`, and `pull_request` headers using fixtures from `tests/fixtures/github_webhook_samples/`, plus unchanged default `ingest/` behavior.
- **Integration:** Extend `tests/integration/test_fn_apigw_object_storage_passthrough.sh` with a second POST carrying `X-GitHub-Event: ping` and verify the object exists under `ingest/github/ping/`. Cycle script re-uploads updated `routing.json`. Default `FN_FORCE_DEPLOY=true` so CI deploys `func.yaml` bump after handler changes.

## Test Specification

| ID | Level | Script | Focus |
|----|-------|--------|--------|
| UT-FN-GH-1 | unit | `test_fn_passthrough_router.sh` | Header-based prefixes + default ingest |
| IT-FN-GH-1 | integration | `test_fn_apigw_object_storage_passthrough.sh` | Live ping path under `ingest/github/ping/` |

### Traceability

| Test ID | Backlog |
|---------|---------|
| UT-FN-GH-1 | SLI-36 |
| IT-FN-GH-1 | SLI-36 |
