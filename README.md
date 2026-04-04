# SLI tracking model

GitHub pipeline execution emits events used to compute Service Level Indicators (SLI). In case of pipeline success event is emitted, and in face of a problem - failure one. Failure message conveys reason to understand if a failure run was because of external or internal service.

Model works on a GitHub repository interacting with OCI tenancy where events are stored.

## Process

This repository is developed using the **RUP Strikes Back** AI-driven development process. The process is managed by the `RUPStrikesBack` git submodule located at `./RUPStrikesBack/`.

Key documents:

- `BACKLOG.md` — full list of backlog items (SLI-1, SLI-2, ...)
- `PLAN.md` — sprint plan; active sprint has `Status: Progress`
- `PROGRESS_BOARD.md` — real-time sprint and item status

To start or continue a development cycle, invoke the RUP Manager:

```text
@RUPStrikesBack/.claude/commands/rup-manager.md
```

All rules, templates, and procedures come from `RUPStrikesBack/`. Sprint artifacts are stored under `progress/sprint_<N>/`.

## Recent updates

### Sprint 3 — Workflow and emit review (YOLO)

**Status:** implemented (review-only; no workflow code changes)

**Backlog**

- **SLI-3:** Reviewed `model-*.yml` — call graph, `MODEL —` naming, `sli-event` / `sli-failure-reason` usage; see `progress/sprint_3/sprint_3_implementation.md`.
- **SLI-4:** Reviewed `sli-event` (`action.yml`, `emit.sh`); unit tests: `bash .github/actions/sli-event/tests/test_emit.sh`.

**Artifacts:** `progress/sprint_3/` (analysis, design, implementation, tests, documentation). Traceability: `progress/backlog/SLI-3/`, `progress/backlog/SLI-4/`.

---

## Goals

1. track SLI for a GitHub pipeline
2. track SLI for a GitHub pipeline steps

## Environment

GitHub workflow lives in GitHub repository holding this code. Interaction with OCI requires OCI CLI (with prerequisite i.e. python) and OCI access profile to be available. Moreover destination OCI log should be specified. Workflow configuration arguments are specified in repository secrets and variables.

```text
GitHub
  \- Workflow
        |- GitHub Secrets
        |       |- OCI Config file
        |       \- Private key
        \- GitHub Variables
                |- OCI config profile name
                \- OCI Logging
```
