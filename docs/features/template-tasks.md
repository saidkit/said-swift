# <FEAT> Task Log: [Feature Name]

<!-- Legend for the heading above and the stencils below:
       <FEAT>  — feature-id: project prefix + 2-digit feature counter (e.g. INIT-01)
       <NN>    — 2-digit zero-padded task counter within the feature
     Task IDs default to SINGLE-APP: <FEAT>-<NN> (e.g. INIT-01-03) — the clean default for a
     single-app project (avoids a doubled prefix/app token). For a genuinely multi-target
     project — app / CLI helper / login item — reintroduce an <APP> segment: <FEAT>-<APP>-<NN>.
     Skills read these stencils to learn the vocab. -->

**CRITICAL: This file is an append-only historical record.**

- Never overwrite or strip detail from existing task entries
- When updating task status: change only the `Status:` line; add/update `### Fix`, optionally `### Deviations` and `### Gotchas`
- **Pre-commit amendment carve-out**: task entries not yet referenced in any commit (`git log --all --grep <task-id>` empty) MAY be amended in place — extend Approach, Acceptance, add a `### Deviations` note documenting the late fold-in. Never delete prior detail. Once a commit references the task-id, append-only is strict.
- Keep all detail: decisions, trade-offs, lessons learned

## Authoring discipline (read before writing or closing tasks)

**Working folder vs task body.** `docs/working/<feature-id>/` is operator workspace — handoff drafts, scope refinements, research notes, transient authoring. Skills may read/write there as input/output across phases; the task body MUST NOT cite working-folder paths in `Refs:` / `Reading list` / `### Fix`. The task body cites only durable artifacts: ADR / UX-spec / feature-spec / committed code.

**What goes here:** episodes — Problem / Approach / Reading list / Acceptance, then Fix / Deviations? / Gotchas? at close. Section order is canonical — don't reorder.

**What does NOT go here:**
- Forward-looking rules (`must`, `always`, `never`, `frozen`, `convention`, `spec change`). → ADR or `ux/*.md`. Leave only a `Refs:` pointer in the task.
- References to `docs/working/<feature-id>/` paths in `Refs:` / `Reading list` / `### Fix`. → See "Working folder vs task body" above.
- `**Files added:**` / `**Files modified:**` blocks in `### Fix`. Files are derivable from `git log --name-only`.
- TDD red-green narratives. → tests are the source of truth.
- Mid-task amendments (`Follow-up`, `Fix (post-review #2)`, `Re-attempt plan`). → new task IDs, appended at the end of the file.
- Sentences that repeat content from a referenced ADR / UX-spec instead of pointing at it. → `Refs:` and a one-line cite, not a paraphrase.
- "Alternatives considered" entries for options no reasonable reader would have picked. → keep alternatives only when the rejected option is plausible to a reader who doesn't know the codebase.
- Historical narration of how the task evolved (`first I tried X, then user changed mind, then…`). → git log + commit messages are canonical for sequencing.
- Cosmetic Deviations (sub-30-min friction, no downstream impact, plan-vs-actual on positions / sizes / order). → drop entirely; they're noise.
- Gotchas visible from the diff, test names, or commit message alone. → keep Gotchas only when non-obvious from the artifact-under-review.

**Operator questions (holds).** A task that depends on a question only the operator can answer carries the field `**Blocked-on question:** <id>` (a peer of Status / Priority / Refs, never a `###` section). It is not built until a line in this file's `## Lifted holds` section lifts it: `- <id> lifted-by: user@WR-<seconds> -- "<verbatim quote>" -- <date>`, citing the operator's answer as a ruling recorded with `ruled` in `docs/working/<feature-id>/rulings.md`. A task with no such dependency carries no field.

**Close-of-task review** (run before changing Status to Done):

1. **Leak scan.** Read the entry. Any sentence reading as a forward-looking rule (words: `must`, `always`, `never`, `frozen`, `convention`, `spec change`)? Move that content to the relevant ADR or `docs/ux/*.md`. Leave only a `Refs:` pointer in the task.
2. **Gotcha harvest.** List anything non-obvious learned during implementation that wasn't in Approach — failed first attempts, surprising constraints, framework or toolchain quirks. Add as bullets under `### Gotchas`. Then drop any bullet visible from the diff / test names / commit message alone.
3. **Deviation check.** Did the implementation depart from Approach? If yes, write `### Deviations` as `Plan: X / Actual: Y / Reason: Z`. Drop cosmetic deviations — they're noise.
4. **Fill `### Fix`** as a single verification line (`Tests N → M; build + lint + format clean.`) plus optional one-line pointers to spec edits. Drop file enumeration — git is canonical. If a gate could not run (no build tree yet, no test target), say which and why — never claim a pass that didn't happen.
5. **Bloat scan.** Re-read the entry as someone who didn't write it and only has the linked ADR/UX-spec + the diff + git log. Cut every sentence that doesn't add information beyond those sources. Specifically:
   - Sentences that repeat content from a referenced ADR/spec instead of pointing at it
   - "Alternatives considered" entries for options no reasonable reader would have picked
   - File-path enumerations (`git log --name-only` is canonical)
   - Historical narration of how the task evolved
   - Repetition between Approach / Reading list / Acceptance — each section serves a different question; if two say the same thing, one of them is wrong
   - Target the verbosity of the lightest entries in this file's recent history. If a section is twice as long as the equivalent in adjacent tasks, justify or cut.

Report what moved, was added, or was cut before saving.

**Depth varies by task type:**

- **Planned tasks** (from feature pass-2 grilling): fill all five mandatory sections (Problem / Approach / Reading list / Acceptance / Fix). Deviations and Gotchas as needed at close.
- **Ad-hoc tasks** (bug fixes, small follow-ups discovered mid-feature): may carry only Problem + Fix + Gotchas. The template tolerates both shapes — don't pad to fit ceremony.

**`Refs:` discipline.** Mandatory when the task creates or edits an ADR / UX-spec / feature-spec — list all touched paths there. Empty otherwise.

**Platform-specific close notes.** Any task touching signing identity, entitlements, `Info.plist`, the bundle identifier, or the release chain also runs `R-GATE-SIGN` and says so in `### Fix`. Any task adding a dependency, framework, or entitlement runs `R-GATE-DEPS` and names the justification.

---

## Summary Table

| Task | Title | Status |
|---|---|---|
| <FEAT>-01 | [Short title] | Todo / Done / Backlog / Canceled |

---

## <FEAT>-01: [Task Title]

**Status:** (Todo | Done | Canceled | Backlog) (YYYY-MM-DD)
**Priority:** (High | Medium | Low)
**Refs:** (ADR / UX-spec / feature-spec paths the task created or edited; mandatory when the task touches any, otherwise empty)

### Problem
[What needs to be solved? Include context — why is this an issue? For bugs, add a `### Root cause` subsection.]

### Approach
[What to build, not how. Include alternatives considered and why this was chosen. Frozen at pass-2 close — if implementation departs from this, log under Deviations.]

### Reading list
[Files / ADRs / UX specs an implementer must load before starting. Often short — the feature spec's `## Context to load` already covers most.]

### Acceptance
[How "done" is judged — observable outcomes, not implementation steps.]

### Fix
<!-- Filled at close. Single verification line. Example:
  Tests 12 → 15 (3 cases — X / Y / Z); build + lint + format clean.
Plus optional one-liners for spec edits. Name any gate that could not run and why.
No file enumeration (git is canonical). No build-output dumps. -->

### Deviations
<!-- Optional. Only if implementation departed from Approach. Plan / Actual / Reason. -->

### Gotchas
<!-- Optional. Non-obvious things learned during implementation. Bullets. -->

### Out of scope
<!-- Optional. What was decided to skip during work on this task. -->

---------------------------------------

## <FEAT>-02: [Next Task Title]

**Status:** Todo
**Priority:** Medium
**Refs:**

### Problem
...

### Approach
...

### Reading list
...

### Acceptance
...

---------------------------------------

## Lifted holds
<!-- One line per lifted `Blocked-on question` marker; see the holds paragraph above. Empty until a hold is lifted. -->
