# Sprint 26 — Implementation (SLI-41)

## Status: DONE

## Summary

Delivered configuration-only SLI-41 now that SLI-42 registers `oci_monitoring` from `routing.json` keys.

## Configuration (required reading)

This sprint is **driven by configuration in Object Storage** plus **Fn environment variables**. Handler code (Sprint 25 + **SLI-41-2**) loads routing and JSONata from the bucket at runtime (Resource Principal), not from the Docker image alone.

## Configuration file contents (verbatim, Sprint 26)

The blocks below are **byte-for-byte** what lives in the repository under `tests/fixtures/fn_router_passthrough/` and is uploaded by `tools/cycle_apigw_router_passthrough.sh` to the ingest bucket as `config/routing.json`, `config/passthrough.jsonata`, and `config/workflow_run_metric.jsonata` (unless overridden by `SLI_ROUTING_OBJECT` / `SLI_PASSTHROUGH_OBJECT`). In `routing.json`, the literal **`REPLACED_AT_RUNTIME`** is the ingest bucket placeholder; **`router_core.js`** replaces it with **`OCI_INGEST_BUCKET`** when the routing object is loaded.

### `routing.json`

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
    "oci_object_storage:github_workflow_job": {
      "bucket": "REPLACED_AT_RUNTIME",
      "prefix": "ingest/github/workflow_job/"
    },
    "oci_object_storage:github_pull_request": {
      "bucket": "REPLACED_AT_RUNTIME",
      "prefix": "ingest/github/pull_request/"
    },
    "oci_object_storage:github_check_suite": {
      "bucket": "REPLACED_AT_RUNTIME",
      "prefix": "ingest/github/check_suite/"
    },
    "oci_object_storage:github_deployment_status": {
      "bucket": "REPLACED_AT_RUNTIME",
      "prefix": "ingest/github/deployment_status/"
    },
    "oci_object_storage:github_deployment": {
      "bucket": "REPLACED_AT_RUNTIME",
      "prefix": "ingest/github/deployment/"
    },
    "oci_object_storage:github_check_run": {
      "bucket": "REPLACED_AT_RUNTIME",
      "prefix": "ingest/github/check_run/"
    },
    "oci_monitoring:github_workflow_run": {
      "namespace": "github_actions"
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
      "id": "github_workflow_run_to_metric",
      "mode": "fanout",
      "priority": 40,
      "match": {
        "headers": {
          "x-github-event": "workflow_run"
        }
      },
      "transform": {
        "mapping": "./workflow_run_metric.jsonata"
      },
      "destination": {
        "type": "oci_monitoring",
        "name": "github_workflow_run"
      }
    },
    {
      "id": "github_workflow_job_to_bucket",
      "mode": "exclusive",
      "priority": 40,
      "match": {
        "headers": {
          "x-github-event": "workflow_job"
        }
      },
      "transform": {
        "mapping": "./passthrough.jsonata"
      },
      "destination": {
        "type": "oci_object_storage",
        "name": "github_workflow_job"
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
      "id": "github_deployment_to_bucket",
      "mode": "exclusive",
      "priority": 40,
      "match": {
        "headers": {
          "x-github-event": "deployment"
        }
      },
      "transform": {
        "mapping": "./passthrough.jsonata"
      },
      "destination": {
        "type": "oci_object_storage",
        "name": "github_deployment"
      }
    },
    {
      "id": "github_check_run_to_bucket",
      "mode": "exclusive",
      "priority": 40,
      "match": {
        "headers": {
          "x-github-event": "check_run"
        }
      },
      "transform": {
        "mapping": "./passthrough.jsonata"
      },
      "destination": {
        "type": "oci_object_storage",
        "name": "github_check_run"
      }
    },
    {
      "id": "github_deployment_status_to_bucket",
      "mode": "exclusive",
      "priority": 40,
      "match": {
        "headers": {
          "x-github-event": "deployment_status"
        }
      },
      "transform": {
        "mapping": "./passthrough.jsonata"
      },
      "destination": {
        "type": "oci_object_storage",
        "name": "github_deployment_status"
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

### `passthrough.jsonata`

```text
$

```

(JSONata identity: output equals the router body, used for Object Storage ingest routes.)

### `workflow_run_metric.jsonata`

```text
action = "completed" and workflow_run.conclusion in ["success","failure","cancelled","timed_out","action_required"]
? [
    {
      "namespace": "github_actions",
      "name": "workflow_run_result",
      "dimensions": {
        "repository": repository.full_name,
        "workflow":   workflow_run.name,
        "branch":     workflow_run.head_branch,
        "event":      workflow_run.event,
        "conclusion": workflow_run.conclusion
      },
      "datapoints": [{
        "timestamp": workflow_run.updated_at,
        "value": workflow_run.conclusion = "success" ? 1 : 0
      }]
    },
    {
      "namespace": "github_actions",
      "name": "workflow_run_duration_s",
      "dimensions": {
        "repository": repository.full_name,
        "workflow":   workflow_run.name,
        "branch":     workflow_run.head_branch,
        "event":      workflow_run.event,
        "conclusion": workflow_run.conclusion
      },
      "metadata": { "unit": "seconds" },
      "datapoints": [{
        "timestamp": workflow_run.updated_at,
        "value": ($toMillis(workflow_run.updated_at) - $toMillis(workflow_run.created_at)) / 1000
      }]
    }
  ]
: []
```

(When the condition is false, the expression yields an empty array: **no** Monitoring post for non-terminal runs.)

### 1. Repository seeds → bucket objects

| Local seed (edit here) | Uploaded object name (default) | Role |
| --- | --- | --- |
| `tests/fixtures/fn_router_passthrough/routing.json` | `config/routing.json` | Routes, adapters, `match` headers, `transform.mapping` basenames |
| `tests/fixtures/fn_router_passthrough/passthrough.jsonata` | `config/passthrough.jsonata` | Identity mapping `$` for passthrough routes |
| `tests/fixtures/fn_router_passthrough/workflow_run_metric.jsonata` | `config/workflow_run_metric.jsonata` | SLI-41: completed `workflow_run` → dual Monitoring metrics |

**Upload path:** `tools/cycle_apigw_router_passthrough.sh` (when `FN_ROUTER_AUTO_INGEST_BUCKET=true`) runs `oci os object put` for the three files above into the ingest bucket (see script for `SLI_ROUTING_OBJECT`, `SLI_PASSTHROUGH_OBJECT`, `SLI_ROUTING_BUCKET`, `SLI_MAPPING_BUCKET` overrides).

### 2. Fn configuration (environment)

After provisioning, the cycle script merges the Fn **`config`** map to include at least:

| Variable | Purpose |
| --- | --- |
| `OCI_INGEST_BUCKET` | Ingest bucket name (raw + GitHub prefixes + dead letter) |
| `SLI_ROUTING_BUCKET` | Bucket holding `routing.json` (defaults to ingest bucket) |
| `SLI_ROUTING_OBJECT` | Object name for routing JSON (default `config/routing.json`) |
| `SLI_MAPPING_BUCKET` | Bucket for JSONata files (default: same as routing bucket) |
| `SLI_PASSTHROUGH_OBJECT` | **Full object path** for the **passthrough** mapping only (default `config/passthrough.jsonata`). **Must not** override other mappings — see **SLI-41-2** in `sprint_26_bugfixes.md`; `router_core` resolves `config/<basename>` for every other `transform.mapping`. |
| `OCI_MONITORING_COMPARTMENT_ID` | Compartment OCID for `postMetricData` (cycle sets to scaffold compartment) |
| `OCI_REGION` | Home region for Monitoring client |

Full operator knobs (compartment path, Fn context, teardown, deploy flags) remain documented in the **`tools/cycle_apigw_router_passthrough.sh`** header comment.

### 3. Routing behaviour (reading the embedded `routing.json`)

- **`github_workflow_run_to_bucket`** (`exclusive`, `./passthrough.jsonata`): writes **every** `X-GitHub-Event: workflow_run` payload to **`ingest/github/workflow_run/`** (audit / replay).
- **`github_workflow_run_to_metric`** (`fanout`, `./workflow_run_metric.jsonata`): same header match; JSONata (embedded above) emits metrics **only** for completed terminal conclusions; otherwise **`[]`** → no Monitoring post.

**Same match, mixed `exclusive` + `fanout` — not a bug.** The JSON router resolves deliveries as: **one** winning `exclusive` route among those that matched (highest `priority`; two exclusives tied at the same priority → error), then **all** matched `fanout` routes. So this envelope runs **both** the bucket passthrough and the metric mapping in one pass. Implementation: `selectRoutes` / `resolveExclusiveMatch` in `fn/router_passthrough/lib/json_router.js`. Operator follow-up and optional validation guidance: **SLI-43** in `BACKLOG.md` (relates to **SLI-28**).

Adapters wire `oci_object_storage:*` prefixes and **`oci_monitoring:github_workflow_run`** (`namespace: github_actions`). **If the fixture files change, update the verbatim section above to match** (or readers will see a stale snapshot).

### 4. Object Storage layout (ingest prefixes)

Prefixes are defined on the **`oci_object_storage:*`** adapters in `routing.json` (e.g. `ingest/github/ping/`, `ingest/dead_letter/`, …). Operators can list keys with **`tools/list_github_ingest_prefixes.sh`** and validate bodies + Monitoring values with **`tools/validate_router_ingest_and_metrics.sh`** (see sprint tests doc).

### 5. Redeploy vs config-only change

- **JSONata / `routing.json` only:** Re-run the cycle script (or `oci os object put` the changed object). No Fn image rebuild required if the handler already supports the schema.
- **Handler / `router_core.js`:** Bump **`fn/router_passthrough/func.yaml`** version and set **`FN_FORCE_DEPLOY=true`** (or equivalent) so Oracle Functions pulls a new image; see cycle script footer notes.

### Files

| Area | Change |
| --- | --- |
| `tests/fixtures/fn_router_passthrough/routing.json` | `oci_monitoring:github_workflow_run` adapter + fanout route `github_workflow_run_to_metric` |
| `tests/fixtures/fn_router_passthrough/workflow_run_metric.jsonata` | New JSONata filter and dual-metric payload |
| `tests/fixtures/github_webhook_samples/workflow_run.json` | Added `event`, `created_at`, `updated_at` for duration |
| `tests/fixtures/github_webhook_samples/workflow_run_requested.json` | New sample for non-completed runs |
| `tests/unit/test_fn_passthrough_router.sh` | SLI-41 assertions: metrics for completed run, none for requested; FDK path; **SLI-41-2** regression (`SLI_PASSTHROUGH_OBJECT` must not override non-passthrough mappings) |
| `tests/integration/test_fn_apigw_object_storage_passthrough.sh` | **SLI-41-1:** live `workflow_run` POST + Object Storage check + Monitoring poll (`github_actions.workflow_run_result`); timestamps refreshed to satisfy OCI ingest window |
| `tools/cycle_apigw_router_passthrough.sh` | Upload `config/workflow_run_metric.jsonata`; Fn config `OCI_MONITORING_COMPARTMENT_ID` + `OCI_REGION` |
| `tools/list_monitoring_metrics.sh` | Operator helper: `oci monitoring metric list` by namespace (pairs with `tools/list_github_ingest_prefixes.sh`); compartment from `SLI_OCI_STATE_FILE` / `.compartment.ocid` |
| `tools/validate_router_ingest_and_metrics.sh` | Operator helper: newest ingest keys + optional JSON peek + `summarize-metrics-data` for `workflow_run_*` **values** (bucket + Monitoring in one command) |
| `tools/list_github_ingest_prefixes.sh` | Header cross-reference to `list_monitoring_metrics.sh` |
| `fn/router_passthrough/router_core.js` | **SLI-41-2:** `buildLoadMappingFromRef` applies `SLI_PASSTHROUGH_OBJECT` only for basename `passthrough.jsonata`; other mappings load `config/<basename>` (fixes raw webhook → Monitoring / dead-letter “metric name … blank”) |
| `fn/router_passthrough/func.yaml` | Version bumped whenever the Fn handler or bundle changes (see file; redeploy requires bump + `FN_FORCE_DEPLOY=true` per cycle script notes) |

### Runtime notes

- **SLI-42:** `routing.json` adapter keys activate `oci_monitoring` (Sprint 25).
- **SLI-41-2:** `SLI_PASSTHROUGH_OBJECT` applies only to `passthrough.jsonata`; see `progress/sprint_26/sprint_26_bugfixes.md`.
