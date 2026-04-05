# Sprint 7 - Contracting Summary

## Project Overview

SLI Tracker is a set of GitHub Actions and shell scripts that track and emit Service Level Indicators (SLI) to OCI Logging from CI/CD pipelines. Sprint 7 bootstraps the test-first quality gates system defined in `agent_qualitygate.md`.

## Current Sprint

- Sprint Number: 7
- Status: Progress
- Mode: managed
- Test: smoke, unit, integration
- Regression: none
- Backlog Items: SLI-10 (Implement test-first quality gates)

## Key Requirements (SLI-10)

1. Create centralized `tests/run.sh` runner with `--smoke`, `--unit`, `--integration`, `--all`, `--new-only <manifest>` flags
2. Migrate existing tests to `tests/` tree (unit and integration)
3. Create initial smoke tests in `tests/smoke/`
4. Replace old test locations with one-line wrapper scripts
5. Validate all migrated tests pass from new locations

## Rule Compliance

- **GENERAL_RULES.md**: Understood. Follow RUP 5-phase process (extended to 7 via `agent_qualitygate.md` patch). Managed mode: interactive, ask for clarification.
- **GIT_RULES.md**: Understood. Semantic commits, no scope in parentheses before colon, push after commit.
- **agent_qualitygate.md**: Understood. Adds Phase 3.1 (Test Specification) and Phase 4.1 (Test Execution). Test/Regression parameters detected from PLAN.md.

## Responsibilities

- **Allowed edits**: Sprint 7 documents in `progress/sprint_7/`, source code in `tests/`, wrapper scripts at old test locations, `PROGRESS_BOARD.md`, `README.md`
- **Prohibited**: Modifying `PLAN.md` (except status), modifying `BACKLOG.md`, modifying status tokens owned by Product Owner
- **Communication**: Proposed changes via `sprint_7_proposedchanges.md`, questions via `sprint_7_openquestions.md`

## Constraints

- Do not modify other sprint directories
- All test scripts must be copy-paste-able, no `exit` in examples
- Follow existing code conventions
- Wrapper scripts at old locations must preserve backward compatibility

## Open Questions

None. SLI-10 deliverables are clearly specified in BACKLOG.md.

## Status

Contracting Complete - Ready for Inception
