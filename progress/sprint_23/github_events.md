# Sprint 23 — GitHub Event Routing

Documents the `X-GitHub-Event` types received from the `rstyczynski/sli_tracker` repository
webhook and their Object Storage destinations as of 2026-04-12.

Source: `tests/fixtures/fn_router_passthrough/routing.json` (loaded into
`sli-router-passthrough-dev-bucket/config/routing.json` at deploy time).

---

## Routing table

All routes use `passthrough.jsonata` (identity transform) and `mode: exclusive, priority: 40`.
The two catch-all routes have lower priorities and no `X-GitHub-Event` constraint.

| X-GitHub-Event | Route id | Object Storage prefix | Added |
| --- | --- | --- | --- |
| `ping` | `github_ping_to_bucket` | `ingest/github/ping/` | sprint 23 initial |
| `push` | `github_push_to_bucket` | `ingest/github/push/` | sprint 23 initial |
| `pull_request` | `github_pull_request_to_bucket` | `ingest/github/pull_request/` | sprint 23 initial |
| `check_suite` | `github_check_suite_to_bucket` | `ingest/github/check_suite/` | sprint 23 initial |
| `workflow_run` | `github_workflow_run_to_bucket` | `ingest/github/workflow_run/` | sprint 23 initial |
| `workflow_job` | `github_workflow_job_to_bucket` | `ingest/github/workflow_job/` | sprint 23 initial |
| `check_run` | `github_check_run_to_bucket` | `ingest/github/check_run/` | sprint 23 post-audit |
| `deployment` | `github_deployment_to_bucket` | `ingest/github/deployment/` | sprint 23 post-audit |
| `deployment_status` | `github_deployment_status_to_bucket` | `ingest/github/deployment_status/` | sprint 23 post-audit |
| _(absent)_ | `no_github_event_to_bucket` | `ingest/no_github_event/` | sprint 23 initial |
| _(any unmatched)_ | `passthrough_to_object_storage` | `ingest/` | sprint 23 initial |

Dead-letter destination (routing failure): `ingest/dead_letter/`

---

## Post-audit discovery (2026-04-12)

Inspecting live `ingest/` objects (catch-all prefix) revealed two event types that were
arriving but had no specific route:

| Event type | Objects found | Payload top-level keys | Context |
| --- | --- | --- | --- |
| `check_run` | 65 | `check_run`, `action` | Fired by GitHub Actions per job step; distinct from `check_suite` |
| `deployment` | 14 | `deployment`, `workflow`, `workflow_run`, `action` | Fired when a new deployment is created (precedes `deployment_status`) |
| `deployment_status` | 1 | `deployment_status`, `deployment`, `check_run`, `workflow`, `workflow_run`, `action` | Fired when deployment state changes (success/failure) |

All three routes were added in commit `0d9c2b6`. Objects already in `ingest/` before the fix
remain there; new webhooks route to the correct `ingest/github/{event}/` prefix.

---

## Event relationships

```
push / schedule / workflow_dispatch
  └── workflow_run          (one per workflow execution)
        └── workflow_job    (one per job within the run)
              └── check_suite  (one per commit/ref)
                    └── check_run   (one per job step / action)

push / workflow_run
  └── deployment            (created when a deploy step triggers)
        └── deployment_status  (created/success/failure/inactive)
```

`check_run` and `deployment`/`deployment_status` are the higher-frequency events in this
repository because the CI model workflows run on a schedule and deploy to `model-env-*`
environments on every run.

---

## Adding a new event type

1. Add an adapter entry to `routing.json`:
   ```json
   "oci_object_storage:github_<event>": {
     "bucket": "REPLACED_AT_RUNTIME",
     "prefix": "ingest/github/<event>/"
   }
   ```
2. Add a route (priority 40, exclusive):
   ```json
   {
     "id": "github_<event>_to_bucket",
     "mode": "exclusive",
     "priority": 40,
     "match": { "headers": { "x-github-event": "<event>" } },
     "transform": { "mapping": "./passthrough.jsonata" },
     "destination": { "type": "oci_object_storage", "name": "github_<event>" }
   }
   ```
3. Upload `routing.json` to `sli-router-passthrough-dev-bucket/config/routing.json`.
4. Add a unit assertion in `tests/unit/test_fn_passthrough_router.sh`.
5. Commit and push.

To discover unrouted event types accumulating in `ingest/`:

```bash
./tools/get_ingest_object.sh <object-name>   # fetch a single object
# or list + sample:
oci os object list --bucket-name sli-router-passthrough-dev-bucket \
  --prefix "ingest/" --delimiter "/" --all \
  | jq -r '.data[].name' | while read obj; do
    oci os object get --bucket-name sli-router-passthrough-dev-bucket \
      --name "$obj" --file - 2>/dev/null \
    | jq -r '[keys[]] | map(select(. != "action" and . != "repository" and . != "sender")) | sort | join(",")'
  done | sort | uniq -c | sort -rn
```
