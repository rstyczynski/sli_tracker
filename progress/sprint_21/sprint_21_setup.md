# Sprint 21 Setup — SLI-33 + SLI-34 Universal Destinations

## Contract

Rules understood: YOLO mode, unit tests only, with regression intentionally scoped to the router/transformer component instead of the entire repository unit suite.

Responsibilities:
- remove filesystem-only destination metadata from `routing.json`
- keep destination identity universal for multiple delivery adapters
- provide concrete adapters for filesystem, OCI Object Storage, OCI Monitoring, and OCI Logging
- preserve router and transformer component behavior through unit regression
- make the scoped regression gate explicit and reproducible through manifests

Constraints:
- no live OCI calls in this sprint
- no integration gate in this sprint
- adapters must stay plain Node.js modules, not framework plugins
- regression scope must still run through `tests/run.sh`

Open questions:
- destination `type` stays an open string for compatibility; adapter support is enforced in adapter code, not through a closed schema enum

## Analysis

The current router contract leaks filesystem concerns through `destination.directory`, which makes `routing.json` less reusable for HTTP, queue, and OCI adapters. The simplest correction is to keep only logical destination identity in the routing definition and move transport-specific realization into adapter configuration. Existing router behavior can be preserved if filesystem path derivation falls back to `type/name`.

The second issue is process-related: full unit regression across the repository is too broad for router/transformer-only changes. The test runner already supports manifest filtering for new-code gates, so extending that concept to a generic manifest filter is the minimal way to support component-scoped regression without building a new runner.

The sprint is feasible as a unit-only change because all target adapters can be prepared as injected-callback modules with offline fixtures and state assertions. No OCI SDK integration is required to validate the contract.
