# Sprint 22 Design — SLI-35 Public OCI Function router to Object Storage (pass-through)

## SLI-35. Public OCI Function router to Object Storage (pass-through)

Status: Accepted (implementation: see `sprint_22_implementation.md`)

### Requirement Summary

Accept a routing envelope payload over a public HTTP endpoint, run it through the existing router + transformer library using a pass-through JSONata mapping (`$`), and persist the resulting document to OCI Object Storage. This produces a stable, replayable “raw ingest” stream while still exercising the same routing/transform contract as the rest of the project.

### Feasibility Analysis

**API availability:**

- OCI Functions can receive HTTP requests via OCI API Gateway using a Function backend.
- OCI Object Storage supports writing objects via the OCI SDK.
- `oci_scaffold/cycle-apigw.sh` (reference) provisions a public API Gateway wired to a Function; SLI-35 uses **`tools/cycle_apigw_router_passthrough.sh`**, which reuses those ensure scripts without modifying `oci_scaffold`.

**Technical constraints:**

- Public endpoints may require DNS propagation and deployment readiness delays (handle with retries/backoff in integration tests).
- Object Storage read-after-write can be eventually consistent (verify with retries).

**Risk assessment:**

- **Propagation delays**: API GW endpoint may return transient errors right after provisioning (mitigate with retry).
- **Consistency**: object GET after PUT may fail briefly (mitigate with retry).

### Design Overview

**Architecture:**

- A single OCI Function (`router_passthrough`) accepts an HTTP request and executes one configured router route.
- An OCI API Gateway deployment exposes the Function publicly (`PUBLIC` endpoint).
- Provisioning uses `oci_scaffold` ensure-script patterns via **`tools/cycle_apigw_router_passthrough.sh`**, including bucket creation and Fn config for **`OCI_INGEST_BUCKET`**.

**Key components:**

1. **Function handler**: reads request body, builds an envelope from Fn standard input, runs the router+transformer with `routing.json`, and delivers via the existing Object Storage destination adapter.
2. **Routing definition**: a minimal `routing.json` (single route) that references a pass-through mapping (`$`) and a single Object Storage destination.
3. **Provisioning scripts**: ensure compartment, function app, function, API GW deployment, and destination bucket (idempotent).
4. **Integration test**: calls public endpoint, then verifies the object exists in the bucket and content matches the request payload (since mapping is `$`).

**Development note (fast iteration):**

- Use compartment **`/SLI_tracker`** (`SLI_COMPARTMENT_PATH`, default) and a **stable `NAME_PREFIX`** so VCN, API Gateway, and DNS are reused; avoids tearing down and reprovisioning on every test (DNS propagation).
- Do **not** tear down API Gateway after routine Fn tests; redeploy handler code by bumping **`fn/router_passthrough/func.yaml`** and **`FN_FORCE_DEPLOY=true`**. Sprint-end cleanup: **`tests/cleanup_router_apigw_stack.sh`** (same *role* as **`tests/cleanup_sli_buckets.sh`**).

**Data flow:**

1. Client POSTs JSON payload to API Gateway endpoint.
2. API GW invokes the Function with the request payload.
3. Function runs the router+transformer:
   - selects the configured route
   - applies the pass-through mapping (`$`)
   - delivers to the Object Storage destination adapter
4. Function returns 200 with route id and delivery metadata (bucket + object name).

### Technical Specification

#### `routing.json` specification (used by the Function)

The Function uses the **existing** router library (`tools/json_router.js`) and executes a `routing.json` definition with:

- one route (exclusive)
- `transform.mapping` pointing to a JSONata file that is simply `$` (pass-through)
- destination pointing to a logical `oci_object_storage` target resolved via `adapters`

`routing.json`:

```json
{
  "adapters": {
    "oci_object_storage:raw_ingest": {
      "bucket": "<bucket-name>",
      "prefix": "ingest/"
    }
  },
  "routes": [
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

Pass-through mapping (`passthrough.jsonata`):

```text
$
```

**HTTP contract (public endpoint):**

- **Method**: `POST` (and optionally `ANY` for convenience during scaffolding)
- **Request body**: expected JSON payload (stored after pass-through mapping)
- **Response** (JSON):

```json
{
  "ok": true,
  "route": "passthrough_to_object_storage",
  "deliveries": [
    {
      "bucket": "<bucket-name>",
      "objectName": "ingest/2026-04-10T09:00:00Z_abcd1234.json"
    }
  ]
}
```

**Object Storage write contract (adapter-driven):**

- Content stored as the router output (for `$`, this is the same JSON value as input).
- Content type: `application/json` when input is JSON (best-effort).

**Object naming:**

- Prefix: `ingest/` (configurable)
- Name includes timestamp + short random suffix to avoid collisions.

**Configuration:**

- `routing.json` and `passthrough.jsonata` are packaged with the Function source (initial iteration).
- Compartment and gateway provisioned under `/SLI_tracker` (integration convention).

**Error handling:**

- Invalid/missing body: return 400 with `{ ok:false, error:"..." }`
- Object Storage write failure: return 500 and include a short error string

### Testing Strategy

**Unit tests (fast):**

- Validate object naming, payload passthrough, and error handling without calling OCI APIs (pure functions / stubs).

**Integration tests (live OCI):**

- Provision bucket + public API Gateway + Function using **`tools/cycle_apigw_router_passthrough.sh`** (oci_scaffold ensure scripts as reference).
- POST a sample JSON payload.
- Verify the object exists in the bucket and its content equals the request payload.

**Success criteria:**

- Public POST produces 200 response and creates exactly one object with matching content.

## Test Specification

### Unit

#### UT-1: Pass-through handler persists body as-is (stubbed Object Storage)

- **Input**: JSON string body
- **Expected**: `putObject(bucket, objectName, body)` called with exact bytes; response includes `bucket` and `objectName`
- **Target**: `tests/unit/test_fn_passthrough_router.sh`

### Integration

#### IT-1: Public API Gateway → Function → Object Storage persistence

- **Preconditions**: working OCI profile (default `DEFAULT`), `fn` CLI installed, public internet access
- **Steps**:
  - provision bucket + function + API GW deployment (idempotent)
  - POST sample JSON payload to the public endpoint
  - GET the created object from the bucket and compare bytes
- **Target**: `tests/integration/test_fn_apigw_object_storage_passthrough.sh`

### Traceability

- SLI-35
  - Unit: UT-1
  - Integration: IT-1

## YOLO Mode Decisions

### Decision 1: Public endpoint without auth by default

**Context**: Backlog requires “exposed to the internet” but does not specify auth.
**Decision made**: Start with a public endpoint; add API GW auth as a later enhancement if needed.
**Rationale**: Keeps Sprint 22 focused on the core persistence contract.
**Alternatives**: API key / JWT auth at API GW.
**Risk**: Medium (public endpoint exposure); mitigated by using a dedicated bucket prefix and allowing future auth.

### Decision 2: Store raw bytes, JSON as a convention

**Context**: Payload shape may evolve; requirement says “as is”.
**Decision made**: Persist raw body bytes; treat JSON only as a test payload convention.
**Rationale**: Preserves replay/audit fidelity.
**Alternatives**: Parse and re-serialize JSON.
**Risk**: Low.

---

## Design Summary

Sprint 22 adds a minimal, public ingestion point (API GW → Function) that persists incoming payloads to Object Storage using the router + `$` mapping, with function sources in **`fn/router_passthrough/`** and provisioning via **`tools/cycle_apigw_router_passthrough.sh`** (oci_scaffold ensure scripts as reference-only).
