# Sprint 21 Tests — SLI-33 + SLI-34 Universal Destinations

## Gate A2 — Unit (new tests / changed component scope)

Result: **PASS** — 5 scripts passed, 0 failed.

Command:

```bash
TS="$(date -u '+%Y%m%d_%H%M%S')"
LOG="progress/sprint_21/test_run_A2_unit_${TS}.log"
tests/run.sh --unit --new-only progress/sprint_21/new_tests.manifest 2>&1 | tee "$LOG"
```

Coverage:

- router batch behavior with logical destinations only
- router schema behavior with universal destinations
- router CLI batch behavior without filesystem metadata in `routing.json`
- filesystem adapter destination resolution
- OCI Logging / Monitoring / Object Storage adapter resolution
- mixed destination dispatch with dead-letter routing

## Gate B2 — Unit Regression (component-scoped)

Result: **PASS** — 11 scripts passed, 0 failed.

Command:

```bash
TS="$(date -u '+%Y%m%d_%H%M%S')"
LOG="progress/sprint_21/test_run_B2_unit_${TS}.log"
tests/run.sh --unit --manifest progress/sprint_21/regression_tests.manifest 2>&1 | tee "$LOG"
```

Scope:

- router library
- router CLI
- router schema and batch behavior
- router adapter layer
- transformer library
- transformer CLI
- transform-to-router CLI pipeline

## Outcome

Sprint 21 defines component-scoped regression as:

- explicit
- manifest-driven
- still executed through the centralized test runner

This is the intended answer for scoping regression to one component without inventing a separate test harness.

## Artifacts

- `progress/sprint_21/test_run_A2_unit_20260410_000001.log`
- `progress/sprint_21/test_run_B2_unit_20260410_000101.log`
- `progress/sprint_21/test_run_A2_unit_20260410_091118.log`
- `progress/sprint_21/test_run_B2_unit_20260410_091118.log`
- `progress/sprint_21/test_run_C2_integration_20260410_091118.log`

## Gate C2 — Integration (live OCI, mapping source + CLI parity)

Result: **PASS** — 6 scripts passed, 0 failed.

Command:

```bash
TS="$(date -u '+%Y%m%d_%H%M%S')"
LOG="progress/sprint_21/test_run_C2_integration_${TS}.log"
tests/run.sh --integration --manifest progress/sprint_21/integration_tests.manifest 2>&1 | tee "$LOG"
```

Coverage:

- router loads `transform.mapping` from OCI Object Storage via `definition.mapping` + `definition.adapters`
- CLI (`tools/json_router_cli.js`) uses the same mapping resolution as the library when `mapping` is present
- resources created under compartment `/SLI_tracker` via `oci_scaffold` ensure scripts

## Notes

- Sprint 21 includes **unit + integration** gates.
- Integration requires a working OCI API-key profile (default: `DEFAULT`).

## End-to-end integration scenarios (review-friendly)

These scenarios are implemented as integration scripts under `tests/integration/` and run through a single manifest.

Run all Sprint 21 integration scenarios:

```bash
tests/run.sh --integration --manifest progress/sprint_21/integration_tests.manifest
```

### IT-1 — Mapping from bucket (library path)

- **Script**: `tests/integration/test_json_router_mapping_oci_object_storage.sh`
- **Source**: local envelope fixture (filesystem)
- **Mapping**: OCI Object Storage bucket (`routing.json` `mapping` + `adapters`)
- **Target**: in-memory (asserts output shape)
- **Purpose**: proves the router library can fetch `transform.mapping` from Object Storage using a real OCI SDK connection.

`routing.json` (effective shape):

```json
{
  "adapters": {
    "oci_object_storage:mappings": {
      "bucket": "<mapping-bucket>",
      "prefix": "jsonata/"
    }
  },
  "mapping": {
    "type": "oci_object_storage",
    "name": "mappings"
  },
  "routes": [
    {
      "id": "workflow_to_logging",
      "match": {
        "headers": {
          "X-GitHub-Event": "workflow_run"
        }
      },
      "transform": {
        "mapping": "./mapping_log.jsonata"
      },
      "destination": {
        "type": "oci_logging",
        "name": "github_events"
      }
    }
  ]
}
```

### IT-2 — Mapping from bucket (CLI parity)

- **Script**: `tests/integration/test_json_router_cli_mapping_oci_object_storage.sh`
- **Source**: local envelope fixture (filesystem)
- **Mapping**: OCI Object Storage bucket
- **Target**: CLI JSON output
- **Purpose**: proves `tools/json_router_cli.js` uses the same mapping resolution as the library when `routing.json` defines `mapping`.

`routing.json`:

```json
{
  "adapters": {
    "oci_object_storage:mappings": {
      "bucket": "<mapping-bucket>",
      "prefix": "jsonata/"
    }
  },
  "mapping": {
    "type": "oci_object_storage",
    "name": "mappings"
  },
  "routes": [
    {
      "id": "workflow_to_logging",
      "match": {
        "headers": {
          "X-GitHub-Event": "workflow_run"
        }
      },
      "transform": {
        "mapping": "./mapping_log.jsonata"
      },
      "destination": {
        "type": "oci_logging",
        "name": "github_events"
      }
    }
  ]
}
```

### Flow 1 — File → Bucket, map = File

- **Script**: `tests/integration/test_router_flow_1_file_to_bucket_map_file.sh`
- **Source**: filesystem directory (`file_source_adapter`)
- **Mapping**: local filesystem (`./mapping_log.jsonata`)
- **Target**: OCI Object Storage bucket (`oci_object_storage_adapter`) under prefix `out/`
- **Purpose**: proves “real data” delivery to Object Storage works when mappings are local.

`routing.json`:

```json
{
  "adapters": {
    "file_system:source": {
      "directory": "./source"
    },
    "oci_object_storage:raw_events": {
      "bucket": "<data-bucket>",
      "prefix": "out/"
    }
  },
  "source": {
    "type": "file_system",
    "name": "source"
  },
  "routes": [
    {
      "id": "workflow_to_bucket",
      "match": {
        "headers": {
          "X-GitHub-Event": "workflow_run"
        }
      },
      "transform": {
        "mapping": "./mapping_log.jsonata"
      },
      "destination": {
        "type": "oci_object_storage",
        "name": "raw_events"
      }
    }
  ]
}
```

### Flow 2 — File → Bucket, map = Bucket

- **Script**: `tests/integration/test_router_flow_2_file_to_bucket_map_bucket.sh`
- **Source**: filesystem directory
- **Mapping**: OCI Object Storage bucket (`mapping` destination)
- **Target**: OCI Object Storage bucket under prefix `out/`
- **Purpose**: proves end-to-end “data to bucket” with mapping also loaded from bucket.

`routing.json`:

```json
{
  "adapters": {
    "file_system:source": {
      "directory": "./source"
    },
    "oci_object_storage:mappings": {
      "bucket": "<mapping-bucket>",
      "prefix": "jsonata/"
    },
    "oci_object_storage:raw_events": {
      "bucket": "<data-bucket>",
      "prefix": "out/"
    }
  },
  "source": {
    "type": "file_system",
    "name": "source"
  },
  "mapping": {
    "type": "oci_object_storage",
    "name": "mappings"
  },
  "routes": [
    {
      "id": "workflow_to_bucket",
      "match": {
        "headers": {
          "X-GitHub-Event": "workflow_run"
        }
      },
      "transform": {
        "mapping": "./mapping_log.jsonata"
      },
      "destination": {
        "type": "oci_object_storage",
        "name": "raw_events"
      }
    }
  ]
}
```

### Flow 3 — Bucket → File, map = Bucket

- **Script**: `tests/integration/test_router_flow_3_bucket_to_file_map_bucket.sh`
- **Source**: OCI Object Storage bucket/prefix (`oci_object_storage_source_adapter`)
- **Mapping**: OCI Object Storage bucket
- **Target**: filesystem (`file_adapter`)
- **Purpose**: proves the “ingest from Object Storage” side works (bucket source → router → file target) while also resolving mappings from bucket.

`routing.json`:

```json
{
  "adapters": {
    "oci_object_storage:mappings": {
      "bucket": "<mapping-bucket>",
      "prefix": "jsonata/"
    },
    "oci_object_storage:source": {
      "bucket": "<source-bucket>",
      "prefix": "source/"
    },
    "file_system:out": {
      "directory": "out"
    }
  },
  "source": {
    "type": "oci_object_storage",
    "name": "source"
  },
  "mapping": {
    "type": "oci_object_storage",
    "name": "mappings"
  },
  "routes": [
    {
      "id": "workflow_to_file",
      "match": {
        "headers": {
          "X-GitHub-Event": "workflow_run"
        }
      },
      "transform": {
        "mapping": "./mapping_log.jsonata"
      },
      "destination": {
        "type": "file_system",
        "name": "out"
      }
    }
  ]
}
```

### Flow 4 — Complex multi-target (file source, file mappings, fanout + exclusive priority)

- **Script**: `tests/integration/test_router_complex_flow_file_map_multi_targets.sh`
- **Source**: filesystem directory (configured in `routing.json` `source`)
- **Mapping**: local filesystem (multiple JSONata mappings)
- **Targets**:
  - OCI Object Storage bucket prefixes: `logs/`, `metrics/`, `messages/`, `fanout/`
  - filesystem directories: `fanout/`, `exclusive/`
- **Purpose**:
  - validates multiple mapping shapes and multiple destinations in one run
  - validates `fanout` delivers to bucket + filesystem
  - validates `exclusive` prioritization suppresses the lower-priority bucket route

`routing.json` (excerpt; effective structure):

```json
{
  "adapters": {
    "file_system:source": { "directory": "./source" },
    "oci_object_storage:logs": { "bucket": "<data-bucket>", "prefix": "logs/" },
    "oci_object_storage:metrics": { "bucket": "<data-bucket>", "prefix": "metrics/" },
    "oci_object_storage:messages": { "bucket": "<data-bucket>", "prefix": "messages/" },
    "oci_object_storage:fanout": { "bucket": "<data-bucket>", "prefix": "fanout/" },
    "oci_object_storage:exclusive": { "bucket": "<data-bucket>", "prefix": "exclusive/" },
    "file_system:fanout": { "directory": "fanout" },
    "file_system:exclusive": { "directory": "exclusive" }
  },
  "source": { "type": "file_system", "name": "source" },
  "routes": [
    { "id": "to_logs_bucket", "mode": "exclusive", "priority": 10, "destination": { "type": "oci_object_storage", "name": "logs" } },
    { "id": "to_metrics_bucket", "mode": "exclusive", "priority": 10, "destination": { "type": "oci_object_storage", "name": "metrics" } },
    { "id": "to_messages_bucket", "mode": "exclusive", "priority": 10, "destination": { "type": "oci_object_storage", "name": "messages" } },
    { "id": "fanout_bucket", "mode": "fanout", "priority": 1, "destination": { "type": "oci_object_storage", "name": "fanout" } },
    { "id": "fanout_file", "mode": "fanout", "priority": 1, "destination": { "type": "file_system", "name": "fanout" } },
    { "id": "exclusive_to_file_higher_priority", "mode": "exclusive", "priority": 50, "destination": { "type": "file_system", "name": "exclusive" } },
    { "id": "exclusive_to_bucket_lower_priority", "mode": "exclusive", "priority": 5, "destination": { "type": "oci_object_storage", "name": "exclusive" } }
  ]
}
```
