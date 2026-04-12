# Synthetic GitHub webhook bodies

Minimal JSON bodies shaped like GitHub webhook delivery payloads. They are **not** live secrets; use them with **`X-GitHub-Event`** (and optional **`X-GitHub-Delivery`**) when exercising the public router or unit tests.

- **`ping.json`** — use header `X-GitHub-Event: ping`
- **`push.json`** — `X-GitHub-Event: push`
- **`workflow_run.json`** — `X-GitHub-Event: workflow_run`
- **`pull_request.json`** — `X-GitHub-Event: pull_request`

The router fixture `tests/fixtures/fn_router_passthrough/routing.json` routes the samples above plus **`X-GitHub-Event: workflow_job`**, **`check_suite`**, and other listed GitHub headers to separate Object Storage prefixes under **`ingest/github/<event>/`**.
