# RUPStrikesBack v2.0 Upgrade Plan

This document captures the analysis and proposals for upgrading RUPStrikesBack to v2.0 with test-first quality gates and token-efficient architecture.

---

## 1. Patch Inventory

| # | Patch File | Purpose | Lines | Feasibility |
|---|------------|---------|-------|-------------|
| 1 | `backlog_item_patch.md` | Backlog item format definition | 54 | Easy |
| 2 | `sprint_patch.md` | Sprint format with Test/Regression fields | 68 | Easy |
| 3 | `rup_manager_patched.md` | Wrapper adding Phase 3.1 + 4.1 | 166 | Moderate |
| 4 | `rup_bug_policy.md` | Bug handling during sprints | 49 | Easy |
| 5 | `agent_qualitygate.md` | Test-first quality gates (comprehensive) | 697 | Moderate-High |
| 6 | `rup_manager_simplified.md` | Consolidated 5-phase with quality gates | 221 | Decision required |

---

## 2. File Dependency Graph

### Core Structure

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           ENTRY POINTS                                       │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   HUMANS.md ─────────────┬───────────────────► AGENTS.md                    │
│   (Product Owner)        │                     (AI Agents)                   │
│                          │                          │                        │
│                          ▼                          ▼                        │
│                    ┌──────────┐              ┌──────────────┐               │
│                    │ PLAN.md  │◄─────────────│rup-manager.md│               │
│                    │ (sprints)│              │(orchestrator)│               │
│                    └────┬─────┘              └──────┬───────┘               │
│                         │                           │                        │
│         ┌───────────────┼───────────────────────────┼───────────────┐       │
│         ▼               ▼                           ▼               ▼       │
│   ┌──────────┐   ┌─────────────┐            ┌─────────────────────────┐    │
│   │BACKLOG.md│   │PROGRESS_    │            │    rules/generic/       │    │
│   │ (items)  │   │BOARD.md     │            │  ┌─────────────────────┐│    │
│   └──────────┘   │ (status)    │            │  │GENERAL_RULES.md     ││    │
│                  └─────────────┘            │  │GIT_RULES.md         ││    │
│                                             │  │PRODUCT_OWNER_GUIDE  ││    │
│                                             │  └─────────────────────┘│    │
│                                             └─────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Phase Execution Flow (Current)

```
                         rup-manager.md
                              │
        ┌─────────┬──────────┼──────────┬─────────┐
        ▼         ▼          ▼          ▼         ▼
   ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐
   │Phase 1  │ │Phase 2  │ │Phase 3  │ │Phase 4  │ │Phase 5  │
   │Contractor│►│Analyst  │►│Designer │►│Construct│►│Document │
   └────┬────┘ └────┬────┘ └────┬────┘ └────┬────┘ └────┬────┘
        │           │           │           │           │
        ▼           ▼           ▼           ▼           ▼
   ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐
   │contract │ │analysis │ │design   │ │implement│ │document │
   │.md      │ │.md      │ │.md      │ │.md+tests│ │.md      │
   └─────────┘ └─────────┘ └─────────┘ └─────────┘ └─────────┘
```

### Patched Phase Flow (v2.0)

```
                    rup_manager_v2.md
                              │
                              ▼
                    ┌─────────────────┐
                    │ Step 0: Detect  │
                    │ Mode + Test +   │
                    │ Regression      │
                    └────────┬────────┘
                             │
   ┌─────────────────────────┼─────────────────────────┐
   ▼                         ▼                         ▼
┌──────────┐          ┌──────────────┐          ┌──────────────┐
│ Phase 1  │          │   Phase 2    │          │   Phase 3    │
│ Setup    │─────────►│ Design +     │─────────►│Construction  │
│(contract │          │ Test Spec    │          │(code only)   │
│+analysis)│          │ + Skeletons  │          │              │
└──────────┘          └──────┬───────┘          └──────┬───────┘
     │                       │                         │
     ▼                       ▼                         ▼
┌──────────┐          ┌──────────────┐          ┌──────────────┐
│setup.md  │          │design.md     │          │implement.md  │
│          │          │new_tests.    │          │              │
│          │          │manifest      │          │              │
└──────────┘          └──────────────┘          └──────────────┘
                                                       │
                                                       ▼
                                          ┌────────────────────┐
                                          │     Phase 4        │
                                          │   Quality Gates    │
                                          ├────────────────────┤
                                          │ Phase A (new-code) │
                                          │ A1 smoke→A2 unit→  │
                                          │ A3 integration     │
                                          │        │           │
                                          │        ▼           │
                                          │ Phase B (regress)  │
                                          │ B1 smoke→B2 unit→  │
                                          │ B3 integration     │
                                          └─────────┬──────────┘
                                                    │
                                                    ▼
                                          ┌─────────────────┐
                                          │    Phase 5      │
                                          │    Wrap-up      │
                                          └─────────────────┘
```

### Test Infrastructure

```
┌─────────────────────────────────────────────────────────────────┐
│                     tests/ DIRECTORY                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  tests/run.sh ◄──────── Quality Gates (Phase 4)                 │
│       │                                                          │
│       ├──► tests/smoke/test_*.sh                                │
│       ├──► tests/unit/test_*.sh                                 │
│       └──► tests/integration/test_*.sh                          │
│                                                                  │
│  tests/manifests/ ◄──── Regression Scope                        │
│       │                                                          │
│       ├──► component_<name>.manifest                            │
│       └──► ...                                                  │
│                                                                  │
│  progress/sprint_N/new_tests.manifest ◄── Phase A (--new-only) │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 3. Token Efficiency Analysis

### Current Approach (Granular Files)

| File | Lines |
|------|-------|
| rup-manager.md | 243 |
| GENERAL_RULES.md | 661 |
| agent-contractor.md | 152 |
| agent-analyst.md | 271 |
| agent-designer.md | 406 |
| agent-constructor.md | 539 |
| agent-documentor.md | 477 |
| **Subtotal (core)** | **~2,749** |
| + agent_qualitygate.md | 696 |
| **Total with patches** | **~3,445** |

### Token Cost

| Approach | Lines to Read | Est. Tokens |
|----------|---------------|-------------|
| Current granular | ~2,749 | ~15,000 |
| Current + patches | ~3,445 | ~19,000 |
| Proposed v2 (merged) | ~530 | ~3,000 |

**Potential savings: ~75% token reduction**

---

## 4. Proposed Architecture: Option A (Merged Phases)

### File Structure

```
.claude/commands/
├── rup_manager_v2.md        # Slim orchestrator (~150 lines)
└── agents/
    ├── agent-phase1.md      # Setup: contractor + analyst (~80 lines)
    ├── agent-phase2.md      # Design: designer + test-architect (~100 lines)
    ├── agent-phase3.md      # Build: constructor + test-executor (~120 lines)
    └── agent-phase4.md      # Wrap: documentor (~80 lines)

rules/
├── generic/
│   ├── QUICK_RULES.md       # Essential rules only (~50 lines)
│   ├── FULL_RULES.md        # Complete rules (for edge cases)
│   └── ...
└── detailed/                # Corner case docs (read on-demand)
    ├── DESIGN_ITERATION.md
    ├── TEST_MOCKING.md
    └── ...
```

### Phase Mapping

| v1 Phases | v2 Phase | Agent File |
|-----------|----------|------------|
| 1 Contracting + 2 Inception | Phase 1 Setup | agent-phase1.md |
| 3 Elaboration + 3.1 Test Spec | Phase 2 Design | agent-phase2.md |
| 4 Construction + 4.1 Test Exec | Phase 3 Build | agent-phase3.md |
| 5 Documentation | Phase 4 Wrap | agent-phase4.md |

### Corner Case Triggers

Each slim agent file contains a trigger table:

```markdown
## Corner Case Triggers

| If you encounter... | Read this file |
|---------------------|----------------|
| API feasibility unclear | `rules/detailed/API_VERIFICATION.md` |
| Test isolation needs mocks | `rules/detailed/TEST_MOCKING.md` |
| Design rejected by PO | `rules/detailed/DESIGN_ITERATION.md` |
| Multi-sprint backlog item | `rules/detailed/CROSS_SPRINT.md` |
| YOLO mode edge cases | `rules/detailed/YOLO_DECISIONS.md` |
```

Agent only reads detailed files when it hits a trigger condition.

---

## 5. Skills Discovery Layer (Generic Solution)

### Problem

RUP is a generic methodology, but corner cases (mocking, deployment, etc.) are project-specific.

### Solution: Project Skills Index

#### Generic RUP Structure

```
RUPStrikesBack/                    # GENERIC (reusable)
├── .claude/commands/
│   └── rup_manager_v2.md
├── rules/
│   └── generic/
└── skills/
    └── SKILLS_TEMPLATE.md         # Template for projects to copy
```

#### Project-Specific Structure

```
<your-project>/
├── RUPStrikesBack/                # (submodule - generic)
├── skills/                        # Project-specific skills
│   ├── SKILLS_INDEX.md            # Discovery file (required)
│   ├── mocking_oci.md
│   ├── mocking_github.md
│   └── testing_integration.md
└── ...
```

### Generic Trigger in RUP Manager

```markdown
## Corner Case Handling

When you encounter a situation not covered by quick rules:

1. Check if `skills/SKILLS_INDEX.md` exists in project root
2. If yes, read it to find relevant skill
3. If no skill matches, use defaults or ask Product Owner

**Do NOT hardcode project-specific knowledge in RUP files.**
```

### Project Skills Index Template

```markdown
# Project Skills Index

This file maps corner cases to project-specific guidance.

## Test & Mocking
| Trigger | Skill File |
|---------|------------|
| Need to mock external service X | `skills/mocking_x.md` |
| Integration test setup | `skills/testing_integration.md` |

## Infrastructure
| Trigger | Skill File |
|---------|------------|
| Deploy artifacts | `skills/deploy.md` |
| Configure secrets | `skills/secrets_management.md` |

## Project Conventions
| Trigger | Skill File |
|---------|------------|
| Naming conventions | `skills/naming.md` |
| Error handling patterns | `skills/error_handling.md` |
```

### Flow Diagram

```
┌──────────────────────────────────────────────────────────┐
│                  RUP GENERIC LAYER                       │
│                                                          │
│  rup_manager_v2.md                                       │
│       │                                                  │
│       ▼                                                  │
│  ┌────────────────────┐                                  │
│  │ Corner case hit?   │                                  │
│  └─────────┬──────────┘                                  │
│            │ YES                                         │
│            ▼                                             │
│  ┌────────────────────────────┐                          │
│  │ Read skills/SKILLS_INDEX.md│ ◄── Discovery point      │
│  └─────────┬──────────────────┘                          │
│            │                                             │
└────────────┼─────────────────────────────────────────────┘
             │
             ▼
┌────────────────────────────────────────────────────────┐
│               PROJECT-SPECIFIC LAYER                    │
│                                                         │
│  skills/SKILLS_INDEX.md                                 │
│       │                                                 │
│       ├──► skills/mocking_x.md                          │
│       ├──► skills/testing_integration.md                │
│       └──► skills/deploy.md                             │
│                                                         │
└────────────────────────────────────────────────────────┘
```

### Benefits

| Aspect | Generic RUP | Project Skills |
|--------|-------------|----------------|
| Ownership | RUPStrikesBack repo | Each project repo |
| Updates | Affects all projects | Isolated to project |
| Content | Process, phases, rules | Mocking, deploy, conventions |
| Reuse | 100% | 0% (project-specific) |

---

## 6. Patch Integration Order

### P1 — Standalone Rules (Easy)

1. `backlog_item_patch.md` → copy to `rules/generic/backlog_item_definition.md`
2. `sprint_patch.md` → copy to `rules/generic/sprint_definition.md`
3. `rup_bug_policy.md` → copy to `rules/generic/bug_policy.md`
4. Add references in `GENERAL_RULES.md`

### P2 — Architecture Decision

**Option A (Recommended):** Merge phases + skills layer
- Create `rup_manager_v2.md` (slim orchestrator)
- Create 4 merged agent files
- Create `rules/generic/QUICK_RULES.md`
- Create `skills/SKILLS_TEMPLATE.md`
- Extract test gates from `agent_qualitygate.md`

**Option B:** Apply granular patches
- Apply `agent_qualitygate.md` Part 2 instructions to 7 files
- Create `agent-test-architect.md` and `agent-test-executor.md`
- More files, higher token cost

### P3 — Update Entry Points

- Update `AGENTS.md` with new phase structure
- Update `HUMANS.md` if needed

---

## 7. Summary

| Decision | Recommendation |
|----------|----------------|
| Phase structure | Merge into 4 phases (Option A) |
| Token efficiency | ~75% reduction with merged approach |
| Project-specific knowledge | Skills discovery layer |
| Patch integration | P1 first (rules), then P2 (architecture) |

---

## 8. Next Steps

1. Review this plan in RUPStrikesBack project
2. Decide on Option A vs Option B
3. Create v2.0 branch
4. Implement changes
5. Test with SLI_tracker as first adopter
