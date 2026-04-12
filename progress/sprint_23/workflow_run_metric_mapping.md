# SLI-41 — Proposed: `workflow_run` → OCI Monitoring metric mapping

Design note for the backlog item. Not implemented.

---

## Trigger condition

Emit only when `action = "completed"`. Discard `requested` and `in_progress` events —
duration and conclusion are only available after completion.

---

## OCI Monitoring payload (two metrics per run)

```json
[
  {
    "namespace": "github_actions",
    "name": "workflow_run_result",
    "dimensions": {
      "repository":  "<repository.full_name>",
      "workflow":    "<workflow_run.name>",
      "branch":      "<workflow_run.head_branch>",
      "event":       "<workflow_run.event>",
      "conclusion":  "<workflow_run.conclusion>"
    },
    "datapoints": [
      {
        "timestamp": "<workflow_run.updated_at>",
        "value": 1
      }
    ]
  },
  {
    "namespace": "github_actions",
    "name": "workflow_run_duration_s",
    "dimensions": {
      "repository":  "<repository.full_name>",
      "workflow":    "<workflow_run.name>",
      "branch":      "<workflow_run.head_branch>",
      "event":       "<workflow_run.event>",
      "conclusion":  "<workflow_run.conclusion>"
    },
    "metadata": { "unit": "seconds" },
    "datapoints": [
      {
        "timestamp": "<workflow_run.updated_at>",
        "value": "<(updated_at - created_at) in seconds>"
      }
    ]
  }
]
```

`value` for `workflow_run_result`:

- `1` if `conclusion = "success"`
- `0` for `failure`, `cancelled`, `timed_out`, `action_required`
- omit event entirely for `skipped` / `neutral` (not an SLI signal)

---

## JSONata mapping (`workflow_run_metric.jsonata`)

```jsonata
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

---

## Existing adapter

`tools/adapters/oci_monitoring_adapter.js` already implements the pluggable handler API
(`supports()`, `onRoute()`, `getState()`). It accepts destination types `oci_monitoring` and
`oci_metric` and delegates actual emission to a caller-supplied `emit` function. The
`router_passthrough` Fn needs a concrete `emit` implementation that calls the OCI Monitoring
SDK `postMetricData()` with Resource Principal auth — the same pattern used by the existing
`oci_object_storage_adapter.js` for `putObject`.

---

## Routing definition changes required

1. **New adapter** — `oci_monitoring:github_workflow_run`:

   ```json
   "oci_monitoring:github_workflow_run": {
     "namespace": "github_actions"
   }
   ```

2. **New fanout route** — alongside the existing exclusive Object Storage route:

   ```json
   {
     "id": "github_workflow_run_to_metric",
     "mode": "fanout",
     "priority": 40,
     "match": { "headers": { "x-github-event": "workflow_run" } },
     "transform": { "mapping": "./workflow_run_metric.jsonata" },
     "destination": { "type": "oci_monitoring", "name": "github_workflow_run" }
   }
   ```

3. **New adapter in `router_core.js`** — an `oci_monitoring` adapter that calls
   `oci.monitoring.MonitoringClient.postMetricData()` using Resource Principal auth,
   similar to how the existing `oci_object_storage` adapter calls `putObject`.

---

## Live payload reference (2026-04-12 sample from `ingest/github/workflow_run/`)

```json
{
  "action": "requested",
  "workflow_run": {
    "id": 24300346776,
    "name": "SLI-22 — scheduled SLI snapshot (30 min)",
    "status": "queued",
    "conclusion": null,
    "event": "schedule",
    "head_branch": "main",
    "run_number": 91,
    "run_attempt": 1,
    "created_at": "2026-04-12T06:19:50Z",
    "updated_at": "2026-04-12T06:19:50Z"
  },
  "repository": { "full_name": "rstyczynski/sli_tracker" }
}
```

Note: `conclusion` is `null` on `requested` — the mapping guard `action = "completed"` prevents
emitting a metric with a null conclusion dimension.
