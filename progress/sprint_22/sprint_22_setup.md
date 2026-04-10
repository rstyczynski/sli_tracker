# Sprint 22 Setup — SLI-35 Public OCI Function router to Object Storage (pass-through)

## Contract

Sprint goal: add an internet-exposed OCI Function endpoint that accepts a routing envelope payload and persists it to OCI Object Storage **without transformation** so raw inputs can be replayed/audited later.

Constraints and rules to follow:

- The routing payload is stored **as-is** (no JSONata transform; no schema mutation beyond what is required by OCI Function runtime parsing).
- Provisioning must be **idempotent** and automated using `oci_scaffold` patterns, specifically the `cycle-apigw` approach for public exposure.
- The function endpoint must be reachable from the public internet via API Gateway.
- Tests must follow the centralized runner (`tests/run.sh`) and Sprint 22 parameters in `PLAN.md` (unit + integration; regression unit).
- Integration tests must be safe to re-run and must clean up or isolate cloud resources (prefix-based buckets / compartment scoping).

Deliverables:

- A new OCI Function (pass-through router) plus an API Gateway deployment exposing it publicly.
- An Object Storage bucket and object naming scheme for persisted requests.
- Library/CLI usage notes (how to deploy + how to invoke).
- Unit tests for pure request→object behavior and config parsing.
- Integration test that posts a real request to the public endpoint and verifies object creation in the bucket.

Open questions (non-blocking, YOLO defaults apply unless clarified later):

- Authentication at the public endpoint (default: public endpoint accepts requests; protection may be added later with API GW auth).
- Envelope format strictness (default: accept any JSON payload; store raw bytes; return 2xx on successful persistence).

## Analysis

Backlog item: **SLI-35**.

What is needed:

- A minimal OCI Functions handler that:
  - accepts an HTTP request body (JSON)
  - writes the payload bytes to Object Storage
  - returns a small JSON response including the created object name and bucket

Compatibility with existing codebase:

- Existing repo already contains:
  - OCI tooling (`oci_scaffold/`, `tools/ensure_oci_resources.sh`)
  - Node-based routing/transform components (not required for pass-through)
  - integration test patterns that provision OCI resources under compartment `/SLI_tracker`

Feasibility:

- High. OCI SDK + Object Storage usage patterns exist in the repo; `oci_scaffold` is already used for idempotent provisioning in integration tests.

Risks:

- Eventual consistency in Object Storage reads after write (mitigate with retries in integration verification).
- API Gateway deployment propagation delays (mitigate with retry/backoff when probing the endpoint).

Readiness:

- Requirements are clear enough to proceed to design in YOLO mode.
