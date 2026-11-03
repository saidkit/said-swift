# Architecture Decision Records

Point-in-time records of **why** a non-obvious decision was made. ADRs are history, not live state — read the relevant one when working in that area; **don't preload all of them**, and verify against the actual code (an ADR may have been superseded).

Two classes live here:

- **STARTER ADRs** (`ADR-SWIFT-S0x`) - cross-cutting decisions **portable across Swift / macOS app projects** (repo anatomy, stack, patterns, build chain). These are the said-swift template spine and ship with the template.
- **Project ADRs** (`ADR-SWIFT-00x`) - decisions specific to *your* product. They instantiate or override the STARTER ADRs. **The template ships none** - the first one you write is yours.

## Quick Reference

| Load this | When you need to |
|---|---|
| ADR-SWIFT-S01-repository-structure.md | Understand where code goes (app target layout, xcconfig, dependency direction) |
| ADR-SWIFT-S02-app-stack.md | Choose / understand the stack (Swift 6, AppKit shell + SwiftUI content, dependency policy) |
| ADR-SWIFT-S03-feature-structure.md | Lay out a feature's internals (Views / State / Services, the `@MainActor` boundary) |
| ADR-SWIFT-S05-dependency-injection.md | Wire dependencies (`AppEnvironment`, per-feature `Deps`, no singletons) |
| ADR-SWIFT-S06-pure-service-modules.md | Wrap a system framework or external system behind a contract |
| ADR-SWIFT-S07-concurrency-and-main-thread.md | Cross an isolation boundary, bridge a callback, or keep work off the main thread |
| ADR-SWIFT-S08-settings-and-data-storage.md | Decide where a piece of state lives on the user's disk |
| ADR-SWIFT-S09-error-handling-and-logging.md | Handle a failure, log it, or decide whether the user sees it |
| ADR-SWIFT-S10-build-signing-distribution.md | Build, sign, notarize, version, or ship |
| ADR-SWIFT-S11-quality-gates.md | Add or move a quality gate, or reconcile the formatter with the linter |

## Index

### STARTER (template spine - portable)

| ADR | Topic |
|---|---|
| ADR-SWIFT-S01-repository-structure.md | Repository structure (app target layout; settings in xcconfig; one-way dependency direction) |
| ADR-SWIFT-S02-app-stack.md | App stack (Swift 6 strict concurrency; AppKit shell with SwiftUI content; near-zero dependencies) |
| ADR-SWIFT-S03-feature-structure.md | Feature structure (feature anatomy along the `@MainActor` boundary) |
| ADR-SWIFT-S05-dependency-injection.md | Dependency injection (`AppDelegate` composition root; `AppEnvironment`; per-feature `Deps`) |
| ADR-SWIFT-S06-pure-service-modules.md | Pure service modules (system frameworks and external systems behind contracts) |
| ADR-SWIFT-S07-concurrency-and-main-thread.md | Concurrency & the main-thread boundary (actor isolation; explicit hops from legacy callbacks) |
| ADR-SWIFT-S08-settings-and-data-storage.md | Settings & data storage (three stores split by the text-editor test) |
| ADR-SWIFT-S09-error-handling-and-logging.md | Error handling & logging (typed per-seam errors; expected vs unexpected; `os.Logger`) |
| ADR-SWIFT-S10-build-signing-distribution.md | Build, signing & distribution (xcconfig layering; `make` facade; notarize -> staple; derived versioning) |
| ADR-SWIFT-S11-quality-gates.md | Quality gates (tiering by feedback cost; both git hooks; one owner per concern, asserted) |

### Project (your product)

<!-- Add a row per project ADR as you write them: ADR-SWIFT-001, -002, … -->

_None yet — the template ships no project ADRs._

### Relationships

- **ADR-SWIFT-S01 is the structural spine.** S03 (feature internals), S06 (service seam), and S05 (wiring) each elaborate one seam of the S01 layout; S10 owns its `Build Configs/` layer.
- **ADR-SWIFT-S02 sets the stack** (Swift 6, AppKit+SwiftUI, strict concurrency) that S01's layout and S03's boundary assume.
- **ADR-SWIFT-S07 is the boundary S03 organizes around** — S03 is *where the folders go*, S07 is *what the compiler enforces across them*.
- **ADR-SWIFT-S06 and S05 are two halves of one seam**: S06 defines the contract, S05 decides who constructs and injects it. S09 rule 1 lives at the same boundary (translate framework errors there).
- **ADR-SWIFT-S10 ships what S01/S02 build** - it delivers the artifact and owns version identity; it does not re-decide the stack.
- **ADR-SWIFT-S08 is the installed footprint**, the counterpart to S01's repository footprint. Its `SettingsService` facade is an S06 contract, injected per S05 rule 9.
- **ADR-SWIFT-S11 decides when every gate runs**, and is the counterpart to the QA checklist (which owns the `verify:` command) and the `Makefile` (which owns the command). It defers the release tier to S10 and the compiler posture to S02.
- **ADR-SWIFT-S09 spans the whole structure** - translation at the S06 seam, classification in S03 features, surfacing per the UX gate.

## Naming

- **ADR-SWIFT-S0x** - STARTER ADR. Portable across Swift / macOS app projects. Changing one is a template-level decision, and diverging from the shipped text means your copy has forked from the template.
- **ADR-SWIFT-00x** — Project ADR. Specific to your product.

## Creating a new ADR

1. Propose the next sequential number (separate sequences for system and project ADRs).
2. Use [`template.md`](template.md).
3. Create an ADR when the decision **affects multiple features or is hard to reverse**. Record the decision and its *why*; link the feature / working notes that drove it.
4. **Cross-reference** related ADRs in the Relationships section.
5. **After landing:** add a row to the Index (and Quick Reference) and update Relationships. Don't list an ADR file that doesn't exist (**no dangling pointers**).
6. A project ADR that contradicts a system ADR must say so explicitly and say why — silent divergence is how a template stops being one.
