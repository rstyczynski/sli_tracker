# Patch: Sprint Definition

> **Integration instruction:** copy this file to `RUPStrikesBack/rules/generic/sprint_definition.md` in the RUP repo and add a reference to it from `GENERAL_RULES.md`.

## Rule

A sprint entry in `PLAN.md` describes a unit of work the team commits to delivering. It must state what will be tested and what must not regress — so the implementor knows the quality bar before writing a line of code.

## Format

```text
## Sprint <N> - <Title>

Status: Planned | Progress | Done
Mode: managed | YOLO
Test: <smoke | unit | integration | none  (comma-separated)>
Regression: <smoke | unit | integration | none  (comma-separated)>

<Optional: 1-2 sentences of context if the sprint is non-obvious.>

Backlog Items:

* <ID>. <Title>
```

## Fields

| Field | Description |
| --- | --- |
| `Status` | Current state of the sprint. |
| `Mode` | `managed` = full RUP gates; `YOLO` = autonomous, minimal ceremony. |
| `Test` | Which test levels the implementor must run before closing the sprint. |
| `Regression` | Which levels of the existing test suite the Test Executor re-runs after new-code gates pass. Same values as `Test:`. Default if omitted: `unit, integration`. Use `none` only for experimental or throwaway sprints. |

## Constraints

- `Test` and `Regression` are required for every sprint — they define the exit criteria.
- No design, no sub-tasks, no implementation notes — those belong in the sprint elaboration doc.
- One sprint = one coherent deliverable; bundle items only when they are tightly coupled.

## Example (good)

```text
## Sprint 8 - curl backend for emit.sh

Status: Planned
Mode: YOLO
Test: unit
Regression: unit

Backlog Items:

* SLI-11. Split emit.sh into emit_oci.sh and emit_curl.sh
```

## Example (bad — missing Test and Regression)

```text
## Sprint 8 - curl backend for emit.sh

Status: Planned
Mode: YOLO

Backlog Items:

* SLI-11. Split emit.sh into emit_oci.sh and emit_curl.sh
```
