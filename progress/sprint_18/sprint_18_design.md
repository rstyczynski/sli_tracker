# Sprint 18 Design — SLI-26 JSON Transformer

## Components

### `tools/json_transformer.js` (library)

Public API (CommonJS):
```
loadMapping(filePath)     → { version, description, expression }
transform(source, mapping) → Promise<any>
```

`loadMapping` reads the file, parses JSON, validates `expression` field is present and a string.
`transform` compiles the JSONata expression once, evaluates it against `source`, and returns the result.

### `tools/json_transform_cli.js` (CLI)

```
Usage:
  node tools/json_transform_cli.js --mapping <file> [--input <file>]
  cat source.json | node tools/json_transform_cli.js --mapping <file>

Options:
  --mapping  Path to mapping JSON file (required)
  --input    Path to source JSON file (optional; reads stdin if omitted)
  --pretty   Pretty-print output (optional; default: compact)
  --help     Show usage
```

Exits 0 on success with JSON to stdout. Exits 1 on any error with message to stderr.

### `tools/mappings/` (example mapping files)

- `github_workflow_run_to_oci_log.jsonata` — maps GitHub `workflow_run` webhook to OCI log entry shape
- `health_to_oci_metric.jsonata` — maps a `/health` API response to an OCI metric datapoint shape

### Mapping file format

Two file formats are supported:

- `.jsonata` — the file content is a raw JSONata expression
- `.json` — JSON envelope with `version`, optional `description`, and required `expression`

```json
{
  "version": "1",
  "description": "Human-readable description",
  "expression": "<JSONata expression string>"
}
```

The `expression` is a full JSONata expression. The source document root is available as `$`. Field values are accessed with `$.fieldName` or shorthand `fieldName`. Example:

```json
{
  "version": "1",
  "description": "Extract workflow outcome",
  "expression": "{ \"outcome\": workflow_run.conclusion, \"name\": workflow_run.name }"
}
```

## Testing Strategy

**Scope:** unit only. No OCI API calls, no HTTP, no filesystem side effects beyond reading fixture files.

**Test categories:**

1. **Happy-path transformations** — valid source + valid mapping → expected output
   - Identity mapping (`$$`)
   - Field extraction and rename
   - Nested field access
   - Array transformation
   - Conditional expression
   - String concatenation / manipulation
   - Numeric computation
   - GitHub `workflow_run` → OCI log shape
   - `/health` response → OCI metric shape

2. **Bad source data** — valid mapping, bad/unexpected source
   - Missing field in source (expression references absent path → `undefined`)
   - Null field value
   - Wrong type (number where string expected — JSONata coerces, result verified)
   - Empty source object `{}`
   - Source is a JSON array at root
   - Missing nested webhook objects (`workflow_run`, `repository`)
   - Empty objects that collapse generated output sections
   - Missing optional metadata (for example `freeformTags`) omitted from output

3. **Bad mapping** — valid source, bad mapping file
   - `expression` field missing
   - `expression` is not a string (number, null, object)
   - `expression` is invalid JSONata syntax
   - Mapping file is not valid JSON
   - Mapping file does not exist
   - Runtime evaluation errors caused by incompatible data or invalid function usage

4. **Strict required-field validation**
   - Mappings may use JSONata `$assert($exists(...), "...")` to fail fast on required input fields
   - Required-field checks must be verified for both missing leaf fields and missing parent objects
   - Error messages should stay actionable enough to identify the missing source path

5. **CLI behaviour**
   - Reads from file via `--input`
   - Reads from stdin (pipe)
   - `--pretty` produces indented output
   - Unknown flag → non-zero exit + usage to stderr
   - Missing `--mapping` → non-zero exit
   - Non-existent mapping file → non-zero exit
   - Non-existent input file → non-zero exit
   - Malformed source JSON → non-zero exit
   - Transform-time `$assert(...)` failure surfaces as exit 1 with error text on stderr

## Test Specification

### Unit tests — UT-1 through UT-54

| ID    | Suite | Script                              | Function / scenario                            |
|-------|-------|-------------------------------------|------------------------------------------------|
| UT-1  | unit  | test_json_transformer.sh            | identity mapping returns source unchanged      |
| UT-2  | unit  | test_json_transformer.sh            | field extraction and rename                    |
| UT-3  | unit  | test_json_transformer.sh            | nested field access                            |
| UT-4  | unit  | test_json_transformer.sh            | array transformation                           |
| UT-5  | unit  | test_json_transformer.sh            | conditional expression                         |
| UT-6  | unit  | test_json_transformer.sh            | string concatenation                           |
| UT-7  | unit  | test_json_transformer.sh            | numeric computation                            |
| UT-8  | unit  | test_json_transformer.sh            | github workflow_run → oci log shape            |
| UT-9  | unit  | test_json_transformer.sh            | health endpoint → oci metric shape             |
| UT-10 | unit  | test_json_transformer.sh            | missing field in source → undefined omitted    |
| UT-11 | unit  | test_json_transformer.sh            | null field value passed through                |
| UT-12 | unit  | test_json_transformer.sh            | wrong type — JSONata coercion                  |
| UT-13 | unit  | test_json_transformer.sh            | empty source object                            |
| UT-14 | unit  | test_json_transformer.sh            | source is array at root                        |
| UT-15 | unit  | test_json_transformer.sh            | expression field missing → error               |
| UT-16 | unit  | test_json_transformer.sh            | expression is not a string → error             |
| UT-17 | unit  | test_json_transformer.sh            | invalid JSONata syntax → error                 |
| UT-18 | unit  | test_json_transformer.sh            | mapping file not valid JSON → error            |
| UT-19 | unit  | test_json_transformer.sh            | mapping file does not exist → error            |
| UT-20 | unit  | test_json_transformer_cli.sh        | cli --input file produces correct output       |
| UT-21 | unit  | test_json_transformer_cli.sh        | cli reads from stdin                           |
| UT-22 | unit  | test_json_transformer_cli.sh        | cli --pretty produces indented output          |
| UT-23 | unit  | test_json_transformer_cli.sh        | cli unknown flag → exit 1                      |
| UT-24 | unit  | test_json_transformer_cli.sh        | cli missing --mapping → exit 1                 |
| UT-25 | unit  | test_json_transformer_cli.sh        | cli non-existent mapping file → exit 1         |
| UT-26 | unit  | test_json_transformer_cli.sh        | cli non-existent input file → exit 1           |
| UT-27 | unit  | test_json_transformer_cli.sh        | cli malformed source JSON → exit 1             |
| UT-28 | unit  | test_json_transformer.sh            | github workflow_run success → SLI event        |
| UT-29 | unit  | test_json_transformer.sh            | github workflow_run failure → outcome_value=0  |
| UT-30 | unit  | test_json_transformer.sh            | /health all UP → metric value=1 per component  |
| UT-31 | unit  | test_json_transformer.sh            | /health db DOWN → component value=0            |
| UT-32 | unit  | test_json_transformer.sh            | github workflow_run → OCI PostMetricData       |
| UT-33 | unit  | test_json_transformer.sh            | /health all UP → OCI PostMetricData            |
| UT-34 | unit  | test_json_transformer.sh            | /health db DOWN → OCI PostMetricData           |
| UT-35 | unit  | test_json_transformer.sh            | OCI bucket CloudEvent → log entry              |
| UT-36 | unit  | test_json_transformer.sh            | OCI compute CloudEvent → OCI metric            |
| UT-37 | unit  | test_json_transformer.sh            | OCI PostgreSQL backup CloudEvent → log entry   |
| UT-38 | unit  | test_json_transformer.sh            | missing conclusion degrades gracefully         |
| UT-39 | unit  | test_json_transformer.sh            | component missing status degrades gracefully   |
| UT-40 | unit  | test_json_transformer.sh            | missing freeformTags omits optional dimension  |
| UT-41 | unit  | test_json_transformer.sh            | division by zero returns null in JSONata       |
| UT-42 | unit  | test_json_transformer.sh            | undefined function in expression → error       |
| UT-43 | unit  | test_json_transformer.sh            | invalid date passed to `$toMillis` → error     |
| UT-44 | unit  | test_json_transformer.sh            | missing workflow_run object degrades gracefully|
| UT-45 | unit  | test_json_transformer.sh            | empty components object omits metricData       |
| UT-46 | unit  | test_json_transformer.sh            | numeric component status coerces to unhealthy  |
| UT-47 | unit  | test_json_transformer.sh            | string arithmetic → error                      |
| UT-48 | unit  | test_json_transformer.sh            | `$substringAfter` no-match behavior            |
| UT-49 | unit  | test_json_transformer.sh            | strict mapping rejects missing conclusion      |
| UT-50 | unit  | test_json_transformer.sh            | strict mapping rejects missing updated_at      |
| UT-51 | unit  | test_json_transformer.sh            | strict mapping rejects missing repository name |
| UT-52 | unit  | test_json_transformer.sh            | strict mapping rejects missing workflow_run    |
| UT-53 | unit  | test_json_transformer.sh            | strict mapping rejects missing repository      |
| UT-54 | unit  | test_json_transformer_cli.sh        | CLI surfaces strict mapping assertion failure  |

## Requirements Clarified During Construction

- The library must support both raw `.jsonata` files and `.json` envelope files; examples and tests use both formats.
- JSONata evaluation is Promise-based, so both library and CLI contracts must treat transform failures as async errors.
- The transformer must support two mapping styles without special-case code:
  - permissive mappings where missing fields are omitted naturally by JSONata
  - strict mappings that enforce required inputs via `$assert($exists(...), "...")`
- Real-world coverage extends beyond the initial examples to GitHub webhook payloads, health-to-metric mappings, and OCI event reshaping, because those are already represented in the fixture corpus and exercise the reusable-library claim.
