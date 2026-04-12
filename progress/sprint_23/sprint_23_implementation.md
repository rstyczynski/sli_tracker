# Sprint 23 — Implementation (SLI-36)

## Code and config

- **`fn/router_passthrough/router_core.js`** — `applyIngestBucketToRoutingObject` assigns `OCI_INGEST_BUCKET` to every `oci_object_storage:*` adapter entry so all routes resolve a real bucket name at runtime (the JSON still uses placeholder `REPLACED_AT_RUNTIME` in-repo; the Function overwrites it on load).
- **`tests/fixtures/fn_router_passthrough/routing.json`** — Canonical routing file in the repository; **`tools/cycle_apigw_router_passthrough.sh`** uploads it to Object Storage as **`config/routing.json`** (unless **`SLI_ROUTING_OBJECT`** overrides the object name).
- **`fn/router_passthrough/func.yaml`** — Version bump when the handler changes so redeploys pick up new code.
- **`tests/fixtures/github_webhook_samples/`** — Synthetic GitHub bodies for unit tests and manual curl replay; see **`README.md`** there.

## Complete routing definition (`config/routing.json`)

Below is the **full** routing JSON shipped with this sprint (matches **`tests/fixtures/fn_router_passthrough/routing.json`**). At deploy time the Function replaces every adapter’s **`bucket`** with **`OCI_INGEST_BUCKET`** from Function configuration.

```json
{
  "adapters": {
    "oci_object_storage:raw_ingest": {
      "bucket": "REPLACED_AT_RUNTIME",
      "prefix": "ingest/"
    },
    "oci_object_storage:github_ping": {
      "bucket": "REPLACED_AT_RUNTIME",
      "prefix": "ingest/github/ping/"
    },
    "oci_object_storage:github_push": {
      "bucket": "REPLACED_AT_RUNTIME",
      "prefix": "ingest/github/push/"
    },
    "oci_object_storage:github_workflow_run": {
      "bucket": "REPLACED_AT_RUNTIME",
      "prefix": "ingest/github/workflow_run/"
    },
    "oci_object_storage:github_pull_request": {
      "bucket": "REPLACED_AT_RUNTIME",
      "prefix": "ingest/github/pull_request/"
    }
  },
  "routes": [
    {
      "id": "github_ping_to_bucket",
      "mode": "exclusive",
      "priority": 40,
      "match": {
        "headers": {
          "x-github-event": "ping"
        }
      },
      "transform": {
        "mapping": "./passthrough.jsonata"
      },
      "destination": {
        "type": "oci_object_storage",
        "name": "github_ping"
      }
    },
    {
      "id": "github_push_to_bucket",
      "mode": "exclusive",
      "priority": 40,
      "match": {
        "headers": {
          "x-github-event": "push"
        }
      },
      "transform": {
        "mapping": "./passthrough.jsonata"
      },
      "destination": {
        "type": "oci_object_storage",
        "name": "github_push"
      }
    },
    {
      "id": "github_workflow_run_to_bucket",
      "mode": "exclusive",
      "priority": 40,
      "match": {
        "headers": {
          "x-github-event": "workflow_run"
        }
      },
      "transform": {
        "mapping": "./passthrough.jsonata"
      },
      "destination": {
        "type": "oci_object_storage",
        "name": "github_workflow_run"
      }
    },
    {
      "id": "github_pull_request_to_bucket",
      "mode": "exclusive",
      "priority": 40,
      "match": {
        "headers": {
          "x-github-event": "pull_request"
        }
      },
      "transform": {
        "mapping": "./passthrough.jsonata"
      },
      "destination": {
        "type": "oci_object_storage",
        "name": "github_pull_request"
      }
    },
    {
      "id": "passthrough_to_object_storage",
      "mode": "exclusive",
      "priority": 0,
      "transform": {
        "mapping": "./passthrough.jsonata"
      },
      "destination": {
        "type": "oci_object_storage",
        "name": "raw_ingest"
      }
    }
  ]
}
```

**Schema:** validated by **`tools/schemas/json_router_definition.schema.json`**. **Envelope:** JSON with optional **`body`**, **`headers`**, **`endpoint`**, **`source_meta`**; GitHub traffic should include **`X-GitHub-Event`** in **`headers`**. Other GitHub event types not listed above still match the catch-all route and land under **`ingest/`** until you add routes.

## Operator CLI — bucket and namespace from scaffold state

Do not hand-edit the ingest bucket name. After **`tools/cycle_apigw_router_passthrough.sh`** (or any run that wrote **`oci_scaffold/state-<NAME_PREFIX>.json`**), read **`.bucket.namespace`** and **`.bucket.name`** from that file — the same fields as **`tests/integration/test_fn_apigw_object_storage_passthrough.sh`**.

```bash
cd "$(git rev-parse --show-toplevel)"
REPO_ROOT="$(pwd)"
NAME_PREFIX="${SLI_FN_APIGW_ROUTER_PREFIX:-sli-router-passthrough-dev}"
STATE_FILE="${REPO_ROOT}/oci_scaffold/state-${NAME_PREFIX}.json"
test -f "$STATE_FILE" || { echo "missing state file: $STATE_FILE (run cycle_apigw_router_passthrough.sh first)" >&2; exit 1; }
export SLI_OS_NAMESPACE="$(jq -r '.bucket.namespace // empty' "$STATE_FILE")"
export SLI_INGEST_BUCKET="$(jq -r '.bucket.name // empty' "$STATE_FILE")"
export OCI_CLI_PROFILE="${OCI_CLI_PROFILE:-DEFAULT}"
test -n "$SLI_OS_NAMESPACE" && test -n "$SLI_INGEST_BUCKET" || { echo "state file missing bucket fields" >&2; exit 1; }
./tools/list_github_ingest_prefixes.sh --limit 5
```

Positional equivalent (same values from **`jq`**):

```bash
NS="$(jq -r '.bucket.namespace // empty' "$STATE_FILE")"
BN="$(jq -r '.bucket.name // empty' "$STATE_FILE")"
./tools/list_github_ingest_prefixes.sh "$NS" "$BN" --limit 5
```

**`list_github_ingest_prefixes.sh`** prints the newest objects (by **`timeCreated`**) under each **`ingest/github/<event>/`** prefix, then a short sample of other **`ingest/*`** keys (excluding **`ingest/github/`**) for default-traffic inspection.

## Tests

- **`tests/unit/test_fn_passthrough_router.sh`** — Stubbed **`putObject`**; asserts paths for ping / push / workflow_run / pull_request and default **`ingest/`**.
- **`tests/integration/test_fn_apigw_object_storage_passthrough.sh`** — Verifies default **`ingest/`** and **`ingest/github/ping/`** after a synthetic ping post.

See **`sprint_23_tests.md`** for quality gate logs.
