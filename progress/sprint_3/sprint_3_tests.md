# Sprint 3 — Tests

## Environment

- bash, jq, gh CLI, OCI CLI (DEFAULT profile for log search)
- GitHub repo variable `SLI_OCI_LOG_ID` must point to the OCI custom log OCID
- GitHub repo secret `OCI_CONFIG_PAYLOAD` must contain a valid packed OCI session
- All test output includes `FAIL:` lines if assertions fail; summary line is authoritative

---

## T1 — sli-event unit tests (SLI-4)

```bash
cd /path/to/SLI_tracker
bash .github/actions/sli-event/tests/test_emit.sh
```

Expected tail:
```
== summary ==
passed: 19  failed: 0
```

**Status: PASS** (19 tests, 0 failed)

---

## T2–T7 — End-to-end integration tests (SLI-3 + SLI-4)

Scripted, executable test that:
1. Triggers `model-call` and `model-push` workflows via `gh workflow run` (success and failure variants)
2. Waits for all four runs to complete
3. Asserts expected GitHub conclusions (success / failure)
4. Verifies each sli-event step emitted `SLI log entry pushed to OCI Logging`
5. Queries OCI Logging and asserts received event counts, outcomes, failure_reasons, and job types

### Run the script

```bash
cd /path/to/SLI_tracker
bash progress/sprint_3/test_sli_integration.sh
```

### Latest result (2026-04-04)

```
=== T0: repo tooling prerequisites ===
PASS: gh CLI present
PASS: OCI CLI present
PASS: jq present

=== T1: unit tests — emit.sh helper functions ===
PASS: emit.sh unit tests: passed count
PASS: emit.sh unit tests: failed count

=== T2: model-call — success + failure workflow dispatch ===
PASS: model-call success run triggered: 23985897588
PASS: model-call failure run triggered: 23985899025

=== T3: model-push — success + failure workflow dispatch ===
PASS: model-push success run triggered: 23985900406
PASS: model-push failure run triggered: 23985901746

=== T4: wait for all four runs to complete ===
    Runs: 23985897588 23985899025 23985900406 23985901746
PASS: run 23985897588 completed
PASS: run 23985899025 completed
PASS: run 23985900406 completed
PASS: run 23985901746 completed

=== T5: expected workflow conclusions ===
PASS: model-call success → conclusion success
PASS: model-call failure → conclusion failure
PASS: model-push success → conclusion success
PASS: model-push failure → conclusion failure

=== T6: sli-event step emitted to OCI (per-job notice) ===
PASS: run 23985897588 / Delegate to reusable / Init — runner selection → init job (no SLI step expected)
PASS: run 23985897588 / Delegate to reusable / SLI — init → SLI pushed
PASS: run 23985897588 / Delegate to reusable / Main — per-env execution [model-env-1] / Leaf execution → SLI pushed
PASS: run 23985897588 / Delegate to reusable / Main — per-env execution [model-env-2] / Leaf execution → SLI pushed
PASS: run 23985899025 / Delegate to reusable / Init — runner selection → init job (no SLI step expected)
PASS: run 23985899025 / Delegate to reusable / SLI — init → SLI pushed
PASS: run 23985899025 / Delegate to reusable / Main — per-env execution [model-env-1] / Leaf execution → SLI pushed
PASS: run 23985899025 / Delegate to reusable / Main — per-env execution [model-env-2] / Leaf execution → SLI pushed
PASS: run 23985900406 / Delegate to reusable / Init — runner selection → init job (no SLI step expected)
PASS: run 23985900406 / Delegate to reusable / SLI — init → SLI pushed
PASS: run 23985900406 / Delegate to reusable / Main — per-env execution [model-env-2] / Leaf execution → SLI pushed
PASS: run 23985900406 / Delegate to reusable / Main — per-env execution [model-env-1] / Leaf execution → SLI pushed
PASS: run 23985901746 / Delegate to reusable / Init — runner selection → init job (no SLI step expected)
PASS: run 23985901746 / Delegate to reusable / SLI — init → SLI pushed
PASS: run 23985901746 / Delegate to reusable / Main — per-env execution [model-env-2] / Leaf execution → SLI pushed
PASS: run 23985901746 / Delegate to reusable / Main — per-env execution [model-env-1] / Leaf execution → SLI pushed

=== T7: OCI Logging received events — query last 15 min ===
PASS: OCI received at least 12 events (4 runs × 3 jobs)
PASS: OCI: at least 4 success outcome events
PASS: OCI: at least 4 failure outcome events
PASS: OCI: model-call events present
PASS: OCI: model-push events present
PASS: OCI: at least 4 failure events carry failure_reasons
PASS: OCI: sli-init job events present
PASS: OCI: leaf job events present

=== Summary ===
passed: 41  failed: 0
```

**Status: PASS** (41 tests, 0 failed)

---

## Bugs found and fixed during testing

| # | Symptom | Root cause | Fix |
|---|---------|------------|-----|
| B1 | `vars` context validation error in action.yml | `vars` context not available inside composite action YAML | Removed `vars.SLI_OCI_LOG_ID` from action.yml env; pass `oci.log-id` via `context-json` in callers |
| B2 | `${{ toJSON(inputs) }}` validation error in action.yml | `${{ }}` expressions in input descriptions are evaluated as templates | Rewrote descriptions to use plain text |
| B3 | `bash: command not found` (exit 127) in sli-event step | `oci_profile_setup.sh` wrote `PATH=<wrap_dir>:\$PATH` to `$GITHUB_ENV`; literal `$PATH` not expanded, breaking the runtime PATH | Removed `GITHUB_ENV` PATH line; `GITHUB_PATH` alone is correct |
| B4 | `Missing option(s) --specversion` from `oci logging-ingestion put-logs` | OCI CLI 3.77 added `--specversion` as required | Added `--specversion "1.0"` to the call |
| B5 | `InvalidParameter: No value for property 'source'` | OCI Logging batch JSON lacked required `source`, `type`, and `id` fields | Added `source`, `type`, `id` to the batch entry in `emit.sh` |
| B6 | sli-init events not pushed despite OCI setup present | `context-json` embedded `environments-json` (a JSON array) as a double-quoted string → invalid JSON → `sli_normalize_json_object` silently fell back to `{}` | Moved init outputs to `inputs-json: ${{ toJSON(needs.init.outputs) }}`; kept only OCI block in `context-json` |

---

## OCI Logging setup

| Resource | OCID |
|----------|------|
| Log group `sli-events` (tenancy root) | `ocid1.loggroup.oc1.eu-zurich-1.amaaaaaaknhfuyiajpq42txu7p3qnr7hapi4mkr46bv4tmulv4h36ghuwfpq` |
| Custom log `github-actions` | `ocid1.log.oc1.eu-zurich-1.amaaaaaaknhfuyiac44m4tbxdcents5aq5mwjievgutftkzq3aharjcytywa` |
| GitHub repo variable `SLI_OCI_LOG_ID` | set to custom log OCID above |

---

## Summary

| Item | Tests | Passed | Failed |
|------|-------|--------|--------|
| SLI-4 unit (emit.sh helpers) | 19 | 19 | 0 |
| SLI-3+4 integration (end-to-end) | 41 | 41 | 0 |
| **Total** | **60** | **60** | **0** |
