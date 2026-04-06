# Sprint 8 — Elaboration

Status: Complete

## Key Design Decisions

- emit_common.sh: verbatim copy of all pure helpers — no regressions possible
- emit_oci.sh: identical sli_emit_main push block as current emit.sh
- emit_curl.sh: OCI API-key signing via openssl; region from config file
- emit.sh: dispatcher via exec (clean process separation)
- action.yml: emit-backend input defaults to oci-cli (backward compatible)

## Artifacts

- progress/sprint_8/sprint_8_design.md

## Status

Design Accepted — ready for Construction
