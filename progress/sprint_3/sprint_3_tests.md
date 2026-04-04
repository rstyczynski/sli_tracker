# Sprint 3 — Tests

## Overview

Two test tiers cover SLI-3 (model workflows) and SLI-4 (sli-event action):

| Tier | Script | Assertions |
|------|--------|-----------|
| Unit | `.github/actions/sli-event/tests/test_emit.sh` | 19 — emit.sh pure helpers |
| Integration | `progress/sprint_3/test_sli_integration.sh` | 41 — full GitHub → OCI round-trip |
| **Total** | | **60** |

---

## Prerequisites — one-time setup

### 1. Tools on the operator machine

| Tool | Purpose |
|------|---------|
| `gh` | GitHub CLI, authenticated (`gh auth login`) |
| `oci` | OCI CLI, with a `DEFAULT` profile (API-key, for log search) |
| `jq` | JSON processor |
| `bash` | ≥ 4.0 |

### 2. OCI Logging resources

Create once; OCIDs are recorded in the test script for reference.

```bash
# Create log group in tenancy root (do once)
oci logging log-group create \
  --compartment-id <TENANCY_OCID> \
  --display-name "sli-events" \
  --description "SLI tracking events from GitHub Actions"

# Create custom log inside it (do once)
oci logging log create \
  --log-group-id <LOG_GROUP_OCID> \
  --display-name "github-actions" \
  --log-type CUSTOM
```

Existing resources (this repo):

| Resource | OCID |
|----------|------|
| Log group `sli-events` | `ocid1.loggroup.oc1.eu-zurich-1.amaaaaaaknhfuyiajpq42txu7p3qnr7hapi4mkr46bv4tmulv4h36ghuwfpq` |
| Custom log `github-actions` | `ocid1.log.oc1.eu-zurich-1.amaaaaaaknhfuyiac44m4tbxdcents5aq5mwjievgutftkzq3aharjcytywa` |

### 3. GitHub repo variable and secret

```bash
# Set once; update the OCID if you recreated the log
gh variable set SLI_OCI_LOG_ID \
  --body "ocid1.log.oc1.eu-zurich-1.amaaaaaaknhfuyiac44m4tbxdcents5aq5mwjievgutftkzq3aharjcytywa"
```

OCI session secret — pack and upload with:

```bash
bash .github/actions/oci-profile-setup/setup_oci_github_access.sh \
  --session-profile-name SLI_TEST
```

This opens a browser for OCI login and uploads `OCI_CONFIG_PAYLOAD` to the repo secret.
**Session tokens expire (typically 1 hour); re-run this command before each test cycle.**

---

## T1 — sli-event unit tests (SLI-4)

Tests `emit.sh` pure-helper functions (no OCI, no GitHub Actions context needed).

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

Single executable script. Run from the repo root:

```bash
cd /path/to/SLI_tracker
bash progress/sprint_3/test_sli_integration.sh
```

### What the script does

| Step | Description |
|------|-------------|
| T0 | Assert gh, oci, jq are present |
| T1 | Run unit tests and assert 19/19 pass |
| T2 | Dispatch `model-call` success + failure runs via `gh workflow run` |
| T3 | Dispatch `model-push` success + failure runs |
| T4 | Poll every 30 s until all four runs reach `completed` |
| T5 | Assert GitHub conclusions match simulate-failure inputs |
| T6 | Fetch per-job logs; assert each `sli-event` step emitted a push notice |
| T7 | Wait 30 s for OCI ingestion latency; query OCI Logging; assert ≥12 events, success/failure/failure_reasons/sli-init/leaf counts |

### Expected output structure

```
=== T0: repo tooling prerequisites ===
PASS: gh CLI present
PASS: OCI CLI present
PASS: jq present
...
=== Summary ===
passed: 41  failed: 0
```

Any `FAIL:` line indicates a regression. Exit code 0 = all pass, 1 = any failure.

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

## Bugs found and fixed during integration testing

Integration testing revealed six additional bugs not caught during code review:

| # | Symptom | Root cause | Fix |
|---|---------|------------|-----|
| B1 | `vars` context validation error in action.yml | `vars` context not valid inside composite action YAML expressions | Removed `vars.SLI_OCI_LOG_ID` from action.yml env; callers pass `oci.log-id` via `context-json` (where `vars` is valid) |
| B2 | `${{ toJSON(inputs) }}` validation error in action.yml | `${{ }}` expressions inside YAML `description:` strings are evaluated as templates | Rewrote descriptions to plain text without expression examples |
| B3 | `bash: command not found` (exit 127) in sli-event step | `oci_profile_setup.sh` wrote `PATH=<dir>:\$PATH` to `$GITHUB_ENV`; `$PATH` is not expanded by the GITHUB_ENV reader, leaving PATH as a literal string | Removed GITHUB_ENV PATH assignment; `GITHUB_PATH` alone correctly prepends the wrapper dir |
| B4 | `Missing option(s) --specversion` from `oci logging-ingestion put-logs` | OCI CLI 3.77 made `--specversion` required (CloudEvents spec version) | Added `--specversion "1.0"` to the call |
| B5 | `InvalidParameter: No value for property 'source'` from OCI Logging | OCI Logging batch JSON requires `source`, `type`, and `id` fields per entry | Added `source: "github-actions/sli-tracker"`, `type: "sli-event"`, `id: "<ts>-sli"` to the batch |
| B6 | sli-init events silently not pushed despite OCI setup present | `context-json` embedded `environments-json` (a raw JSON array) inside a double-quoted string → invalid JSON → `sli_normalize_json_object` silently fell back to `{}`; `oci.log-id` was lost | Moved init outputs to `inputs-json: ${{ toJSON(needs.init.outputs) }}`; kept only OCI block in `context-json` |

---

## Summary

| Item | Tests | Passed | Failed |
|------|-------|--------|--------|
| SLI-4 unit (emit.sh helpers) | 19 | 19 | 0 |
| SLI-3+4 integration (end-to-end) | 41 | 41 | 0 |
| **Total** | **60** | **60** | **0** |
