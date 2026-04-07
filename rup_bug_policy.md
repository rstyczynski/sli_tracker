# RUP Bug Handling (Lightweight) — Sprint-Scoped Policy

## Default rule
Bugs discovered during a sprint are handled as part of the **current backlog item** (fold-in fix),
unless they expand scope (see “Promotion criteria” below).

## Where to register a bug
Primary location: register bugs under the affected backlog item (e.g., `## SLI-17`) in:

1. `progress/sprint_<N>/sprint_<N>_bugs.md`

Secondary locations (only when needed):

- `progress/sprint_<N>/sprint_<N>_setup.md` (`## Analysis`) **only if** the bug changes feasibility/compatibility assumptions or introduces new constraints.
- `progress/sprint_<N>/sprint_<N>_implementation.md` may include a short pointer to `sprint_<N>_bugs.md` (avoid duplicating the full write-up).

(Optional) If the fix materially changes the design/architecture, add a brief amendment to
`progress/sprint_<N>/sprint_<N>_design.md`.

## Bug entry template (use consistently)
Under the backlog item section, write:

- **Symptom**: exact error + where observed (command/gate/log path)
- **Root cause**: minimal causal explanation
- **Fix**: what changed (file/function-level)
- **Verification**: which Quality Gate/log proves resolution (re-run info)

## Bugs found during Quality Gates (Phase 4) — expected loop
If a Quality Gate fails due to a bug:

- Record the bug under the backlog item in `progress/sprint_<N>/sprint_<N>_bugs.md` (using the template above).
- Fix the code (Construction loop).
- Re-run the **failing gate** (and downstream gates if the process requires).
- Ensure the new gate run is tee’d to a timestamped log and listed in `progress/sprint_<N>/sprint_<N>_tests.md` under `## Artifacts`.

## Promotion criteria (when a bug becomes a new backlog item)
Create a new backlog item in `BACKLOG.md` (and track it in `PROGRESS_BOARD.md`) when any is true:

- **Scope expansion**: fix requires work beyond the current item’s requirement summary.
- **Cross-cutting impact**: fix touches multiple backlog items/areas and needs dedicated design/test spec updates.
- **Defer decision**: bug cannot be resolved in-sprint and needs explicit follow-up ownership.

## Minimal documentation updates at wrap-up
In Phase 5 (Wrap-up):

- Mention the bug + fix briefly in the sprint’s `README.md` “Recent updates” section.
- Keep the detailed narrative in sprint artifacts, not in the README.

