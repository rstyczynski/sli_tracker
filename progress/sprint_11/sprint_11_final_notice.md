# Sprint 11 — Final notice (post-implementation conclusions)

**Sprint:** 11 (SLI-16) · **Topic:** JavaScript `sli-event-js` vs explicit workflow steps

These points were clarified after delivery; they refine the original “pre/main/post in one action” story.

## 1. Local actions and `pre` hooks

GitHub does **not** run **`pre`** for actions referenced with `./` (repository-local actions). Optional OCI restore cannot live in `pre` for that model. The shipped approach is an explicit **`oci-profile-setup`** step at the beginning of workflows that need credentials.

## 2. `outcome` and `${{ job.status }}`

`${{ job.status }}` is **not** “frozen at workflow parse time”; it is evaluated when the runner processes the step. It is bound **once per step** (into `INPUT_*`), including for the **post** hook — it does **not** re-evaluate inside `post.js`. For a step that runs **after** the main work step, passing `outcome: ${{ job.status }}` is usually correct.

Reading the **current run** via the GitHub API is possible (`GITHUB_RUN_ID`, `GITHUB_TOKEN`), but while the job is still running the workflow run **`conclusion`** may be unset; expressions like **`steps.<id>.conclusion`** are often simpler than an API round-trip.

## 3. Is the `post.js` pattern still justified?

**Not meaningless**, but **much of the original value is gone** once `pre` is removed and the workflow must still list:

- setup (e.g. `oci-profile-setup`), and  
- a **final** reporting step.

**What `post` still offers:**

- Post hooks run in the job **post phase** (after normal steps), which matters if this action is **not** the last step or multiple actions define `post` (ordering is LIFO).
- `post-if: always()` can emit even when the **main** half of **that** action fails — but if an **earlier** step failed, the reporting step is still **skipped** unless the workflow uses e.g. **`if: always()`** (not only `!cancelled()`).

**For a last step only** (as in `model-emit-js.yml`), a **composite `sli-event`** step or a **`run:`** invoking `emit.sh` with `if: always()` is **simpler and clearer** than a JavaScript action whose `main` is empty and whose behavior is entirely in `post`.

The JS wrapper aligned with a story of **one `uses:`** doing **pre (OCI) + post (emit)**. With **pre unsupported locally**, half of that story is gone; keeping **`sli-event-js`** is a **design choice** (familiar `uses:` surface, possible future publish), not a platform requirement.

## 4. Takeaway for future sprints

Prefer **composite + `emit.sh`** (or an explicit shell step) for repo-local “model” workflows unless there is a concrete need for JS-only behavior or marketplace packaging. Revisit **`if:`** on the reporting step so SLI runs on failure when that is required (**`always()`** vs **`!cancelled()`**).
