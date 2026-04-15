# Sprint 29 — Quality Gates (SLI-48)

## Status: PASS

## Gates executed

| Gate | Command | Result | Retries |
| ---- | ------- | ------ | ------- |
| A2 Unit | `tests/run.sh --unit --new-only progress/sprint_29/new_tests.manifest` | PASS (2/2) | 0 |
| A3 Integration | `tests/run.sh --integration --new-only progress/sprint_29/new_tests.manifest` | PASS (1/1) | 0 |
| B2 Unit | `tests/run.sh --unit --component router` | PASS (14/14) | 0 |
| B3 Integration | `tests/run.sh --integration --component router` | PASS (7/7) | 0 |

## Gate details

### A2 — New-code unit gate

- `test_json_router_cli.sh` now validates single-envelope and `stdin` CLI delivery through file-system destinations.
- `test_json_pipeline_cli.sh` now validates transform-to-router piping through real file-system delivery.

### A3 — New-code integration gate

- `test_json_router_cli_mapping_oci_object_storage.sh` loads mapping content from OCI Object Storage and verifies the CLI stores the routed payload back into OCI Object Storage through the real adapter path.

### B2 / B3 — Router regression

- Router unit regression remained green after the CLI runtime change.
- Router integration regression remained green, including the live Fn/API Gateway passthrough stack and the OCI Object Storage mapping/delivery flows.

## Artifacts

- `progress/sprint_29/test_run_A2_unit_20260414_131521.log`
- `progress/sprint_29/test_run_A3_integration_20260414_131529.log`
- `progress/sprint_29/test_run_B2_unit_20260414_131540.log`
- `progress/sprint_29/test_run_B3_integration_20260414_131602.log`
