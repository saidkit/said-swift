# Changelog - said-swift

The releases of this Swift / AppKit macOS SAID starter, newest first. A cloned project records which release it is based on in its `## Lane` block (`SAID.starter:`); this file says what each release is. Versions follow [semver](https://semver.org/).

## said-swift@0.1.0 - 2026-11-03

Initial versioned release of the **said-swift** Swift 6 / AppKit macOS app starter.

- The `ADR-SWIFT-S01..S11` spine (repository structure, app stack, feature structure, versions and upgrades, dependency injection, pure service modules, concurrency and the main thread, settings and data storage, error handling and logging, build / signing / distribution, quality gates).
- The `docs/` context spine (conventions, ADRs, feature spec and task-log templates, QA and UX checklists) and the append-only task-log discipline.
- The keyed `## Lane` block (`SAID.surface: native`, `SAID.profile: code`, `SAID.commands: make ci`) and the tiered `make` gates (`pre-commit`, `ci`, `validate`, `tooling-check`).
