# Agent Starting Point

Welcome! This document is your starting point when using RUPStrikesBack as a submodule.

## Quick Start

To execute a complete development cycle automatically:

```
@RUPStrikesBack/.claude/commands/rup-manager.md
```

## Management Commands (Version 2.0)

```
@RUPStrikesBack/.claude/commands/backlog.md add <title>
@RUPStrikesBack/.claude/commands/backlog.md list [--status <status>]
@RUPStrikesBack/.claude/commands/backlog.md prioritize

@RUPStrikesBack/.claude/commands/sprint.md create [<N>]
@RUPStrikesBack/.claude/commands/sprint.md start [<N>]
@RUPStrikesBack/.claude/commands/sprint.md status [<N>]
@RUPStrikesBack/.claude/commands/sprint.md close [<N>]

@RUPStrikesBack/.claude/commands/bug.md report <title>
@RUPStrikesBack/.claude/commands/bug.md triage [<BUG-ID>]
@RUPStrikesBack/.claude/commands/bug.md list [--sprint <N>]

@RUPStrikesBack/.claude/commands/archive-sprint.md <N>
```

## Phase Agents

To execute individual phases:

```
@RUPStrikesBack/.claude/commands/agents/agent-contractor.md   # Phase 1: Setup (Contracting)
@RUPStrikesBack/.claude/commands/agents/agent-analyst.md      # Phase 1: Setup (Inception)
@RUPStrikesBack/.claude/commands/agents/agent-designer.md     # Phase 2: Design + Test Specification
@RUPStrikesBack/.claude/commands/agents/agent-constructor.md  # Phase 3: Construction
                                                              # Phase 4: Quality Gates (via rup-manager)
@RUPStrikesBack/.claude/commands/agents/agent-documentor.md   # Phase 5: Wrap-up
```

**Note:** Phase 4 (Quality Gates) is orchestrated by `rup-manager.md` using procedures from `RUPStrikesBack/rules/generic/test_procedures.md`. It runs quality gates (A1-A3 new-code, B1-B3 regression) and handles the fix-and-retry loop with the Constructor.

## Execution Modes

The RUP process supports two execution modes configured in `PLAN.md`:

### Mode: managed (Default - Interactive)

**Characteristics:**
- Human-supervised execution
- Agents ask for clarification on ambiguities
- Interactive decision-making at each phase
- Recommended for complex or high-risk sprints

**Behavior:**
- Wait for design approval
- Stop for unclear requirements
- Ask about significant implementation choices
- Confirm before making major decisions

### Mode: YOLO (Autonomous - "You Only Live Once")

**Characteristics:**
- Fully autonomous execution
- Agents make reasonable assumptions for weak problems
- No human interaction required
- All decisions logged in implementation docs
- Recommended for well-understood, low-risk sprints

**Behavior:**
- Auto-approve designs
- Make reasonable assumptions (documented)
- Proceed with partial test success
- Auto-fix simple issues
- Only stop for critical failures

**Decision Logging:**
All YOLO mode decisions are logged in phase documents with:
- What was ambiguous
- What assumption was made
- Rationale for the decision
- Risk assessment

**Audit Trail:**
The Mode field in PLAN.md creates a permanent git record showing which sprints were autonomous vs supervised.

**How to Detect Mode and Test Parameters:**
Read the active Sprint section in PLAN.md:
```markdown
## Sprint 20

Status: Progress
Mode: YOLO
Test: unit, integration
Regression: unit

Backlog Items:
* GH-27. Feature implementation
```

**Required fields:**
- `Mode:` — `YOLO` or `managed` (default: managed)
- `Test:` — `smoke`, `unit`, `integration`, `none` (default: unit, integration)
- `Regression:` — `smoke`, `unit`, `integration`, `none` (default: unit, integration)

See `RUPStrikesBack/rules/generic/sprint_definition.md` for full specification.

## Rules (MUST READ)

Before starting any work, you MUST read and understand all rules in `RUPStrikesBack/rules/generic` directory.

**IMPORTANT**: You MUST comply with all rules without exceptions. If anything is unclear or conflicts, ask immediately.

## Summary

As an agent:

1. ✅ Read all rules in `RUPStrikesBack/rules/generic` directory
2. ✅ Invoke `@RUPStrikesBack/.claude/commands/rup-manager.md` for full cycle
3. ✅ Follow agent instructions from `RUPStrikesBack/.claude/commands/agents/`
4. ✅ Ask questions when unclear - NEVER assume

**Ready to start?** Invoke `@RUPStrikesBack/.claude/commands/rup-manager.md` to begin.
