# ADR-SWIFT-S01: Repository Structure (macOS app)

**Date:** 2026-07-25
**Status:** Accepted
**Class:** System (portable across Swift / macOS app projects)

## Problem

An Xcode-built macOS app needs a predictable internal organization so features land in the same places every time, the main-thread boundary is obvious, and context loading stays targeted. Xcode's defaults actively work against this: the New Project template drops every file into one flat group, build settings default to the `.pbxproj`, and `AppDelegate` is the path of least resistance for any logic that needs to run at launch.

**Context:**
- One app target produces one binary; Swift compiles it as a **single module**, so there is no compiler-enforced boundary between folders.
- `project.pbxproj` is a generated, merge-hostile file. Anything stored there is invisible to `git diff` review and is the single worst merge-conflict surface in the repo.
- macOS apps carry non-source surface — entitlements, `Info.plist`, asset catalogs, signing identity — that is as load-bearing as the code.
- Optimised for both humans and LLMs finding code by convention.

## Decision

**A single app target with a conventional source layout. `AppDelegate` composes; features implement. All build settings live in `.xcconfig` files. System frameworks and external systems sit behind service protocols in `Core/`.**

### Canonical layout

```
project/
├── docs/                              # the SAID spine (this directory)
├── <Product>/                         # app target sources — ours
│   ├── App/                           # lifecycle + composition root (S05)
│   │   ├── AppDelegate.swift          # thin: builds the environment, hands off
│   │   ├── AppEnvironment.swift       # the composition root's dependency graph
│   │   └── main.swift                 # the entry point — see rule 9
│   ├── Features/<Name>/               # FEATURE MODULES — where capability lives (S03)
│   ├── Core/                          # cross-feature, feature-agnostic
│   │   ├── <Service>/                 # external-system / framework seam (S04)
│   │   ├── Extensions/                # Foundation/AppKit extensions (Type+Feature.swift)
│   │   └── Support/                   # logging, errors, small utilities
│   ├── UI/                            # shared cross-feature views + design tokens
│   ├── Resources/                     # Assets.xcassets, .xib/.storyboard, .strings
│   ├── Supporting/                    # Info.plist, *.entitlements, bridging header
│   └── Build Configs/                 # ALL build settings (S06)
│       ├── Project-Base.xcconfig
│       ├── <Product>-Base.xcconfig
│       └── <Product>-{Debug,Release}.xcconfig
├── <Product>Tests/                    # unit tests, mirroring the source tree
├── <Product>UITests/                  # XCUITest — optional
├── scripts/                           # build / release / notarize entry points
├── Makefile                           # command facade → scripts + xcodebuild (S06)
├── .swiftlint.yml  .swift-format      # lint / format config (R-GATE-LINT, R-GATE-FORMAT)
└── <Product>.xcodeproj                # (+ .xcworkspace when a package manager needs one)
```

### Rules

1. **`AppDelegate` composes; it doesn't implement.**
   `applicationDidFinishLaunching` builds the dependency graph (S05) and hands control to feature coordinators. It holds no business logic, no window layout, no I/O. If it exceeds ~100 lines, logic has leaked into it.
2. **Features are the unit of implementation.**
   A cohesive capability lives in `<Product>/Features/<Name>/` and owns its views, view models, feature-local services, and types — see ADR-SWIFT-S03.
3. **All build settings live in `.xcconfig`.**
   The target's Build Settings tab must show no overrides beyond the xcconfig assignment. A setting in `project.pbxproj` is a setting nobody will review — see ADR-SWIFT-S06.
4. **System frameworks and external systems sit behind protocols in `Core/<Service>/`.**
   Never call a permission-gated or process-global framework API directly from a view or view model. The protocol is the seam that makes the feature testable — see ADR-SWIFT-S04.
5. **`Core/` and `UI/` never import `Features/`.**
   The dependency direction is one-way. Because Swift compiles the app as one module the compiler will not stop you; this is enforced by review and by the folder discipline.
6. **Resources are declarative.**
   No logic in `.xib`/`.storyboard` beyond outlets and actions. Prefer programmatic views or SwiftUI content hosted in AppKit (ADR-SWIFT-S02).
7. **One target per shipped binary.**
   CLI helpers, login items, XPC services, and Spotlight/Share extensions are their own targets with explicit dependency edges and their own xcconfig — never files bolted onto the app target.
8. **Tests mirror the source tree.**
   `<Product>Tests/Features/<Name>/…` matches `<Product>/Features/<Name>/…`. A reader who knows where the code is knows where its test is.

9. **The entry point is `main.swift`, not `@main` on the delegate.**
   Construct `NSApplication`, assign the delegate, set the activation policy, call `run()`.
   Verified failure: `@main` on an `NSApplicationDelegate` did **not** invoke
   `applicationDidFinishLaunching` in an app target — the process launched and stayed alive,
   the callback never fired, and no window appeared. Nothing errored, which is what makes it
   expensive to diagnose. The explicit form is also the only one that states activation policy
   plainly, which an agent or menu-bar app must control anyway.

### Dependency direction

```
App/ (composition root)  →  Features/<Name>/  →  Core/<Service>/  →  system frameworks / external
                         ↘   UI/ (shared views)   ↗
```

Lower layers never import upward. **Features never reach into another feature's internals** — share via `Core/`, `UI/`, or dependency injection (ADR-SWIFT-S05).

### When the single-module boundary is not enough

Swift's `internal` is module-wide, so nothing prevents a view from calling another feature's service. Two escalations, in order:

1. **Convention + review** (default). Cheap, sufficient for a single-team app.
2. **Local SPM package per boundary.** Move `Core/<Service>/` or a feature into `Packages/<Name>/` and depend on it from the app target. Now `public` is a real contract and the compiler enforces it. Do this when a boundary has been violated twice, not preemptively — it costs build-graph complexity and slows incremental builds.

Do **not** reach for a multi-module split as the starting layout. Most macOS apps never need it.

## Out of scope

- **Feature internals** — ADR-SWIFT-S03.
- **Service-module internals** — ADR-SWIFT-S04.
- **Wiring / DI** — ADR-SWIFT-S05.
- **Build settings, signing, distribution** — ADR-SWIFT-S06.
- **Where user data and settings live on disk** — ADR-SWIFT-S08 (this ADR covers the *repo*, not the *installed footprint*).

## Alternatives considered

| Option | Verdict |
|---|---|
| `App/` + `Features/` + `Core/` + `UI/`, settings in xcconfig | **Chosen** — predictable locations, reviewable build config, testable seams |
| Xcode default flat group, settings in the target editor | Rejected — every setting change is an unreviewable `pbxproj` diff; no seams |
| MVC-by-kind (`Controllers/`, `Views/`, `Models/`) | Rejected — a feature's files scatter across three folders; touching one capability means three directories |
| Multi-module SPM from day one (`Packages/*` per feature) | Rejected as the default — real enforcement, but pays build-graph and incremental-build cost before any boundary has been violated. Available as an escalation |
| Workspace of several app targets | Rejected — one shipped binary; a second target is a second thing to sign, notarize, and keep in version lockstep |

## Consequences

**Positive:** predictable locations for humans and LLMs; build configuration is a reviewable text diff; `pbxproj` conflicts drop to file-membership changes only; each external system has exactly one swappable seam; `AppDelegate` stays readable.

**Negative:** more folders than Xcode's default; the `Core/`→`Features/` direction has no compiler enforcement in a single module and depends on review; adding a file still touches `pbxproj` (unavoidable in an Xcode-driven project).

## Related

- **Stack:** [ADR-SWIFT-S02](ADR-SWIFT-S02-app-stack.md) — language, UI framework, and dependency policy this layout assumes.
- **Feature internals:** [ADR-SWIFT-S03](ADR-SWIFT-S03-feature-structure.md) — the anatomy of `Features/<Name>/`.
- **Service modules:** [ADR-SWIFT-S04](ADR-SWIFT-S04-pure-service-modules.md) — the `Core/<Service>/` seam.
- **Dependency injection:** [ADR-SWIFT-S05](ADR-SWIFT-S05-dependency-injection.md) — how features receive services.
- **Build & distribution:** [ADR-SWIFT-S06](ADR-SWIFT-S06-build-signing-distribution.md) — the `Build Configs/` layer and the `Makefile` facade.
- **Conventions:** [`../conventions.md`](../conventions.md).
