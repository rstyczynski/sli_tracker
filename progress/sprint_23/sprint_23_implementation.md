# Sprint 23 — Implementation (SLI-36)

## Code and config

- **`fn/router_passthrough/router_core.js`** — `applyIngestBucketToRoutingObject` now assigns `OCI_INGEST_BUCKET` to every `oci_object_storage:*` adapter entry so additional GitHub routes resolve a real bucket name.
- **`tests/fixtures/fn_router_passthrough/routing.json`** — Operator-facing routing document uploaded to Object Storage by `tools/cycle_apigw_router_passthrough.sh` as `config/routing.json` (unless overridden). Defines adapters and routes below.
- **`fn/router_passthrough/func.yaml`** — Version bump for redeploy after handler change.
- **`tests/fixtures/github_webhook_samples/`** — Synthetic GitHub bodies used by unit tests and for manual curl replay; see `README.md` in that directory.

## Routing document (`config/routing.json`)

The file is standard JSON validated by `tools/schemas/json_router_definition.schema.json`.

**Adapters (all share one bucket at runtime; prefixes differ):**

- `oci_object_storage:raw_ingest` → prefix `ingest/`
- `oci_object_storage:github_ping` → `ingest/github/ping/`
- `oci_object_storage:github_push` → `ingest/github/push/`
- `oci_object_storage:github_workflow_run` → `ingest/github/workflow_run/`
- `oci_object_storage:github_pull_request` → `ingest/github/pull_request/`

**Routes (exclusive, JSONata `./passthrough.jsonata` on each):**

1. `github_ping_to_bucket` — `match.headers["x-github-event"]` equals `ping`, priority 40, destination `oci_object_storage` / `github_ping`.
2. `github_push_to_bucket` — header value `push`, same priority, destination `github_push`.
3. `github_workflow_run_to_bucket` — `workflow_run`.
4. `github_pull_request_to_bucket` — `pull_request`.
5. `passthrough_to_object_storage` — no header match, priority 0, destination `raw_ingest` (legacy and non-GitHub traffic).

GitHub sends additional event types (for example `issues`, `repository`). Those are **not** listed here; they continue to match the catch-all and land under `ingest/` until new routes are added.

**Envelope shape** expected by the public Function (unchanged): JSON with optional `body`, `headers`, `endpoint`, `source_meta`. GitHub API Gateway integrations should forward `X-GitHub-Event` into `headers` when building the envelope.

## Operator CLI — latest objects per GitHub prefix

Script: **`tools/list_github_ingest_prefixes.sh`**

Requires OCI CLI auth and Object Storage namespace + bucket name (the ingest bucket created by the router stack).

```bash
cd "$(git rev-parse --show-toplevel)"

export OCI_CLI_PROFILE="${OCI_CLI_PROFILE:-DEFAULT}"
export SLI_OS_NAMESPACE="$(oci os ns get --query data --raw-output)"
export SLI_INGEST_BUCKET="<bucket-from-state-or-console>"

./tools/list_github_ingest_prefixes.sh --limit 5
```

Positional form:

```bash
./tools/list_github_ingest_prefixes.sh "$SLI_OS_NAMESPACE" "$SLI_INGEST_BUCKET" --limit 5
```

The script prints the newest objects (by `timeCreated`) under each `ingest/github/<event>/` prefix, then a short sample of other `ingest/*` keys (excluding `ingest/github/`) for default-traffic inspection.

## Tests

- **`tests/unit/test_fn_passthrough_router.sh`** — Stubbed `putObject`; asserts paths for ping/push/workflow_run/pull_request and default `ingest/`.
- **`tests/integration/test_fn_apigw_object_storage_passthrough.sh`** — Deploys or reuses API Gateway + Fn; verifies default ingest and `ingest/github/ping/` after posting a synthetic ping body.

See **`sprint_23_tests.md`** for quality gate logs.
