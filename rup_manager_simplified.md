# RUP Simplified Manager — Test-First Quality Gates

Execute the complete RUP cycle in **5 phases** with test-first quality gates.

Simplification over `rup_manager_patched.md`: phases merged, boilerplate artifacts eliminated,
mode detected once. Quality rules (test skeletons, mandatory logs, regression gates, PROGRESS_BOARD)
are fully preserved.

---

## Step 0: Detect Mode and Test Parameters (ONCE)

1. Read `PLAN.md` — find the Sprint with `Status: Progress`
2. Extract `Mode:`, `Test:`, `Regression:` fields. Defaults: `Test: unit, integration`, `Regression: unit, integration`
3. Display the combined banner — this is the contract for all phases:

```text
═══════════════════════════════════════════════════════════
SPRINT [N] | MODE: [YOLO|managed] | Test: [values] | Regression: [values]
═══════════════════════════════════════════════════════════
YOLO: all outputs self-approved immediately, no waits, 10-min limit.
```

**All subsequent phases use this banner. Do NOT re-read PLAN.md for mode or sprint number.**

---

## Phase 1: Setup (Contracting + Inception)

Read `RUPStrikesBack/.claude/commands/agents/agent-contractor.md` and
`RUPStrikesBack/.claude/commands/agents/agent-analyst.md` — skip Step 0 (mode detection)
in both; mode is already set in the Phase 0 banner.

Produce a **single file** `progress/sprint_${no}/sprint_${no}_setup.md` with two sections:

```markdown
## Contract
[contractor output: rules understood, responsibilities, constraints, open questions]

## Analysis
[analyst output: backlog items analyzed, feasibility, compatibility, open questions]
```

Update `PROGRESS_BOARD.md`: Sprint → `under_analysis`; Backlog Items → `analysed`

**Decision point:** If any critical ambiguity exists in either section, stop and request clarification.

Commit: `docs: (sprint-${no}) setup phase — contract and analysis` · Push.

---

## Phase 2: Design + Test Specification

Read `RUPStrikesBack/.claude/commands/agents/agent-designer.md` — skip Step 0 and Step 8
("Await Approval"). **YOLO mode: self-approve immediately after writing; no 60-second wait.**
**Managed mode: wait for explicit Product Owner approval before continuing.**

The design document `progress/sprint_${no}/sprint_${no}_design.md` **must** include a
`### Testing Strategy` section (per `agent_qualitygate.md` §2.3 template).

**Immediately after writing the design** (no separate commit), execute the Test Architect
instructions from `agent_qualitygate.md` §3:

1. Read the `### Testing Strategy` section and the `Test:` param from the Phase 0 banner
2. Append a `## Test Specification` section to `sprint_${no}_design.md` (SM-N / UT-N / IT-N + traceability table) — **no separate test_spec.md file**
3. Append test skeletons to existing files in `tests/smoke/`, `tests/unit/`, `tests/integration/` (one file per component/domain, not per sprint)
4. Write `progress/sprint_${no}/new_tests.manifest` (format: `suite:script[:function]`)
5. Verify skeletons run and produce expected failures: `tests/run.sh --unit` (and `--smoke` if applicable)

Update `PROGRESS_BOARD.md`: Backlog Items → `designed` → `test_specified`

**Decision point:** If test scope is unclear after reading the Testing Strategy, stop and request clarification before writing skeletons.

Commit: `docs: (sprint-${no}) design, test spec, and test skeletons` · Push.

---

## Phase 3: Construction

Read `RUPStrikesBack/.claude/commands/agents/agent-constructor.md` — skip Step 0.

**Override (`agent_qualitygate.md` §4):** Do NOT create new test cases. Implement code to satisfy
the design; fill `# TODO: implement` stubs in existing skeletons only.

Produce `progress/sprint_${no}/sprint_${no}_implementation.md`.

Update `PROGRESS_BOARD.md`: Sprint → `under_construction`; Backlog Items → `under_construction`

Commit: `feat: (sprint-${no}) implement [brief description]` · Push.

**Do NOT proceed to Phase 5. Proceed to Phase 4.**

---

## Phase 4: Quality Gates

Execute `agent_qualitygate.md` §4a (Test Executor) exactly. Use `Test:` and `Regression:` from
the Phase 0 banner.

Every gate **must** tee output to a timestamped log (mandatory — gate not counted without log):
```bash
TS="$(date -u '+%Y%m%d_%H%M%S')"
LOG="progress/sprint_${no}/test_run_<gate>_${TS}.log"   # gate: A1_smoke A2_unit A3_integration B1_smoke B2_unit B3_integration
tests/run.sh --<level> [--new-only progress/sprint_${no}/new_tests.manifest] 2>&1 | tee "$LOG"
```

**Phase A — New-Code Gates** (per `Test:` param): A1 smoke → A2 unit → A3 integration.
Each must pass before the next. A1 fail = skip A2/A3. `--new-only …manifest` for all A gates.

**Phase B — Regression Gates** (per `Regression:` param, only after Phase A passes):
B1 smoke, B2 unit, B3 integration. Full suite (no `--new-only`).

**Retry policy:** Managed: retries 1–4 auto, retry 5 human escalation, 6–10 if approved, after 10 → `failed`.
YOLO: all 10 auto; integration gates accept ≥80% pass rate with failures documented.
On failure: hand report to Constructor → fix → re-run gate.

Produce `progress/sprint_${no}/sprint_${no}_tests.md` with `## Artifacts` listing all log paths.

Update `PROGRESS_BOARD.md`: Items → `smoke_passed` / `unit_tested` / `integration_tested` / `tested` (or `failed`);
Sprint → `implemented` / `implemented_partially` / `failed`.

Commit: `test: (sprint-${no}) quality gates — [pass/fail summary]` · Push.

**Phase 5 only after all gates pass (or YOLO threshold met). Retries exhausted → mark `failed`, still run Phase 5.**

---

## Phase 5: Wrap-up

1. **Update `README.md`** — add `### Sprint N — [title]` to the Recent Updates section
   (follow template in `RUPStrikesBack/.claude/commands/agents/agent-documentor.md` §6)
2. **Create backlog traceability symlinks** in `progress/backlog/[ITEM-ID]/` pointing to all
   sprint_${no} documents (follow `agent-documentor.md` §4 procedure)
3. **Inline compliance check** (no document produced — just verify before committing):
   - All sprint artifacts exist: `setup.md`, `design.md`, `implementation.md`, `tests.md`, log files
   - No `exit` commands in copy-paste blocks in `implementation.md`
   - All log file paths listed in `tests.md ## Artifacts`
4. Verify `PROGRESS_BOARD.md` final state is correct

Commit: `docs: (sprint-${no}) update README and backlog traceability` · Push.

---

## Step 6: Final Summary ⚠️ MANDATORY

```
# RUP Simplified Cycle — Sprint [N] Completion Report

Sprint: N | Mode: [YOLO|managed] | Status: [implemented|implemented_partially|failed]

## Phases Executed
- Phase 1 Setup:          [done] → sprint_N_setup.md
- Phase 2 Design:         [done] → sprint_N_design.md (includes test spec + skeletons)
- Phase 3 Construction:   [done] → sprint_N_implementation.md
- Phase 4 Quality Gates:  [pass|fail] → [N] log files + sprint_N_tests.md
- Phase 5 Wrap-up:        [done] → README + backlog traceability

## Backlog Items
| Item | Status | Tests |
|------|--------|-------|
| SLI-N | tested/failed | N pass / N fail |

## Quality Gates
| Gate | Result | Retries |
|------|--------|---------|
| A2 Unit        | pass | 0 |
| A3 Integration | pass | 0 |
| B2 Unit        | pass | 0 |
| B3 Integration | pass | 0 |

## Commits
- [hash] docs: (sprint-N) setup phase — contract and analysis
- [hash] docs: (sprint-N) design, test spec, and test skeletons
- [hash] feat: (sprint-N) implement [description]
- [hash] test: (sprint-N) quality gates — [summary]
- [hash] docs: (sprint-N) update README and backlog traceability

## Files Modified
[list all modified/created files]

## Deferred Items
[list or "None"]

## Test Parameters
- Test: [value]  |  Regression: [value]
- Flaky tests deferred: [list or "None"]
```

---

## Execution Checklist

- [ ] **Step 0** — Mode + test params detected; banner displayed
- [ ] **Phase 1** — Setup (contract + analysis) → `sprint_N_setup.md` → commit, push
- [ ] **Phase 2** — Design + test spec + skeletons → `sprint_N_design.md` + `new_tests.manifest` → commit, push
- [ ] **Phase 3** — Construction (no new tests) → `sprint_N_implementation.md` → commit, push
- [ ] **Phase 4** — Quality gates (Phase A + Phase B) → log files + `sprint_N_tests.md` → commit, push
- [ ] **Phase 5** — Wrap-up (README + backlog traceability) → commit, push
- [ ] **Step 6** — Final Summary (MANDATORY — never skip)
