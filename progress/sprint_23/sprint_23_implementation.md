# Sprint 23 — Implementation (SLI-36)

## Bugs

Post-sprint code review (2026-04-12) found three hardcoded-value issues; full write-up in
[sprint_23_bugs.md](sprint_23_bugs.md). Short summary:

- **BUG-1** (`x-github-event` in `json_router.js:114`) — fold-in fix, core library.
- **BUG-2** (`passthrough.jsonata` basename check in `router_core.js:229`) — promoted to backlog.
- **BUG-3** (`oci_object_storage:raw_ingest` key requirement in `router_core.js:148`) — deferred.

## Code and config

- **`fn/router_passthrough/router_core.js`** — `applyIngestBucketToRoutingObject` assigns `OCI_INGEST_BUCKET` to every `oci_object_storage:*` adapter entry so all routes resolve a real bucket name at runtime (the JSON still uses placeholder `REPLACED_AT_RUNTIME` in-repo; the Function overwrites it on load). **`mergeHttpGatewayHeadersIntoEnvelope`** copies API Gateway client headers from the Fn FDK’s **`ctx.httpGateway.headers`** (GitHub’s **`X-Github-Event`**, etc.) into **`envelope.headers`** when the POST body is raw JSON so header-based routes match in production.
- **`fn/router_passthrough/lib/json_router.js`** (and **`tools/json_router.js`**) — **`matchesRoute`** supports **`match.headers_absent`**: an array of header names that must be missing or empty (after normalization) so envelopes without **`X-GitHub-Event`** can be routed exclusively to **`ingest/no_github_event/`** at priority **5**, above the **`raw_ingest`** catch-all (**priority 0**).
- **`fn/router_passthrough/func.js`** — Passes **`(input, ctx)`** into **`runRouter(input, { fdkContext: ctx })`** so gateway headers are available.
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
    "oci_object_storage:no_github_event": {
      "bucket": "REPLACED_AT_RUNTIME",
      "prefix": "ingest/no_github_event/"
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
    },
    "oci_object_storage:github_check_suite": {
      "bucket": "REPLACED_AT_RUNTIME",
      "prefix": "ingest/github/check_suite/"
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
      "id": "github_check_suite_to_bucket",
      "mode": "exclusive",
      "priority": 40,
      "match": {
        "headers": {
          "x-github-event": "check_suite"
        }
      },
      "transform": {
        "mapping": "./passthrough.jsonata"
      },
      "destination": {
        "type": "oci_object_storage",
        "name": "github_check_suite"
      }
    },
    {
      "id": "no_github_event_to_bucket",
      "mode": "exclusive",
      "priority": 5,
      "match": {
        "headers_absent": ["x-github-event"]
      },
      "transform": {
        "mapping": "./passthrough.jsonata"
      },
      "destination": {
        "type": "oci_object_storage",
        "name": "no_github_event"
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

**GitHub headers and raw JSON bodies:** GitHub sends **`X-Github-Event`** on the HTTP request. OCI API Gateway forwards those on the Fn invocation as **`Fn-Http-H-*`** headers; the FDK exposes the original names on **`ctx.httpGateway.headers`**. **`router_core`** merges those into **`envelope.headers`** before routing (without overwriting non-empty envelope headers). **Offline tests** that call **`runRouter`** with a bare object and **no** **`fdkContext`** still behave like before: add **`headers`** to the envelope JSON yourself, or pass a mock **`fdkContext`** (see **`tests/unit/test_fn_passthrough_router.sh`**). When **`x-github-event`** is missing or empty after merge, the **`no_github_event_to_bucket`** route (priority **5**) stores under **`ingest/no_github_event/`** (including auto-generated **`fn-…`** object names when **`source_meta.file_name`** is absent).

**Headers vs what Object Storage receives (successful route):** **`envelope.headers`** (after the merge above) are used only for **route matching** in **`fn/router_passthrough/lib/json_router.js`** (`matchesRoute` / `normalizeHeaders`). They are **not** copied into the object body on a normal delivery. **`routeTransformAll`** runs **`transform(envelope.body, mapping)`**; the Object Storage **`emit`** hook in **`router_core.js`** persists **`JSON.stringify(output)`** — i.e. the **JSONata result of `envelope.body`**, not the full envelope. With **`passthrough.jsonata`** as **`$`**, the stored file is effectively the parsed **body** alone. To persist gateway or client headers in successful ingest objects **today**, put them in the JSON **body** at the source, or change the router so JSONata receives more than **`body`** (code change).

**Other GitHub event types** (for example **`issues`**, **`repository`**) are not given their own adapter yet; they still carry **`X-GitHub-Event`**, so **`headers_absent`** does not match and they fall through to **`raw_ingest`** under **`ingest/`** until you add another static route + adapter pair (same pattern as **`check_suite`**). Optional header-driven prefix templates are **SLI-38** in **`BACKLOG.md`**, not implemented here.

**Errors and dead letter:** **`dead_letter`** points at **`oci_object_storage` / `dead_letter`** → prefix **`ingest/dead_letter/`**. **`processEnvelope`** (`tools/json_router.js`), via **`destination_dispatcher.js`** **`onDeadLetter`**, delivers **`{ error, envelope }`** as the adapter **`output`**, so dead-letter objects include the **full envelope** (including **`headers`**) under **`envelope`**, not only the body. Examples: **ambiguous exclusive match**, **JSONata transform failure**, **mapping load failure**, **no adapter for a destination**, or **no route matched** when you temporarily remove the catch-all. With the routes above, a normal envelope **always** matches at least one route. If the handler throws outside **`processEnvelope`**, **`func.js`** still returns **`{ "status": "error", … }`** without an object write.

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
# Fetch one object body (stdout); use --file path to write instead of piping
./tools/get_ingest_object.sh ingest/github/workflow_run/fn-1775961003716-d1da2413.json | jq .
```

Positional equivalent (same values from **`jq`**):

```bash
NS="$(jq -r '.bucket.namespace // empty' "$STATE_FILE")"
BN="$(jq -r '.bucket.name // empty' "$STATE_FILE")"
./tools/list_github_ingest_prefixes.sh "$NS" "$BN" --limit 5
```

**`list_github_ingest_prefixes.sh`** prints **object names only** (one full path per line, **newest by `time-created` first** within each section, up to **`--limit`**). Sections, in order: **`ingest/github/ping/`**, **`…/push/`**, **`…/workflow_run/`**, **`…/pull_request/`**, **`…/check_suite/`**, **`ingest/dead_letter/`**, **`ingest/no_github_event/`**, then **`ingest/`** (shallow root only; see earlier). Each section is a single **`oci os object list`** with that prefix (list page size capped at **`LIST_CAP=200`** in the script). The **`ingest/`** block uses **`oci os object list --prefix ingest/ --delimiter /`**, so it lists **only** the catch-all **root** keys (**`ingest/<one segment>`** — no further **`/`**), not nested paths like **`ingest/github/...`** (those appear only under the **`ingest/github/<event>/`** sections). If there are no such root objects, the script prints a single **`(no objects at ingest/ root …)`** line.

**`get_ingest_object.sh`** downloads the **raw object body** for one full key (for example a name printed by the list script). It uses the same **`SLI_OS_NAMESPACE`**, **`SLI_INGEST_BUCKET`**, and **`OCI_CLI_PROFILE`**. With no **`--file`**, it uses **`oci os object get --file -`** (body on **stdout**); **`--file /path/to/out.json`** avoids stdout if an **`oci`** wrapper still prints banner text ahead of binary/JSON. Pass **`--help`** for usage.

**`clear_ingest_prefix.sh`** removes objects via **`oci os object bulk-delete`**. With **no** **`--dir`**, the default prefix **`ingest/`** removes the **entire** ingest tree (nested prefixes included). With **`--dir`** (path under **`ingest/`** or starting with **`ingest/`**), the default is **shallow** only: **`--delimiter /`** so only objects **directly** in that folder are deleted, not deeper subpaths; add **`--recursive`** to delete the full subtree under that directory. **`--prefix`** sets a literal prefix and always deletes the **full** subtree under that prefix (use only one of **`--dir`** or **`--prefix`**). Keys outside the effective prefix (e.g. **`config/`**) are untouched. Use **`--dry-run`** first; a real run requires **`--yes`** or **`SLI_CLEAR_INGEST_YES=1`**.

**Stdout before JSON:** If a shell or **`oci`** wrapper prints banner lines to **stdout** ahead of the JSON document, **`jq` fails** on the combined stream. The script **`strip_leading_nonjson`** keeps output from the first line that looks like JSON (starts with **`[`** or **`{`** after optional whitespace). Prefer wrappers that print only to **stderr**, or a non-noisy login profile, so **`oci --query … --raw-output`** stays a single JSON value.

**`jq` filter:** Use **`select(type == "object" and (.name | type == "string"))`**. The older shape **`select(type == "object") and (.name | …)`** is parsed incorrectly by **`jq`** and yields errors like **Cannot index boolean with string "name"** (and the script would show **`(list jq error)`**).

## Tests

- **`tests/unit/test_fn_passthrough_router.sh`** — Stubbed **`putObject`**; asserts paths for ping / push / workflow_run / pull_request and default **`ingest/`**.
- **`tests/integration/test_fn_apigw_object_storage_passthrough.sh`** — Verifies default **`ingest/`** and **`ingest/github/ping/`** after a synthetic ping post.

See **`sprint_23_tests.md`** for quality gate logs.
