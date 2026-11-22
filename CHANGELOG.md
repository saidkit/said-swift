# Changelog - said-swift

The releases of this Swift / AppKit macOS SAID starter, newest first. A cloned project records which release it is based on in its `## Lane` block (`SAID.starter:`); this file says what each release is. Versions follow [semver](https://semver.org/).

## said-swift@0.3.0 - 2026-11-22

- The `## Lane` block is stamped `said@0.28.0`.
- The SAID phases are named Scope, Act, Inspect, Debrief in the workflow section; the numbered phases are gone. `review-qa` is Inspect's hygiene gate in the QA checklist.

## said-swift@0.2.0 - 2026-11-04

- The `## Lane` block is stamped `said@0.26.0`: the lane passes the said upgrade checks up to that release.
- The task template carries the operator-question hold: the `**Blocked-on question:**` field and the `## Lifted holds` section, lifted only by a recorded ruling.
- A `native-build` Checker in `docs/ux/feature-ux-rules.md` runs `make ci` as the lane's oracle, and the lane declares it in `SAID.reviewers:`.
- Earned rules carry `R-SWIFT-NN` ids and one link to their record each.

## said-swift@0.1.0 - 2026-11-03

Initial versioned release of the **said-swift** Swift 6 / AppKit macOS app starter.

- The `ADR-SWIFT-S01..S11` spine (repository structure, app stack, feature structure, versions and upgrades, dependency injection, pure service modules, concurrency and the main thread, settings and data storage, error handling and logging, build / signing / distribution, quality gates).
- The `docs/` context spine (conventions, ADRs, feature spec and task-log templates, QA and UX checklists) and the append-only task-log discipline.
- The keyed `## Lane` block (`SAID.surface: native`, `SAID.profile: code`, `SAID.commands: make ci`) and the tiered `make` gates (`pre-commit`, `ci`, `validate`, `tooling-check`).
