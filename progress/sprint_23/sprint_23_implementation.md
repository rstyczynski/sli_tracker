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
    "oci_object_storage:dead_letter": {
      "bucket": "REPLACED_AT_RUNTIME",
      "prefix": "ingest/dead_letter/"
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
  "dead_letter": {
    "type": "oci_object_storage",
    "name": "dead_letter"
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

**Schema:** validated by **`tools/schemas/json_router_definition.schema.json`**. **Envelope:** JSON with optional **`body`**, **`headers`**, **`endpoint`**, **`source_meta`**.

**Why GitHub-shaped JSON sometimes still lands under `ingest/`:** GitHub routes match **`match.headers["x-github-event"]`**. If the caller (API Gateway integration, curl test, etc.) posts **only the webhook JSON body** and does **not** copy GitHub’s **`X-GitHub-Event`** HTTP header into the envelope’s **`headers`** map, the router never matches the GitHub routes and the catch-all **`passthrough_to_object_storage`** wins — that is **correct routing**, not a mis-route. Re-run **`tests/unit/test_fn_passthrough_router.sh`**: the same push fixture with a header goes to **`ingest/github/push/`**; without a header it goes to **`ingest/`**.

**Other event types** (for example **`issues`**, **`repository`**) are not listed; they match the catch-all and land under **`ingest/`** until you add routes.

**Errors and dead letter:** **`dead_letter`** points at **`oci_object_storage` / `dead_letter`** → prefix **`ingest/dead_letter/`**. **`processEnvelope`** (`tools/json_router.js`) writes **`{ error, envelope }`** there on failures when **`onDeadLetter`** is set (`router_core.js` enables it from **`definition.dead_letter`**). Examples: **ambiguous exclusive match**, **JSONata transform failure**, **mapping load failure**, **no adapter for a destination**, or **no route matched** when you temporarily remove the catch-all. With the catch-all route above, a normal envelope **always** matches at least one route, so mis-classified GitHub traffic (missing **`X-GitHub-Event`**) is **not** a dead-letter case — it is stored under **`ingest/`** by design. If the handler throws outside **`processEnvelope`**, **`func.js`** still returns **`{ "status": "error", … }`** without an object write.

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

**`list_github_ingest_prefixes.sh`** prints the newest objects under each **`ingest/github/<event>/`** prefix, a **`ingest/dead_letter/`** section, then a merged timeline: **`ingest/github/*`** plus **`ingest/dead_letter/*`** plus flat **`ingest/<file>`** keys (exactly one segment after **`ingest/`**, e.g. **`ingest/fn-….json`**). A single list on **`ingest/`** alone is not used for that merged block because the API’s first page is often dominated by **`fn-*`** keys and omits deeper prefixes.

## Tests

- **`tests/unit/test_fn_passthrough_router.sh`** — Stubbed **`putObject`**; asserts paths for ping / push / workflow_run / pull_request and default **`ingest/`**.
- **`tests/integration/test_fn_apigw_object_storage_passthrough.sh`** — Verifies default **`ingest/`** and **`ingest/github/ping/`** after a synthetic ping post.

See **`sprint_23_tests.md`** for quality gate logs.
