# Sprint 25 — Tests (YOLO)

Sprint mode: **YOLO**. `Test: unit, integration`. `Regression: unit`.

## Status: PASS

## Gates

| Gate | Result |
| --- | --- |
| A2 Unit (`test_fn_passthrough_router.sh`) | PASS — 6/6 |
| A3 Integration (`test_fn_apigw_object_storage_passthrough.sh`) | PASS — 1/1 |
| B2 Unit regression (14-file manifest) | PASS — 14/14 |

## Unit test run

```text
[PASS] runRouter pass-through, GitHub header prefixes, and source_meta object names
[PASS] BUG-2: buildLoadMappingFromRef handles generic mapping refs
[PASS] BUG-3: routing without oci_object_storage:raw_ingest no longer throws
[PASS] SLI-42: oci_object_storage-only routing does not activate monitoring adapter
[PASS] SLI-42: oci_monitoring adapter activates automatically when present in routing definition
[PASS] SLI-42: empty transform output skips postMetricData
=== Summary ===
passed: 6  failed: 0
PASS
```

## New test cases

| ID | Description |
| --- | --- |
| UT-SLI42-1 | `oci_object_storage`-only routing: monitoring emit never called |
| UT-SLI42-2 | Fanout routing with `oci_monitoring` adapter: monitoring emit fires, `compartmentId` injected |
| UT-SLI42-3 | Transform returning `[]`: `postMetricData` skipped; Object Storage emit unaffected |
