# Sprint 29 Manual — Router CLI Operator Guide

## Purpose

Sprint 29 fixed the main operator problem in `tools/json_router_cli.js`:

- before Sprint 29, single-envelope CLI runs only previewed routes
- after Sprint 29, single-envelope CLI executes the real delivery path

That means the CLI is now a practical local wrapper around the same routing runtime model used by the Function path.

This guide is focused only on the router CLI. It shows how to use the tool in all execution modes that matter to an operator.

## CLI Contract

```bash
node tools/json_router_cli.js --routing <file> [--input <file>] [--pretty]
cat envelope.json | node tools/json_router_cli.js --routing <file>
node tools/json_router_cli.js --routing <file> --source-dir <dir> --output-dir <dir> [--pretty]
```

Options:

- `--routing`
  Required. Path to `routing.json`.
- `--input`
  Optional. One envelope JSON file. If omitted, the CLI reads `stdin`.
- `--source-dir`
  Optional. Batch source directory.
- `--output-dir`
  Optional. Batch output directory.
- `--pretty`
  Optional. Pretty-print the result JSON.
- `--help`
  Show usage.

## What the CLI Can Do in Sprint 29

The router CLI now supports four practical operator modes:

1. route one envelope from a local file
2. route one envelope from `stdin`
3. run batch routing from `--source-dir` to `--output-dir`
4. execute a source declared inside `routing.json` without `--input`

The runtime behind the CLI can use these destination types:

- `file_system`
- `oci_object_storage`
- `oci_logging`
- `oci_monitoring`

The runtime can also load mappings from:

- local files
- OCI Object Storage, when `routing.json` declares `mapping.type = "oci_object_storage"`

## Result Shape

For one routed envelope, the CLI returns a structure like:

```json
{
  "status": "routed",
  "deliveries": [
    {
      "route": {
        "id": "audit_to_file",
        "mode": "exclusive",
        "destination": {
          "type": "file_system",
          "name": "audit_copy"
        }
      },
      "output": {
        "audit": {
          "id": "A-1"
        }
      }
    }
  ]
}
```

For batch routing, the CLI returns a summary like:

```json
{
  "processed": 4,
  "results": [
    {
      "file": "001.json",
      "route": "workflow_metric",
      "destination": "file_system/workflow_status",
      "output_path": "/tmp/..."
    }
  ]
}
```

## Capability 1 — Route One Envelope from a File

This is the basic local operator flow. It proves that a single JSON envelope now performs real delivery.

```bash
TMP_DIR="$(mktemp -d /tmp/sli_router_single.XXXXXX)"
echo '$' > "$TMP_DIR/mapping_file.jsonata"
cat > "$TMP_DIR/envelope.json" <<'EOF'
{
  "body": {
    "audit": {
      "id": "A-1",
      "message": "copied to file adapter"
    }
  }
}
EOF

cat > "$TMP_DIR/routing.json" <<'EOF'
{
  "routes": [
    {
      "id": "audit_to_file",
      "match": {
        "required_fields": ["audit.id"]
      },
      "transform": {
        "mapping": "./mapping_file.jsonata"
      },
      "destination": {
        "type": "file_system",
        "name": "audit_copy"
      }
    }
  ]
}
EOF

node tools/json_router_cli.js \
  --routing "$TMP_DIR/routing.json" \
  --input "$TMP_DIR/envelope.json" \
  --pretty

cat "$TMP_DIR/file_system/audit_copy/001_audit_to_file.json" | jq
```

Expected operator understanding:

- the route match is evaluated
- the mapping is executed
- the file is really written under `file_system/audit_copy/`

## Capability 1A — Influence Adapter Behavior with Destination Labeling

The route destination is a logical label:

```json
{
  "type": "file_system",
  "name": "audit_copy"
}
```

The actual adapter behavior can then be changed through the `adapters` section. For `file_system`, the key format is:

`file_system:<name>`

This lets the operator keep the same route label but redirect the write location.

```bash
TMP_DIR="$(mktemp -d /tmp/sli_router_labeling.XXXXXX)"
echo '$' > "$TMP_DIR/mapping_file.jsonata"
cat > "$TMP_DIR/envelope.json" <<'EOF'
{
  "body": {
    "audit": {
      "id": "A-1",
      "message": "written through labeled adapter"
    }
  }
}
EOF

cat > "$TMP_DIR/routing.json" <<'EOF'
{
  "adapters": {
    "file_system:audit_copy": {
      "directory": "out/custom_audit_location"
    }
  },
  "routes": [
    {
      "id": "audit_to_file",
      "match": {
        "required_fields": ["audit.id"]
      },
      "transform": {
        "mapping": "./mapping_file.jsonata"
      },
      "destination": {
        "type": "file_system",
        "name": "audit_copy"
      }
    }
  ]
}
EOF

node tools/json_router_cli.js \
  --routing "$TMP_DIR/routing.json" \
  --input "$TMP_DIR/envelope.json" \
  --pretty

cat "$TMP_DIR/out/custom_audit_location/001_audit_to_file.json" | jq
```

Operator meaning:

- the route still says `file_system / audit_copy`
- the adapter label `file_system:audit_copy` decides where that logical destination really writes
- this is the main way to keep route intent stable while changing local target behavior

## Capability 2 — Route One Envelope from `stdin`

Use this when the envelope is produced by another command or shell pipeline.

```bash
TMP_DIR="$(mktemp -d /tmp/sli_router_stdin.XXXXXX)"
echo '$' > "$TMP_DIR/mapping_file.jsonata"

cat > "$TMP_DIR/routing.json" <<'EOF'
{
  "routes": [
    {
      "id": "audit_to_file",
      "match": {
        "required_fields": ["audit.id"]
      },
      "transform": {
        "mapping": "./mapping_file.jsonata"
      },
      "destination": {
        "type": "file_system",
        "name": "audit_copy"
      }
    }
  ]
}
EOF

cat <<'EOF' | node tools/json_router_cli.js \
      --routing "$TMP_DIR/routing.json" \
      --pretty
{
  "body": {
    "audit": {
      "id": "A-1",
      "message": "copied to file adapter"
    }
  }
}
EOF

cat "$TMP_DIR/file_system/audit_copy/001_audit_to_file.json" | jq
```

Notice that output file auto numbered, here we know it's 001, as router operates on a fresh directory.

## Capability 3 — Pretty Output

Use `--pretty` when you want human-readable result JSON.

```bash
TMP_DIR="$(mktemp -d /tmp/sli_router_pretty.XXXXXX)"
cat > "$TMP_DIR/mapping_log.jsonata" <<'EOF'
{
  "kind": "log",
  "repo": repository.full_name,
  "outcome": workflow_run.conclusion
}
EOF

cat > "$TMP_DIR/envelope.json" <<'EOF'
{
  "headers": {
    "X-GitHub-Event": "workflow_run"
  },
  "body": {
    "workflow_run": {
      "conclusion": "success"
    },
    "repository": {
      "full_name": "acme/repo"
    }
  }
}
EOF

cat > "$TMP_DIR/routing.json" <<'EOF'
{
  "routes": [
    {
      "id": "workflow_to_log_shape",
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
        "name": "workflow_logs"
      }
    }
  ]
}
EOF

node tools/json_router_cli.js \
  --routing "$TMP_DIR/routing.json" \
  --input "$TMP_DIR/envelope.json" \
  --pretty

cat "$TMP_DIR/file_system/workflow_logs/001_workflow_to_log_shape.json" | jq
```

Note about mapping context. The CLI reads a full envelope, for example with `headers` and `body`, and route matching can use the full envelope. However JSONata transformation runs on `envelope.body`, not on the whole envelope. That is why the mapping uses `repository.full_name` and `workflow_run.conclusion`, not `body.repository.full_name`.

Without `--pretty`, the output is compact JSON and easier to pipe into other commands.

## Capability 4 — Batch Route a Source Directory

This is the local bulk-processing mode.

```bash
OUT_DIR="$(mktemp -d /tmp/sli_router_batch.XXXXXX)"
SRC_DIR="$(mktemp -d /tmp/sli_router_batch_source.XXXXXX)"
ROUTING_DIR="$(mktemp -d /tmp/sli_router_batch_routing.XXXXXX)"

cat > "$SRC_DIR/001_workflow_run.json" <<'EOF'
{
  "headers": {
    "X-GitHub-Event": "workflow_run"
  },
  "body": {
    "schema": "github.workflow_run",
    "workflow_run": {
      "conclusion": "success"
    },
    "repository": {
      "full_name": "org/app"
    }
  }
}
EOF

cat > "$SRC_DIR/002_health.json" <<'EOF'
{
  "endpoint": "/health",
  "body": {
    "service": "payments",
    "status": "ok"
  }
}
EOF

cat > "$SRC_DIR/003_unknown.json" <<'EOF'
{
  "body": {
    "message": "unknown payload"
  }
}
EOF

cat > "$ROUTING_DIR/mapping_generic.jsonata" <<'EOF'
{
  "kind": "generic",
  "repo": repository.full_name
}
EOF

cat > "$ROUTING_DIR/mapping_specific.jsonata" <<'EOF'
{
  "kind": "specific",
  "repo": repository.full_name,
  "schema": schema
}
EOF

cat > "$ROUTING_DIR/mapping_metric.jsonata" <<'EOF'
{
  "metric": "workflow_outcome",
  "repo": repository.full_name,
  "value": workflow_run.conclusion = "success" ? 1 : 0
}
EOF

cat > "$ROUTING_DIR/mapping_health.jsonata" <<'EOF'
{
  "metric": "health_status",
  "service": service,
  "value": status = "ok" ? 1 : 0
}
EOF

cat > "$ROUTING_DIR/routing.json" <<'EOF'
{
  "dead_letter": {
    "type": "dead_letter",
    "name": "errors"
  },
  "routes": [
    {
      "id": "generic_workflow",
      "mode": "exclusive",
      "priority": 100,
      "match": {
        "headers": {
          "X-GitHub-Event": "workflow_run"
        }
      },
      "transform": {
        "mapping": "./mapping_generic.jsonata"
      },
      "destination": {
        "type": "normalized_event",
        "name": "generic"
      }
    },
    {
      "id": "specific_workflow",
      "mode": "exclusive",
      "priority": 200,
      "match": {
        "headers": {
          "X-GitHub-Event": "workflow_run"
        },
        "schema": {
          "path": "schema",
          "equals": "github.workflow_run"
        }
      },
      "transform": {
        "mapping": "./mapping_specific.jsonata"
      },
      "destination": {
        "type": "oci_log",
        "name": "specific_events"
      }
    },
    {
      "id": "workflow_metric",
      "mode": "fanout",
      "match": {
        "headers": {
          "X-GitHub-Event": "workflow_run"
        }
      },
      "transform": {
        "mapping": "./mapping_metric.jsonata"
      },
      "destination": {
        "type": "oci_metric",
        "name": "workflow_status"
      }
    },
    {
      "id": "health_endpoint",
      "mode": "exclusive",
      "priority": 50,
      "match": {
        "endpoint": "/health"
      },
      "transform": {
        "mapping": "./mapping_health.jsonata"
      },
      "destination": {
        "type": "oci_metric",
        "name": "health_signal"
      }
    }
  ]
}
EOF

node tools/json_router_cli.js \
  --routing "$ROUTING_DIR/routing.json" \
  --source-dir "$SRC_DIR" \
  --output-dir "$OUT_DIR" \
  | jq

find "$OUT_DIR" -type f | sort
```

What this mode adds:

- the CLI reads many files
- each item is routed independently
- result JSON includes a processed count and per-file results
- files that do not match or fail can go to dead-letter output

Expected behavior for this fixture:

- one workflow item fans out to two files
- one health item produces one output file
- one unknown item lands in `dead_letter/errors/`

## Capability 5 — Execute a Source Declared in `routing.json`

If `routing.json` declares a `source`, the CLI can execute end-to-end without `--input` and without shell piping. This is a special mode that is not used in webhook reception mode, which used stdin input, however is available as may be useful for batch processing e.g. by reading messages from a queue.

Supported source types:

- `file_system`
- `oci_object_storage`

Minimal local file-system source example:

```bash
TMP_DIR="$(mktemp -d /tmp/sli_router_source_mode.XXXXXX)"
mkdir -p "$TMP_DIR/in"
echo '$' > "$TMP_DIR/mapping_file.jsonata"
cat > "$TMP_DIR/in/audit.json" <<'EOF'
{
  "body": {
    "audit": {
      "id": "A-1",
      "message": "copied to file adapter"
    }
  }
}
EOF

cat > "$TMP_DIR/routing.json" <<'EOF'
{
  "source": {
    "type": "file_system",
    "name": "incoming"
  },
  "adapters": {
    "file_system:incoming": { "directory": "in" },
    "file_system:audit_copy": { "directory": "out/audit" }
  },
  "routes": [
    {
      "id": "audit_to_file",
      "match": { "required_fields": ["audit.id"] },
      "transform": { "mapping": "./mapping_file.jsonata" },
      "destination": { "type": "file_system", "name": "audit_copy" }
    }
  ]
}
EOF

(cd "$TMP_DIR" && node "$OLDPWD/tools/json_router_cli.js" --routing "$TMP_DIR/routing.json" --pretty)
find "$TMP_DIR/out" -type f | sort
```

Note about `adapters` in this mode:

- `source` selects one logical input, here `file_system / incoming`
- `adapters["file_system:incoming"]` configures how that source adapter reads input, here from directory `in`
- `adapters["file_system:audit_copy"]` configures how the destination adapter writes output, here to directory `out/audit`
- in other words, the `adapters` section is used for both source adapter configuration and target adapter configuration

Operator meaning:

- the source is resolved from the routing definition
- the CLI becomes a runtime launcher, not just a file/stdin wrapper

## Production level capabilities

### Load `routing.json` from a Remote Location

The router product already supports remote `routing.json`, but not through the local CLI.

Important boundary:

- `json_router_cli.js` still expects `--routing <local-file>`
- the deployed Function runtime can load `routing.json` from OCI Object Storage

That remote-loading path is implemented in:

- [fn/router_passthrough/router_core.js](/Users/rstyczynski/projects/SLI_tracker/fn/router_passthrough/router_core.js)

The Function runtime uses these environment variables:

- `SLI_ROUTING_BUCKET`
- `SLI_ROUTING_OBJECT`
- fallback: `OCI_INGEST_BUCKET`

Default object name:

- `config/routing.json`

So the operator model for remote routing definition is:

1. prepare `routing.json` locally
2. upload it to an OCI bucket
3. configure the deployed runtime to read that object
4. let the Function load routing at invocation time

Practical meaning:

- local CLI validation still uses a local `routing.json`
- deployed runtime can keep routing outside the image, so operators can update configuration without rebuilding code

### Use OCI Object Storage as Mapping Source

Important boundary for the local CLI:

- `routing.json` itself is still loaded from a local file path passed to `--routing`
- only the mapping files can be loaded from OCI Object Storage in this capability

So the operator model is:

1. keep `routing.json` local
2. store JSONata mappings in a bucket
3. let the runtime fetch mappings from OCI during route execution

The CLI can load JSONata mappings from OCI Object Storage when the routing definition declares:

- `mapping.type = "oci_object_storage"`
- an adapter target for the mapping bucket

This is the main remote-mapping capability added to the real runtime path.

Reference integration scenario:

- [`tests/integration/test_json_router_cli_mapping_oci_object_storage.sh`](/Users/rstyczynski/projects/SLI_tracker/tests/integration/test_json_router_cli_mapping_oci_object_storage.sh)

Operator model:

1. upload mapping files into an OCI bucket
2. point `routing.json` mapping adapter to that bucket/prefix
3. run the CLI normally
4. the runtime fetches the mapping from OCI before route execution

### Deliver to OCI Destinations

The Sprint 29 runtime behind the CLI supports these OCI destinations:

- `oci_object_storage`
- `oci_logging`
- `oci_monitoring`

That means the CLI can be used not only for local file exercises, but also for live OCI delivery when:

- `OCI_CLI_PROFILE` is valid
- the routing adapters contain the needed target configuration
- the mapping output shape matches the destination contract

Runtime note for operators:

- `oci_object_storage` writes JSON objects to a bucket/prefix
- `oci_logging` pushes entries through the OCI Logging ingestion client
- `oci_monitoring` posts metric data through the Monitoring ingestion client

## Capability 6 — Dead-Letter Handling

Dead-letter behavior is especially visible in batch mode.

If `routing.json` defines `dead_letter`, failed or unreadable items are written there. If it does not, the CLI fails the run.

Practical operator meaning:

- use `dead_letter` when processing mixed-quality inputs
- omit it when you want strict fail-fast behavior

## Capability 7 — Error Cases You Should Know

These are the main CLI failure modes:

- missing `--routing`
- malformed input JSON
- batch mode with only one of `--source-dir` or `--output-dir`
- unreadable mapping
- unsupported source type
- unsupported destination configuration

The unit tests that cover these cases are:

- [`tests/unit/test_json_router_cli.sh`](/Users/rstyczynski/projects/SLI_tracker/tests/unit/test_json_router_cli.sh)
- [`tests/unit/test_json_pipeline_cli.sh`](/Users/rstyczynski/projects/SLI_tracker/tests/unit/test_json_pipeline_cli.sh)

## Recommended Operator Progression

Use the CLI in this order:

1. single file to local `file_system`
2. `stdin` to local `file_system`
3. transform CLI piped to router CLI
4. batch `--source-dir/--output-dir`
5. source-defined runtime mode in `routing.json`
6. OCI mapping source
7. OCI destinations

That order moves from fully local and observable workflows to live OCI-backed delivery.

## Sprint 29 Takeaway

The important Sprint 29 outcome is simple:

- `json_router_cli.js` is no longer a preview toy for single-envelope runs
- it is now an execution tool that performs real delivery across the same routing runtime model as the Function path

For an operator, that makes the CLI the best place to understand, validate, and evolve a routing definition before deploying it elsewhere.
