# Sprint 27 — Design (SLI-44)

**Sprint test parameters (`PLAN.md`):** **`Test: unit, integration`** — Phase **A2** and **A3** are both in scope. **`Regression: unit`**.

## Problem

Sprint 26 delivers `workflow_run` → Object Storage (raw) + OCI Monitoring (completed-only metrics). Operators still need **OCI Logging** for search, retention, and correlation without replacing bucket or metrics paths.

## Design

### Adapter

- Introduce **`oci_logging`** logical destination type in `routing.json` (name TBD, e.g. `github_workflow_run`) with adapter metadata: at minimum **log OCID** or **log group + log name** resolvable at runtime from Fn environment (align with existing `SLI_OCI_LOG_URI` / scaffold patterns where possible).
- **`router_core.js`** (or shared dispatcher): register a Logging adapter when `oci_logging:*` keys exist, mirroring SLI-42’s dynamic registration.

### Route

- **`github_workflow_run_to_log`**: `mode: fanout`, `match.headers["x-github-event"]: workflow_run`, `transform.mapping` pointing to a new JSONata file (e.g. `workflow_run_log.jsonata`) unless product chooses raw passthrough.
- JSONata contract: produce one or more log-entry-shaped objects expected by the adapter (field names to match PutLogEvents wrapper in code — sprint construction refines).

### Security and operations

- Document redaction / max body size in implementation.
- Fn config keys and cycle-script merge documented alongside `OCI_MONITORING_COMPARTMENT_ID` pattern.

### Versioning

- Bump `fn/router_passthrough/func.yaml` when handler code ships.

---

## Testing Strategy

**Unit:** Extend `tests/unit/test_fn_passthrough_router.sh` (or adjacent script) with injected handler stubs: completed `workflow_run` fixture produces a third delivery path invocation (Logging) with expected payload shape; non-completed behavior per design.

**Integration:** Extend `tests/integration/test_fn_apigw_object_storage_passthrough.sh` or add `tests/integration/test_fn_workflow_run_oci_logging.sh` to assert a log entry appears in OCI Logging (poll/search) after POST — gated on env when live stack available.

**Regression:** Sprint 26 router/transformer unit manifest unchanged for B2.

**Bootstrap (Sprint 27 open):** Placeholder scripts in `new_tests.manifest` assert RUP artifacts exist and exit 0 until SLI-44 code lands; replace with real tests in construction.

---

## Test Specification

### UT-SLI44-1 — Logging adapter invoked on fanout (stub)

| ID | Input | Expect |
| --- | --- | --- |
| UT-SLI44-1 | Fixture `routing.json` extended with `oci_logging` + fanout route; stub handlers | One logging delivery call with expected structured payload (exact fields TBD in implementation) |

### UT-SLI44-2 — Non-completed run (design default)

| ID | Input | Expect |
| --- | --- | --- |
| UT-SLI44-2 | If design chooses “log all runs”: requested/in_progress envelope produces Logging call. If “completed only”: same as metrics — no Logging call for non-terminal. | Documented in `sprint_27_implementation.md` once decided |

### IT-SLI44-1 — Live APIGW + Logging

| ID | Script | Expect |
| --- | --- | --- |
| IT-SLI44-1 | Integration script (new or extended) | After POST `workflow_run`, OCI Logging search returns ≥1 matching entry within poll budget |

### SM-SLI44-1 — RUP bootstrap (placeholder)

| ID | Script | Expect |
| --- | --- | --- |
| SM-SLI44-1 | `tests/unit/test_sli44_rup_placeholder.sh` | PASS — documents sprint open |

### Traceability

| Test | Requirement |
| --- | --- |
| UT-SLI44-1..2 | SLI-44 adapter + routing |
| IT-SLI44-1 | SLI-44 live path |
| SM-SLI44-1 | RUP gate bootstrap |
