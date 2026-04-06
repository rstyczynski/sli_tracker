# RUP Cycle Manager - Patched with Test-First Quality Gates

Execute the complete Rational Unified Process cycle with test-first quality gates.

This is a **wrapper** around the standard `RUPStrikesBack/.claude/commands/rup-manager.md`. It adds Phase 3.1 (Test Specification) and Phase 4.1 (Test Execution) from `agent_qualitygate.md`.

**Use this file instead of** `@RUPStrikesBack/.claude/commands/rup-manager.md` during the experiment period. Once `agent_qualitygate.md` Part 2 is applied to the submodule, this wrapper is no longer needed.

## Instructions

1. **Read the standard rup-manager.md** at `RUPStrikesBack/.claude/commands/rup-manager.md` -- understand the full process, modes, error handling, and state management.
2. **Read `agent_qualitygate.md`** at the project root -- understand the test-first overrides.
3. **Execute all phases below in sequence**, following the standard rup-manager conventions (git commits after each phase, mode detection, etc.).

## Step 0: Detect Execution Mode and Test Parameters

Follow Step 0 from the standard rup-manager.md to detect `Mode:` (managed/YOLO).

**Additionally**, read the active sprint's `Test:` and `Regression:` fields from `PLAN.md`:
- `Test:` -- which new tests to create and gate (smoke, unit, integration, none; default: unit, integration)
- `Regression:` -- which existing tests to re-run (smoke, unit, integration, none; default: unit, integration)

If fields are absent, apply defaults.

Display after the mode banner:
```
Test Parameters:
  Test: [detected value or default]
  Regression: [detected value or default]
```

## YOLO Mode Speed Directive

Same as standard rup-manager.md. Time limit: 10 minutes for all phases.

---

## Phase 1: Execute Contracting

Same as standard rup-manager.md. Read `.claude/commands/agents/agent-contractor.md` and execute. Commit and push.

---

## Phase 2: Execute Inception

Same as standard rup-manager.md. Read `.claude/commands/agents/agent-analyst.md` and execute. Commit and push.

---

## Phase 3: Execute Elaboration

**Note**: Wait 60 seconds for design acceptance. After that assume approval.

Same as standard rup-manager.md. Read `.claude/commands/agents/agent-designer.md` and execute. Commit and push.

**Additionally**: The Designer MUST produce a Testing Strategy section in the design document (see `agent_qualitygate.md` Section 2.3 for the template). This feeds Phase 3.1.

---

## Phase 3.1: Execute Test Specification (NEW)

Execute the Test Architect instructions from `agent_qualitygate.md` Section 3.

**Summary of what this phase does:**
1. Read the approved design document and the sprint's `Test:` parameter
2. Create `progress/sprint_${no}/sprint_${no}_test_spec.md` with test specifications
3. Create/extend executable test skeletons in `tests/smoke/`, `tests/unit/`, `tests/integration/`
4. Write `progress/sprint_${no}/new_tests.manifest` listing all new test entries
5. Verify skeletons run (they should fail -- no implementation yet)
6. Update PROGRESS_BOARD.md with `test_specified` status
7. Commit and push

**Decision Point**: If test scope is unclear, stop and request clarification before proceeding to Phase 4.

---

## Phase 4: Execute Construction

Read `.claude/commands/agents/agent-constructor.md` and execute, **with these overrides from `agent_qualitygate.md` Section 4:**

- Do NOT create new tests (Phase 3.1 already did that)
- Implement code to satisfy the design
- Fill in any `# TODO: implement` stubs in test skeletons
- Commit and push

**Do NOT proceed to Phase 5 directly.** Proceed to Phase 4.1.

---

## Phase 4.1: Execute Test Execution (NEW)

Execute the Test Executor instructions from `agent_qualitygate.md` Section 4a.

**Summary of what this phase does:**

### Phase A: New-Code Gates (driven by `Test:` parameter)

Run only the tests listed in `progress/sprint_${no}/new_tests.manifest`:

1. **Gate A1 -- Smoke** (if `Test:` includes `smoke`): `tests/run.sh --smoke --new-only progress/sprint_${no}/new_tests.manifest`
2. **Gate A2 -- Unit** (if `Test:` includes `unit`): `tests/run.sh --unit --new-only progress/sprint_${no}/new_tests.manifest`
3. **Gate A3 -- Integration** (if `Test:` includes `integration`): `tests/run.sh --integration --new-only progress/sprint_${no}/new_tests.manifest`

### Phase B: Regression Gates (driven by `Regression:` parameter)

Run the full test suite at specified levels:

1. **Gate B1 -- Smoke** (if `Regression:` includes `smoke`): `tests/run.sh --smoke`
2. **Gate B2 -- Unit** (if `Regression:` includes `unit`): `tests/run.sh --unit`
3. **Gate B3 -- Integration** (if `Regression:` includes `integration`): `tests/run.sh --integration`

### Retry Policy

- **Managed mode**: Retries 1-4 automatic. Retry 5: human escalation (continue/stop/reclassify). Retries 6-10 if approved. After 10: sprint `failed`.
- **YOLO mode**: All 10 retries automatic. Integration gates accept >=80% pass rate per attempt.

On failure: hand failure report to Constructor (Phase 4), Constructor fixes, Test Executor re-runs.

### Gate Completion

After all gates pass (or meet YOLO threshold): update PROGRESS_BOARD.md with `tested` status. Commit and push.

If all retries exhausted: mark sprint `failed`. Commit and push. Report in Final Summary.

---

## Phase 5: Execute Documentation

Same as standard rup-manager.md. Read `.claude/commands/agents/agent-documentor.md` and execute. Commit and push.

**Only reached after ALL Phase 4.1 gates pass.**

---

## Step 6: Final Summary (MANDATORY)

Same as standard rup-manager.md. Provide the RUP Cycle Completion Report.

**Additionally include:**

```
**Test Parameters:**
- Test: [value]
- Regression: [value]

**Quality Gates:**
- Phase A (new-code): [gate results]
- Phase B (regression): [gate results]
- Retries used: [count per gate]
- Flaky tests deferred: [list or "None"]
```

---

## Execution Checklist

- [ ] **Step 0** - Detect Mode + Test + Regression parameters
- [ ] **Phase 1 - Contracting** - Execute agent-contractor.md, commit, push
- [ ] **Phase 2 - Inception** - Execute agent-analyst.md, commit, push
- [ ] **Phase 3 - Elaboration** - Execute agent-designer.md (with Testing Strategy), commit, push
- [ ] **Phase 3.1 - Test Specification** - Execute Test Architect (agent_qualitygate.md Section 3), commit, push
- [ ] **Phase 4 - Construction** - Execute agent-constructor.md (no test creation), commit, push
- [ ] **Phase 4.1 - Test Execution** - Execute Test Executor (agent_qualitygate.md Section 4a), commit, push
- [ ] **Phase 5 - Documentation** - Execute agent-documentor.md, commit, push
- [ ] **Step 6 - Final Summary** - RUP Cycle Completion Report with test gate results
