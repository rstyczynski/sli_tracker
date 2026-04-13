# RUP Test-First Quality Gates Patch

**Status:** Experimental -- being validated in this repository before integration into RUPStrikesBack submodule.

**Precedence:** Agents MUST read this document after reading `RUPStrikesBack/rules/generic/GENERAL_RULES.md`. Where rules conflict, this patch takes precedence.

**Discovery chain:** The RUP Manager (`rup-manager.md`) instructs agents to read all rules in `rules/generic/`. After that step, agents must also check for `agent_qualitygate.md` at the project root. If it exists, read it and apply its overrides. This discovery is reliable because it is a fixed, well-known path in the project root -- no dynamic lookup needed.

---

# Part 1: Active Process Override

This section defines the test-first process changes that are active in this repository. It overrides specific sections of the standard RUP Strikes Back process.

## 1. Sprint Test Parameter

Each sprint in `PLAN.md` gains a new `Test:` field alongside `Mode:`:

```markdown
## Sprint N - Feature Name

Status: Progress
Mode: YOLO
Test: unit, integration
Regression: yes
```

### Test: Valid Values (comma-separated)

| Value | Meaning |
|-------|---------|
| `unit` | Unit tests required. Phase 3.1 produces unit test skeletons in `tests/unit/`. Unit test gate enforced in Construction. |
| `integration` | Integration tests required. Phase 3.1 produces integration test skeletons in `tests/integration/`. Integration test gate enforced in Construction. |
| `smoke` | Smoke tests required. Phase 3.1 selects or creates a small subset of the most critical test cases (unit and/or integration) in `tests/smoke/`. These run quickly and answer "is the build testable at all?" If smoke fails, full testing is skipped -- the build is too broken. Runs before unit and integration gates. |
| `none` | No new tests for this sprint. Useful for review-only or documentation-only sprints. Regression still runs. |

### Combinations and Defaults

- `Test: unit` -- pure logic changes with no infrastructure dependency
- `Test: smoke, integration` -- quick critical check + full end-to-end
- `Test: smoke, unit, integration` -- full suite with quick gate first
- `Test: unit, integration` -- **default if `Test:` is omitted**
- `Test: none` -- skip new-code tests (regression still mandatory)

### Interaction with Mode

- **managed** mode: all specified test levels must reach 100% pass rate. Failures block and require human decision.
- **YOLO** mode: unit tests must always reach 100%. Integration tests allow a documented degradation threshold (>=80% pass rate with all failures explained). Smoke test failures always block.
- Regression is mandatory in both modes with no exceptions.

### Regression: Parameter

Controls which levels of existing tests the Constructor re-runs after the sprint's new-code tests pass. Uses the same levels as `Test:`.

| Value | Meaning |
|-------|---------|
| `smoke` | Re-run smoke tests (fastest -- just verify critical paths aren't broken) |
| `unit` | Re-run all unit tests (old + new). Catches logic regressions. |
| `integration` | Re-run all integration tests (old + new). Catches end-to-end regressions. Slowest. |
| `none` | Skip regression entirely. For experimental/throwaway sprints. |

**Combinations and defaults:**

- `Regression: unit` -- re-run all unit tests only (good balance of speed and safety)
- `Regression: smoke` -- fastest regression, just critical paths
- `Regression: smoke, unit` -- critical paths + all unit tests
- `Regression: unit, integration` -- **default if omitted** (full regression)
- `Regression: smoke, unit, integration` -- maximum safety
- `Regression: none` -- skip regression (use sparingly)

**Execution:** Regression gates run AFTER the sprint's new-code gates pass. The Constructor calls `tests/run.sh` for each regression level separately:

```bash
tests/run.sh --smoke         # if Regression: includes smoke
tests/run.sh --unit          # if Regression: includes unit
tests/run.sh --integration   # if Regression: includes integration
```

If any regression gate fails, the sprint is marked `failed` -- the new code broke existing functionality.

**Example sprint configurations:**

```markdown
## Sprint 7 - Critical security fix
Mode: managed
Test: unit, integration
Regression: smoke, unit, integration    # full safety, this is risky

## Sprint 8 - Minor refactor
Mode: YOLO
Test: unit
Regression: unit                        # unit regression is enough

## Sprint 9 - Documentation only
Mode: YOLO
Test: none
Regression: smoke                       # quick sanity check, nothing changed

## Sprint 10 - Experiment
Mode: YOLO
Test: unit
Regression: none                        # throwaway, skip regression
```

### Detection by Agents

Each agent reads `PLAN.md`, finds the active sprint (Status: Progress), and reads the `Test:` and `Regression:` fields. Defaults: `Test: unit, integration`, `Regression: unit, integration`.

---

## 2. Updated Phase Flow

The standard 5-phase flow gains Phase 3.1 between Elaboration and Construction:

```
Phase 1: Contracting           (unchanged)
Phase 2: Inception              (unchanged)
Phase 3: Elaboration            (unchanged)
Phase 3.1: Test Specification   (NEW -- this patch)
Phase 4: Construction           (MODIFIED -- code only, no test creation)
Phase 4.1: Test Execution       (NEW -- this patch, quality gates)
Phase 5: Documentation          (unchanged)
```

Phase 4 (Construction) implements code. Phase 4.1 (Test Execution) runs the quality gates -- first new-code gates (`Test:`), then regression gates (`Regression:`). The Test Executor Agent runs gates and reports results; on failure, the Constructor Agent fixes and the Test Executor re-runs -- up to 10 retries per gate. Phase 5 is only reached after all gates in 4.1 pass.

---

## 3. Phase 3.1: Test Specification

**Role:** Test Architect
**Phase:** 3.1/5 -- between Elaboration and Construction
**Prerequisite:** Phase 3 (Elaboration) complete, design document accepted.

### Responsibilities

1. Read the approved design document (`progress/sprint_${no}/sprint_${no}_design.md`)
2. Read the sprint's `Test:` parameter from `PLAN.md`
3. Produce test specification document
4. Produce executable test skeletons in the centralized `tests/` tree
5. Update PROGRESS_BOARD.md with `test_specified` status
6. Commit and push

### Step 0: Detect Test Scope

Read `PLAN.md` and extract the `Test:` field for the active sprint:
- If `Test:` includes `smoke` -- select or create a small subset of the most critical test cases (from unit and/or integration scope) that run quickly and determine if the build is testable
- If `Test:` includes `unit` -- produce unit test specifications and skeletons
- If `Test:` includes `integration` -- produce integration test specifications and skeletons
- If `Test: none` -- produce only the test spec document noting "no new tests; regression only"

### Step 1: Create Test Specification Document

Create `progress/sprint_${no}/sprint_${no}_test_spec.md` with this structure:

```markdown
# Sprint ${no} - Test Specification

## Sprint Test Configuration
- Test: [value from PLAN.md]
- Mode: [value from PLAN.md]

## Smoke Tests (if Test: includes smoke)

Smoke tests are their own test type: small, fast, self-contained scripts that
live in `tests/smoke/`. They cover the most critical functionality to answer
"is the build testable at all?" They are NOT tags on unit/integration tests --
they are separate scripts written specifically to be fast (seconds, not minutes).

A smoke test may exercise unit-level logic (e.g. "does emit.sh produce valid JSON?")
or integration-level paths (e.g. "can we push one event to OCI?"), but the script
itself lives in `tests/smoke/` and runs independently.

### SM-1: [Critical Functionality Check]
- **What it verifies:** [most important behavior]
- **Pass criteria:** [expected result]
- **Why it's smoke:** [why this is critical enough for the fast gate]
- **Target file:** tests/smoke/test_[name].sh

## Unit Tests (if Test: includes unit)

### UT-1: [Function/Script Under Test]
- **Input:** [defined input]
- **Expected Output:** [exact expected output]
- **Edge Cases:** [boundary conditions]
- **Isolation:** [mocks/stubs needed]
- **Target file:** tests/unit/test_[component].sh (append to existing or create new)

## Integration Tests (if Test: includes integration)

### IT-1: [End-to-End Scenario]
- **Preconditions:** [infrastructure, secrets, tools]
- **Steps:** [ordered sequence]
- **Expected Outcome:** [observable result]
- **Verification:** [how to assert]
- **Target file:** tests/integration/test_[domain].sh (append to existing or create new)

## Traceability

| Backlog Item | Smoke | Unit Tests | Integration Tests |
|---|---|---|---|
| SLI-N | SM-1 | UT-1, UT-2, UT-3 | IT-1, IT-2 |
```

### Step 2: Create Executable Test Skeletons

For each test case in the specification, write (or append to) the corresponding script in `tests/`:

- All test case functions stubbed with assertions defined
- Use `# TODO: implement` markers where the code-under-test will be called
- Pass/fail counting wired into the existing framework in the file
- New test cases are **appended** to existing files (one file per component/domain, not per sprint)

The skeletons must be runnable immediately. Before implementation they will all fail (red). Construction makes them pass (green).

### Step 2a: Write New-Tests Manifest

Create `progress/sprint_${no}/new_tests.manifest` listing every test script and function added by this sprint. This file is consumed by `tests/run.sh --new-only` to run only the sprint's new tests (Phase A gates) without running the full regression suite.

Format (one entry per line):

```
# tests/smoke/test_critical_emit.sh
smoke:test_critical_emit.sh

# tests/unit/test_emit.sh -- specific new functions
unit:test_emit.sh:test_sli_unescape_json_fields
unit:test_emit.sh:test_sli_unescape_nested_objects

# tests/integration/test_sli_integration.sh -- specific new functions
integration:test_sli_integration.sh:test_T8_native_environments
```

Each line is `suite:script_name[:function_name]`. If no function name is given, the entire script is new. The Test Architect writes this manifest alongside the skeletons. `run.sh --new-only` reads it to filter which tests to execute in Phase A gates.

### Step 3: Verify Skeletons Run

Execute `tests/run.sh` with the appropriate flags to confirm skeletons are syntactically valid and produce expected failures:

```bash
tests/run.sh --unit    # should report N failures, 0 passes for new tests
tests/run.sh --smoke   # should pass (preconditions are about infrastructure, not code)
```

### Step 4: Update PROGRESS_BOARD.md

Set Backlog Item status to `test_specified`.

### Step 5: Commit and Push

Commit with: `test(sprint-${no}): add test specifications for [brief description]`

### YOLO Mode Behaviors

- Auto-proceed after creating specs (no review wait)
- Make reasonable test scope decisions based on design complexity
- Log decisions in the test spec document

### Managed Mode Behaviors

- Wait for Product Owner to review test specifications
- Ask about edge cases and negative scenarios
- Confirm test scope is adequate

---

## 4. Construction Phase Overrides

These rules **replace** the corresponding sections in `agent-constructor.md`.

### Override: Step 4 (was "Create Functional Tests")

**REPLACED BY:** Execute pre-existing test skeletons from Phase 3.1.

The Constructor Agent does NOT create new test cases. Tests were already specified and skeletonized in Phase 3.1. The Constructor:

1. Implements code to satisfy the design
2. Fills in any `# TODO: implement` stubs left by the Test Architect (if the skeleton needed the implementation to exist first)
3. Does NOT invent new test cases -- if coverage is missing, flag it in `sprint_${no}_tests.md` for next sprint

---

## 4a. Phase 4.1: Test Execution (Quality Gates)

**Role:** Test Executor Agent
**Phase:** 4.1/5 -- between Construction and Documentation
**Prerequisite:** Phase 4 implementation complete.

The Test Executor runs the quality gates objectively and reports results. When gates fail, it hands a failure report back to the Constructor Agent (Phase 4) with details on what broke. The Constructor fixes, then the Test Executor re-runs. Up to 10 retries per gate.

This separation ensures the agent that wrote the code is not the one judging if it passes.

### Mandatory Test Log Artifacts

**Every gate execution MUST produce a timestamped log file. This is non-negotiable.**

Log files are the proof of execution — without them, test results are unverifiable. A gate is not considered executed unless its log file exists.

**Log file naming and location:**

```text
progress/sprint_${no}/test_run_<gate>_<timestamp>.log
```

Where `<gate>` is one of: `A1_smoke`, `A2_unit`, `A3_integration`, `B1_smoke`, `B2_unit`, `B3_integration`.

**How to produce the log — wrap every gate invocation:**

```bash
TS="$(date -u '+%Y%m%d_%H%M%S')"
LOG="progress/sprint_${no}/test_run_A2_unit_${TS}.log"
tests/run.sh --unit --new-only progress/sprint_${no}/new_tests.manifest \
  2>&1 | tee "$LOG"
echo "Test log: $LOG"
```

Alternatively, if the test script writes its own log (e.g. integration tests with `exec > >(tee)`), the log path must still be reported and recorded in `sprint_${no}_tests.md`.

**The Test Executor MUST:**

1. Create the log file before running the gate (or capture output to it).
2. Print the log path at the end of each gate run.
3. Record all log file paths in `sprint_${no}_tests.md` under an `## Artifacts` section.
4. Never mark a gate as passed or failed without an existing log file.

### Two-Phase Gate Execution

#### Phase A: New-Code Gates (driven by `Test:` parameter)

Run only the new test functions added by this sprint's Phase 3.1. Each gate must pass before the next:

**Gate A1 -- Smoke** (if `Test:` includes `smoke`):
```bash
TS="$(date -u '+%Y%m%d_%H%M%S')"
LOG="progress/sprint_${no}/test_run_A1_smoke_${TS}.log"
tests/run.sh --smoke --new-only progress/sprint_${no}/new_tests.manifest 2>&1 | tee "$LOG"
```
Quick critical subset for the new code. If smoke fails, the build is too broken -- skip remaining gates.

**Gate A2 -- Unit** (if `Test:` includes `unit`):
```bash
TS="$(date -u '+%Y%m%d_%H%M%S')"
LOG="progress/sprint_${no}/test_run_A2_unit_${TS}.log"
tests/run.sh --unit --new-only progress/sprint_${no}/new_tests.manifest 2>&1 | tee "$LOG"
```
New unit tests must pass. Retry loop (see retry policy below). After exhaustion, mark sprint `failed`.

**Gate A3 -- Integration** (if `Test:` includes `integration`):
```bash
TS="$(date -u '+%Y%m%d_%H%M%S')"
LOG="progress/sprint_${no}/test_run_A3_integration_${TS}.log"
tests/run.sh --integration --new-only progress/sprint_${no}/new_tests.manifest 2>&1 | tee "$LOG"
```
New integration tests must pass. Retry loop (see retry policy below). After exhaustion, mark sprint `failed`.

#### Phase B: Regression Gates (driven by `Regression:` parameter)

After all new-code gates pass, re-run existing tests at the levels specified by `Regression:`. This catches breakage of previously working functionality:

**Gate B1 -- Smoke Regression** (if `Regression:` includes `smoke`):
```bash
TS="$(date -u '+%Y%m%d_%H%M%S')"
LOG="progress/sprint_${no}/test_run_B1_smoke_${TS}.log"
tests/run.sh --smoke 2>&1 | tee "$LOG"
```
Quick check that critical paths still work. Fastest regression option.

**Gate B2 -- Unit Regression** (if `Regression:` includes `unit`):
```bash
TS="$(date -u '+%Y%m%d_%H%M%S')"
LOG="progress/sprint_${no}/test_run_B2_unit_${TS}.log"
tests/run.sh --unit 2>&1 | tee "$LOG"
```
All unit tests (old + new). If any fail, the new code broke something.

**Gate B3 -- Integration Regression** (if `Regression:` includes `integration`):
```bash
TS="$(date -u '+%Y%m%d_%H%M%S')"
LOG="progress/sprint_${no}/test_run_B3_integration_${TS}.log"
tests/run.sh --integration 2>&1 | tee "$LOG"
```
All integration tests (old + new). Slowest but most thorough.

If any regression gate fails after retries are exhausted, mark sprint `failed`.

If `Regression: none`, skip Phase B entirely.

### Retry Policy

Each gate has a retry budget of 10 attempts. On failure, the Test Executor hands a failure report to the Constructor, who fixes the issue, and the Test Executor re-runs. The policy differs by mode:

**Managed mode:**
- Retries 1-4: automatic fix-and-rerun cycle between Constructor and Test Executor.
- **Retry 5: human escalation.** The Test Executor pauses and presents a decision to the Product Owner:
  - Continue retrying (grant 5 more attempts)
  - Mark sprint `failed` and stop
  - Reclassify the failure (see flaky vs broken below)
- Retries 6-10: continue if approved at retry 5.
- After retry 10: sprint is `failed`, no further retries.

**YOLO mode:**
- All 10 retries execute automatically with no human escalation.
- Each failure is logged with increasing detail (stack traces, diff of fix attempts).
- After retry 10: sprint is `failed`.

**Flaky vs broken distinction:** When the Test Executor reports a failure, it classifies it:
- **Broken**: the test fails deterministically. The code has a bug. Fix required.
- **Flaky**: the test fails intermittently (infrastructure timeout, race condition, expired credential). The Test Executor notes the failure as flaky if re-running the same code produces different results.

In managed mode, flaky failures can be deferred to a known-issues list at the human escalation point (retry 5) rather than blocking the sprint. In YOLO mode, flaky failures are documented but do not consume retry budget -- only the first occurrence counts.

### YOLO Mode Degradation Threshold

In YOLO mode, integration tests (Gates A3 and B3) may pass with a documented degradation threshold:

- The threshold is evaluated **after each attempt**: if a single run achieves >=80% pass rate, the gate passes immediately with the failures documented in `sprint_${no}_tests.md`.
- The 10-retry loop only applies when pass rate is **below** 80%. Each retry is a chance to fix code and raise the rate above the threshold.
- After 10 attempts without reaching 80%, mark sprint `failed`.
- Unit tests and smoke tests have **NO threshold** -- 100% required regardless of mode.

### Override: rup-manager.md Line 125

The line "Proceed to Phase 5 regardless of test results (partial success is acceptable and will be documented)" is **overridden**.

**New rule:** Phase 5 (Documentation) is only reached after ALL active gates (new-code + regression) pass (or meet YOLO degradation threshold). If gates fail after retries, the sprint is marked `failed` and Construction halts.

---

## 5. Centralized Test Directory Structure

All executable test scripts live in `tests/` at the repo root:

```
tests/
  smoke/
    test_critical_emit.sh          # quick: does emit.sh produce valid JSON at all?
    test_critical_oci.sh           # quick: can we reach OCI and push one event?
  unit/
    test_emit.sh                   # unit tests for emit.sh
    test_install_oci_cli.sh        # unit tests for install script
    test_oci_profile_setup.sh      # unit tests for profile setup
  integration/
    test_sli_integration.sh        # end-to-end SLI pipeline test
  run.sh                           # test runner entry point
```

### Principles

- **One file per component/domain, not per sprint.** New test cases are appended as functions to existing files.
- **Tests evolve cumulatively.** Previous test cases remain in the same files. Running `--unit` or `--integration` always exercises every test ever written -- old and new. This is how regression works: it is not a separate step, it is inherent in every gate.
- **`run.sh`** is the single entry point. Accepts `--smoke`, `--unit`, `--integration`, `--all`. Returns nonzero on any failure.

### Sprint Directory (documentation and artifacts only)

```
progress/sprint_N/
  sprint_N_contract.md             # Phase 1
  sprint_N_analysis.md             # Phase 2
  sprint_N_design.md               # Phase 3
  sprint_N_test_spec.md            # Phase 3.1 (test specifications)
  sprint_N_implementation.md       # Phase 4
  sprint_N_tests.md                # Phase 4 (execution results only)
  test_run_<timestamp>.log         # Phase 4 (execution log)
  oci_logs_<timestamp>.json        # Phase 4 (OCI capture)
  sprint_N_documentation.md        # Phase 5
```

---

## 6. Updated PROGRESS_BOARD.md States

The following states are added to the Backlog Item status values:

| State | Meaning |
|-------|---------|
| `under_analysis` | (existing) Analysis in progress |
| `analysed` | (existing) Analysis complete |
| `under_design` | (existing) Design in progress |
| `designed` | (existing) Design approved |
| `test_specified` | **(NEW)** Test specs and skeletons written, ready for construction |
| `under_construction` | (existing) Implementation in progress |
| `smoke_passed` | **(NEW)** Critical subset of tests pass; build is testable |
| `unit_tested` | **(NEW)** All unit tests pass (includes regression -- old + new) |
| `integration_tested` | **(NEW)** All integration tests pass (includes regression -- old + new) |
| `tested` | (existing) All active gates passed |
| `implemented` | (existing) Code complete |
| `failed` | (existing) Hard stop after gate failure |

---

## 7. Migration Status

Existing tests have not yet been migrated to the centralized `tests/` tree.

**Important rule during migration:** Quality gates (Phase 4.1) run ONLY against the `tests/` tree. Old test locations (`.github/actions/*/tests/`, `progress/sprint_*/test_*.sh`) are NOT scanned by `run.sh`. This means:
- Until a test is migrated to `tests/`, it is not part of any gate or regression.
- Migration should be done as a dedicated sprint (suggested: add to `PLAN.md` as a migration sprint with `Test: none, Regression: none`).

**Migration table:**

| Current Location | Target Location | Status |
|---|---|---|
| `.github/actions/sli-event/tests/test_emit.sh` | `tests/unit/test_emit.sh` | pending |
| `.github/actions/install-oci-cli/tests/test_install_oci_cli.sh` | `tests/unit/test_install_oci_cli.sh` | pending |
| `.github/actions/oci-profile-setup/tests/test_oci_profile_setup.sh` | `tests/unit/test_oci_profile_setup.sh` | pending |
| `progress/sprint_6/test_sli_integration.sh` (latest) | `tests/integration/test_sli_integration.sh` | pending |
| `progress/sprint_3-5/test_sli_integration.sh` (older copies) | archived (superseded by sprint 6 version) | pending |

**Migration procedure per test file:**
1. Copy the file to its target location in `tests/`.
2. Verify the copied script runs correctly from the new location: `tests/run.sh --unit` (or `--integration`).
3. Replace the old file with a one-line wrapper:
   ```bash
   #!/usr/bin/env bash
   exec "$(dirname "$0")/../../tests/unit/test_emit.sh" "$@"
   ```
   This preserves backward compatibility for any CI or scripts referencing the old path.
4. Commit the migration and wrapper together.

---

# Part 2: How to Patch RUPStrikesBack

Once this approach is validated in SLI_tracker, apply the following changes to the RUPStrikesBack submodule. Each entry describes the file, section, and exact change.

## 2.1 GENERAL_RULES.md

**File:** `RUPStrikesBack/rules/generic/GENERAL_RULES.md`

### Change A: Add Test: sprint parameter (after Mode definitions, ~line 153)

Insert a new section defining the `Test:` parameter. Content: Section 1 of Part 1 above ("Sprint Test Parameter").

### Change B: Update Cooperation Flow (lines 218-293)

Replace the 5-phase workflow with 6 phases. Between Phase 3 (Elaboration) and Phase 4 (Construction), insert:

```markdown
### Phase 3.1: Test Specification

1. Test Architect Agent reads approved design from Phase 3
2. Reads sprint's `Test:` parameter from PLAN.md
3. Creates test specification document in sprint directory
4. Creates/extends executable test skeletons in centralized `tests/` tree
5. Updates PROGRESS_BOARD.md with `test_specified` status
6. Commits test specifications and skeletons

**Outputs:**

- `progress/sprint_${no}/sprint_${no}_test_spec.md`
- New/updated test scripts in `tests/smoke/`, `tests/unit/`, `tests/integration/`
```

### Change C: Update PROGRESS_BOARD.md states (lines 155-217)

Add new states: `test_specified`, `smoke_passed`, `unit_tested`, `integration_tested`. See Section 6 of Part 1.

### Change D: Update Testing section (lines 417-508)

Add centralized `tests/` directory structure definition. Add unit/integration/smoke test distinction. Add `run.sh` runner specification. See Section 5 of Part 1.

## 2.2 rup-manager.md

**File:** `RUPStrikesBack/.claude/commands/rup-manager.md`

### Change A: Insert Phase 3.1 (between Phase 3 and Phase 4, after line 114)

```markdown
## Phase 3.1: Execute Test Specification

Read `.claude/commands/agents/agent-test-architect.md` and execute all its instructions.

**Important**: After completing this phase, commit all changes following semantic commit message conventions as described in `rules/generic/GIT_RULES*`. Push to remote after commit.

This phase creates test specifications and executable test skeletons based on the approved design. Test skeletons are placed in the centralized `tests/` tree.

**Decision Point**: If test scope is unclear, stop and request clarification before proceeding to Phase 4.
```

### Change B: Insert Phase 4.1 (between Phase 4 and Phase 5, replacing line 125)

**Remove:**
```
Proceed to Phase 5 regardless of test results (partial success is acceptable and will be documented).
```

**Replace with:**
```markdown
## Phase 4.1: Execute Test Execution

Read `.claude/commands/agents/agent-test-executor.md` and execute all its instructions.

**Important**: After completing this phase, commit all changes following semantic commit message conventions as described in `rules/generic/GIT_RULES*`. Push to remote after commit.

This phase runs quality gates: new-code gates (driven by Test: parameter) then regression gates (driven by Regression: parameter). On failure, the Test Executor hands details back to the Constructor for fixing, then re-runs.

Phase 5 is only reached after ALL active quality gates pass. If gates fail after 10 retries per gate, the sprint is marked `failed`.
```

### Change C: Update Execution Checklist (lines 222-230)

Add Phase 3.1 step between Phase 3 and Phase 4:
```markdown
- [ ] **Step 3.1: Phase 3.1 - Test Specification** - Execute agent-test-architect.md, commit, push
```

Add Phase 4.1 step between Phase 4 and Phase 5:
```markdown
- [ ] **Step 4.1: Phase 4.1 - Test Execution** - Execute agent-test-executor.md, commit, push
```

## 2.3 agent-designer.md

**File:** `RUPStrikesBack/.claude/commands/agents/agent-designer.md`

### Change: Add testing strategy output

In the design document template, add a section that the Designer produces as primary input for Phase 3.1. This must be prescriptive enough for the Test Architect to produce test specifications without guessing:

```markdown
### Testing Strategy

#### Recommended Sprint Parameters
- Test: [smoke, unit, integration -- with rationale for each]
- Regression: [smoke, unit, integration -- with rationale]

#### Unit Test Targets
For each component modified or created:
- **Component:** [file path, e.g. `.github/actions/sli-event/emit.sh`]
- **Functions to test:** [specific function names]
- **Key inputs and edge cases:** [concrete examples]
- **Isolation requirements:** [what to mock -- e.g. "mock OCI CLI responses"]

#### Integration Test Scenarios
For each end-to-end path affected:
- **Scenario:** [description]
- **Infrastructure dependencies:** [OCI tenancy, GitHub API, specific secrets]
- **Expected observable outcome:** [what to assert in OCI logs, workflow status]
- **Estimated runtime:** [seconds/minutes -- informs smoke vs integration decision]

#### Smoke Test Candidates
Which of the above tests are critical enough to be smoke tests:
- **Candidate:** [test description]
- **Why it's critical:** [what breaks if this fails]
- **Expected runtime:** [must be fast -- seconds, not minutes]
```

## 2.4 agent-constructor.md

**File:** `RUPStrikesBack/.claude/commands/agents/agent-constructor.md`

### Change A: Replace Step 4 "Create Functional Tests" (lines 130-223)

Replace with: "Execute pre-existing test skeletons from Phase 3.1 using `tests/run.sh`. Do NOT create new test cases." See Section 4 of Part 1.

### Change B: Replace Step 5 "Execute Test Loop" (lines 225-241)

Remove test execution from the Constructor. Test execution moves to Phase 4.1, owned by the Test Executor Agent.

### Change C: Update YOLO Mode Behaviors (line 40)

Replace "Proceed with partial test success (document failures, don't block)" with:
- Unit tests, smoke tests: 100% required, no exceptions
- Integration tests: >=80% pass rate with documented failures

## 2.5 agent-test-architect.md (NEW FILE)

**File:** `RUPStrikesBack/.claude/commands/agents/agent-test-architect.md`

Create this file with the full contents of Section 3 of Part 1 ("Phase 3.1: Test Specification"), formatted as an agent instruction file matching the style of `agent-constructor.md`.

## 2.6 agent-test-executor.md (NEW FILE)

**File:** `RUPStrikesBack/.claude/commands/agents/agent-test-executor.md`

Create this file with the full contents of Section 4a of Part 1 ("Phase 4.1: Test Execution"), formatted as an agent instruction file. Responsibilities:
- Run quality gates using `tests/run.sh`
- Execute new-code gates (Phase A) then regression gates (Phase B)
- Report failures objectively back to Constructor for fixing
- Track retry count per gate (up to 10)
- Update PROGRESS_BOARD.md with gate status (`smoke_passed`, `unit_tested`, `integration_tested`, `tested`, `failed`)

## 2.7 AGENTS.md

**File:** `RUPStrikesBack/AGENTS.md`

### Change: Add Phase 3.1 and Phase 4.1 to quick-start

In the "To execute individual phases" section, add:

```markdown
@agent-test-architect.md   # Phase 3.1: Test Specification
@agent-test-executor.md    # Phase 4.1: Test Execution
```

Between the designer and constructor entries, and between constructor and documentor entries respectively.
