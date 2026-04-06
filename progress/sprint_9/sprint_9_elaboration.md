# Sprint 9 — Elaboration

## Design Overview

- New `model-emit-curl.yml` workflow (no OCI CLI install, uses `emit-backend: curl`)
- Small enhancement to `emit_curl.sh` for session token support
- Integration test dispatching the workflow and verifying OCI Logging

## Key Design Decisions

1. `oci-auth-mode: none` to bypass OCI CLI requirement in profile setup
2. `x-security-token` header support in `emit_curl.sh` for session-based profiles
3. Integration test follows existing T2–T7 pattern from `test_sli_integration.sh`

## Artifacts

- `progress/sprint_9/sprint_9_design.md`

## Status

Design Accepted — Ready for Construction
