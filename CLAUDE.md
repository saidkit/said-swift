# CLAUDE.md — said-swift Development Guide

## Lane

A **lane** is a tree that owns a full SAID cycle: its own feature specs, task log, working dir and ADRs. A lane is **not a mount**: a project may build into several mounts and remain one lane. This project is one lane and single-app (no app segment in the task id); `scripts/` and `stencils/` are tooling, not lane code. Single-lane work is `said!`; `flow!` is for a feature spanning **two or more task logs**, which this project does not have.

- SAID.lane:         said-swift
- SAID.starter:      said-swift@0.1.0
- SAID.docs-root:    docs/
- SAID.mounts:       [<Product>/]
- SAID.feature-spec: docs/features/<id>.md
- SAID.task-log:     docs/features/<id>.tasks.md
- SAID.working:      docs/working/<id>/
- SAID.id-shape:     <FEAT>-<NN>
- SAID.adr-prefix:   ADR-SWIFT-*
- SAID.surface:      native
- SAID.reviewers:    none
- SAID.commands:     make ci
- SAID.profile:      code

## Project Overview
**Project**: <PROJECT> — <one line: what this app is>
**Template**: said-swift — Swift 6 / AppKit macOS app starter (the `ADR-SWIFT-S0x` spine + `docs/` contract)
**Architecture**: `AppDelegate` composes → `Features/<Name>/` implement → `Core/<Service>/` wraps system frameworks; AppKit shell hosting SwiftUI content; strict concurrency

## Quick Start
Start with **this file only**. Then load deeper context by task — see **Implementation References** (what to read before changing code) and **Context Loading** (what to load, when).

## Implementation References (Check BEFORE changing code)

| Creating / Changing… | Read First |
|---|---|
| ADR landscape (index, relationships, naming) | `docs/adr/README.md` |
| Repo structure / where code goes | `docs/adr/ADR-SWIFT-S01-repository-structure.md` |
| Stack (Swift version, AppKit vs SwiftUI, dependencies) | `docs/adr/ADR-SWIFT-S02-app-stack.md` |
| Feature internals (Views / State / Services, MainActor boundary) | `docs/adr/ADR-SWIFT-S03-feature-structure.md` |
| Touching a system framework or external system | `docs/adr/ADR-SWIFT-S06-pure-service-modules.md` |
| Wiring dependencies / adding to the composition root | `docs/adr/ADR-SWIFT-S05-dependency-injection.md` |
| Build settings, signing, entitlements, notarization, versioning | `docs/adr/ADR-SWIFT-S10-build-signing-distribution.md` |
| Concurrency, actor isolation, bridging a callback | `docs/adr/ADR-SWIFT-S07-concurrency-and-main-thread.md` |
| Where a piece of state lives on disk | `docs/adr/ADR-SWIFT-S08-settings-and-data-storage.md` |
| Error handling, logging, alerts | `docs/adr/ADR-SWIFT-S09-error-handling-and-logging.md` |
| Coding conventions (how-to, code patterns) | `docs/conventions.md` |
| Architecture overview | `docs/vision.md` |
| Feature spec template | `docs/features/template.md` |
| Editing a specific feature | `docs/features/<FEAT>-<NN>.md` |
| Surface UX shape | `docs/ux/README.md` |
| Surface UX review gate | `docs/qa/feature-ux-checklist.md` |
| Quality-gate definitions (`R-GATE-*`) | `docs/qa/feature-qa-checklist.md` |
| Which gate runs when / adding a gate / tool conflicts | `docs/adr/ADR-SWIFT-S11-quality-gates.md` |

## Context Loading Strategy

**Start light → add as needed → keep the working set lean (< ~50k tokens).**

**1. Session start (always):** this guide.

**2. Add by task type:**
- Code review / understanding → `docs/conventions.md`
- Feature development → `docs/conventions.md` + `docs/features/<FEAT>-<NN>.md`
- New feature → `docs/conventions.md` + `ADR-SWIFT-S03` + `docs/features/template.md`
- Touching a framework → `ADR-SWIFT-S06` + `ADR-SWIFT-S07`
- Build / signing / release → `ADR-SWIFT-S10` + `docs/qa/feature-qa-checklist.md`
- Adding or moving a quality gate → `ADR-SWIFT-S11`
- Architecture → `docs/vision.md` + `docs/idea.md` + `docs/adr/README.md`

**3. Load implementation files (only when editing):**
- Feature work → `<Product>/Features/<Name>/`
- Wiring → `<Product>/App/`
- Framework seam → `<Product>/Core/<Service>/`
- Build config → `<Product>/Build Configs/*.xcconfig`

## File Structure
```
docs/
├── idea.md                       # Product context (why)
├── vision.md                     # Technical architecture (what)
├── conventions.md                # Code patterns (how)
├── adr/
│   ├── ADR-SWIFT-S0x-topic.md    # STARTER ADRs - the portable said-swift spine
│   └── ADR-SWIFT-00x-topic.md    # Project ADRs — this product (none ship with the template)
├── features/
│   ├── README.md                 # Feature structure reference
│   ├── template.md               # Feature spec stencil
│   ├── template-tasks.md         # Task log stencil + authoring discipline
│   └── <FEAT>-<NN>.md            # Feature specs
├── qa/
│   ├── feature-qa-checklist.md   # R-GATE-* definitions (the only place verify: lives)
│   └── feature-ux-checklist.md   # per-surface UX gate
├── ux/                           # UX shape specs (shell / menubar / settings / lists / errors)
└── working/<feature-id>/         # operator workspace — never cited from a task body
```

## Navigation Map

| Type | Location | Load When |
|---|---|---|
| Feature specs | `docs/features/<FEAT>-<NN>.md` | working on that feature |
| Composition root | `<Product>/App/` | wiring a dependency, launch sequencing |
| Feature modules | `<Product>/Features/<Name>/` | building a feature |
| Framework seams | `<Product>/Core/<Service>/` | touching a system framework |
| Shared UI | `<Product>/UI/` | extracting cross-feature views |
| Build settings | `<Product>/Build Configs/*.xcconfig` | any build/signing change |
| Entitlements / Info.plist | `<Product>/Supporting/` | capabilities, URL schemes, permissions |
| ADRs | `docs/adr/` | an architectural decision |

## Development Commands

Run from the repo root through `make` (the command facade → `scripts/` + `xcodebuild`):

```bash
make doctor         # what can run, hooks installed, lint scope agreement
make pre-commit     # FAST tier (seconds) — format-check + lint
make ci             # FULL tier (minutes) — + build + test   ← run at task close
make validate       # RELEASE tier — R-GATE-SIGN + R-GATE-HARDENING (needs a built bundle)
make tooling-check  # assert swift-format and SwiftLint agree — after any config change
make install-hooks  # pre-commit hook → fast tier, pre-push hook → full tier
make format         # rewrite in place (your editor should do this on save)
make scan           # opt-in: gitleaks + periphery
make clean
```

Gates are **tiered by cost** — in Swift the build *is* the typecheck and costs minutes, so a
pre-commit hook that builds gets bypassed, and a bypassed gate is worse than none
(ADR-SWIFT-S11).

Never inline a raw `xcodebuild` invocation into a doc, a task entry, or CI — add a `Makefile` target instead (ADR-SWIFT-S10).

## Workflow Process
1. **Analyze** — understand the task (load minimal context)
2. **Plan** — propose implementation (add relevant context)
3. **Wait** — get approval before coding
4. **Implement** — follow `docs/conventions.md`
5. **Test** — `make ci`; run the app for UI-affecting change
6. **Update** — update the feature / task log
7. **Commit** — save to branch (only when asked)

## SAID workflow — the `said:` plugin
This template is the **context spine** (`docs/conventions.md`, `docs/adr/`, `docs/features/`, `docs/working/`); the **`said:` plugin** drives the phases *over* that spine. Each command reads/writes a specific part of the context — invoke the phase you're in.

- **Triage** (find where a bug/behavior lives) → `/said:triage`
- **Phase 1 — Scope** → `/said:scope-refine` (from a handoff / current branch) or `/said:scope-grill` (ideate a thin idea) → writes `docs/working/<feature>/scope.md`
- **Phase 1.5 — Spec TOC** → `/said:uxtoc` (descriptive outline of a spec, for fast iteration)
- **Phase 2 — Architect** → `/said:architect` (`scope.md` → `docs/features/<FEAT>-<NN>.md` + `<FEAT>-<NN>.tasks.md`); `/said:add-task` to append a task discovered mid-flight
- **Phase 3 — Implement** → `/said:impl` (drive a task `Todo → Done` under TDD); `/said:review-ux` (per-surface UX gate for UI work)
- **Phase 3.5 — Verify** → `/said:review-qa` (quality gates + `### Fix` integrity) then `/said:accept` (acceptance-criteria contract)
- **Phase 4 — Debrief** → `/said:debrief` (feature retro; backport lessons into `docs/adr/` + `docs/conventions.md`)

The **Workflow Process** above is the lightweight per-change loop; the `said:` phases are the full feature lifecycle. Both land in the same spine.

## Core Principles
- **Context Efficiency** — load only what you need
- **KISS** — simple solutions over complex
- **MVP First** — working version, then improve
- **Compile-time safety** — let the type system and strict concurrency catch it
- **Main thread is sacred** — anything that can block doesn't run on it
- **Test Everything** — untested code is broken code; no test needs a window or a permission prompt

## Claude Code Reminders
- **Context Management**: start with this guide only, add incrementally
- **File Loading**: only load files you're actively editing
- **Quality Gates**: always run `make ci` before marking complete; if a gate cannot run, say which and why — never claim a pass that didn't happen
- **Commit Policy**: NEVER commit without explicit user request
- **Read First**: always read files before editing them
- **Build settings**: `.xcconfig` only, never the Xcode target editor
- **Diagrams**: use Mermaid or nested outlines — NEVER ASCII art / pseudographics
- **Markdown**: one line per paragraph; bullets one line each; no hard-wrap; prefer lists over tables — use tables only when necessary

## Task Log Rules (`<FEAT>-<NN>.tasks.md`)
**CRITICAL: Task logs are append-only historical records.** Authoring discipline + close-of-task review live in `docs/features/template-tasks.md` — canonical source. Read it before writing or closing any task entry.

Critical rules (full set in template-tasks.md):
- **NEVER overwrite or strip detail** from existing entries
- **New tasks get new IDs** appended at the end (no mid-task amendments)
- **`### Fix` = one verification line** + optional one-liners (spec edits) — never `**Files added:**` blocks; files are derivable from `git log --name-only`
- **When updating status**: change only the `Status:` line; add/update `### Fix`, optionally `### Deviations` and `### Gotchas`
- **When adding new tasks**: append new `## <FEAT>-<NN>` sections at the end. Never reorganize or renumber existing tasks.
- **Fix sections**: document what was actually done, including deviations, bugs found, and outcomes. This is the implementation record.

## Documentation Rules
IMPORTANT: NEVER use ASCII/Unicode box-drawing characters for diagrams.
Use instead:
1. **Mermaid** (preferred for complex flows)
2. **Nested outlines** (simpler alternative)

## Quality Gates
Before marking complete:
- [ ] `make ci` clean — R-GATE-FORMAT, R-GATE-LINT, R-GATE-BUILD, R-GATE-TEST
- [ ] `make validate` — R-GATE-SIGN + R-GATE-HARDENING (signing / entitlements / release tasks only)
- [ ] `make tooling-check` — R-GATE-TOOLING (only if a lint/format config or tool version changed)
- [ ] New dependency or entitlement justified — R-GATE-DEPS
- [ ] Feature / task log updated

**`make ci` is the task-close bundle**, not `make pre-commit` — the latter is the fast inner-loop
subset. Rule definitions and tiers: `docs/qa/feature-qa-checklist.md`. Tiering rationale:
`docs/adr/ADR-SWIFT-S11-quality-gates.md`.

---

**Usage Philosophy**: Start minimal, expand thoughtfully, clean up regularly.

---

## Earned rules (full context in the linked ADR)
- **`AppDelegate` composes, it doesn't implement** — it builds `AppEnvironment` and hands off; no logic → ADR-SWIFT-S01, S05
- **All build settings live in `.xcconfig`** — a setting in `project.pbxproj` is a setting nobody reviewed → ADR-SWIFT-S10
- **UI is `@MainActor`, logic is not** — annotate the type; blocking work never runs on the main actor → ADR-SWIFT-S03, S07
- **Every legacy callback hops explicitly, on its first line** — a C/ObjC callback carries no isolation information → ADR-SWIFT-S07
- **`DispatchQueue.main.sync` is forbidden** — deadlocks now or later, never correct → ADR-SWIFT-S07
- **One import site per framework** — the `Live<Service>` file; contracts speak the app's types, never `AXUIElement`/`OSStatus` → ADR-SWIFT-S06
- **Never cast `NSApp.delegate`** — if an object needs it, it should have been handed it → ADR-SWIFT-S05
- **No singletons with I/O, state, or permissions** — `static let shared` is for immutable values → ADR-SWIFT-S05
- **Three stores, split by the text-editor test** — `UserDefaults` for app settings, a user-visible dir for hand-authored config, Application Support for generated data → ADR-SWIFT-S08
- **Expected vs unexpected decides the response** — expected failures surface in place; unexpected ones are logged; alerts are for decisions → ADR-SWIFT-S09
- **`os.Logger`, never `print`** — a background app has no stdout → ADR-SWIFT-S09
- **Permission failures get a route, not a message** — a System Settings deep link, not an OK button → ADR-SWIFT-S09
- **Gates are tiered by cost, and both git hooks are wired** — `pre-commit` fast, `pre-push` full; a bypassed gate is worse than none → ADR-SWIFT-S11
- **One owner per concern, asserted** — where swift-format and SwiftLint overlap the formatter wins, and `make tooling-check` proves they agree → ADR-SWIFT-S11
- **`get-task-allow` never ships** — debugger attach on a release build, and a notarization rejection → ADR-SWIFT-S10
- **Write `@MainActor` and `nonisolated` explicitly** — never rely on the absence of an annotation; default isolation is a build setting → ADR-SWIFT-S07
- **Bundle ID and `CFBundleVersion` are one-way doors** — TCC grants and update floors are keyed to them → ADR-SWIFT-S10

<!-- ============================================================================
     PROJECT-SPECIFIC SECTION — intentionally empty in the said-swift starter.
     A consuming app appends its product overview, repository topology, platform
     integrations, signing identity, and open questions here
     (Model A: one file = template + project section).
     ============================================================================ -->
