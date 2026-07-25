# ADR-SWIFT-S02: App Stack (Swift 6 / AppKit shell with SwiftUI content)

**Date:** 2026-07-25
**Status:** Accepted
**Class:** System (portable across Swift / macOS app projects)

## Problem

"Which UI framework" is the decision that constrains every later one — window behaviour, state model, testability, minimum OS version, hiring, and how much of the platform is reachable at all. SwiftUI is the default answer for new Apple platform work and the wrong default for a *system-level* macOS app: the parts of AppKit it does not cover are exactly the parts a utility app is made of.

The stack decision also has to survive Swift 6's concurrency checking, which is not optional in new code and is not a lint rule — it changes what compiles.

**Context:**
- Target class of app: a macOS-only utility / system app — menu bar presence, multiple windows, global hotkeys, accessibility APIs, background work.
- Swift 6 strict concurrency is available and enforceable at compile time.
- Every third-party dependency in a signed, notarized, hardened-runtime binary is a supply-chain and signing liability.

## Decision

**Swift 6 with strict concurrency complete. AppKit owns the app shell; SwiftUI renders pane content inside it. Dependencies are opt-in and justified individually, defaulting to none.**

### The stack

| Concern | Choice | Note |
|---|---|---|
| Language | **Swift 6**, `SWIFT_STRICT_CONCURRENCY = complete` | non-negotiable for new code; data races become compile errors (ADR-SWIFT-S07) |
| App shell | **AppKit** — `NSApplication`, `NSApplicationDelegate`, `NSWindowController`, `NSStatusItem`, `NSMenu` | owns lifecycle, activation policy, windows, menu bar |
| View content | **SwiftUI**, hosted via `NSHostingView` / `NSHostingController` | panes, settings, list/detail content |
| State | **`@Observable`** (Observation) where the deployment target allows; otherwise plain value types + explicit change callbacks | avoid Combine for new code; it is legacy-adjacent |
| Concurrency | Swift structured concurrency — `async/await`, `Task`, `actor`, `@MainActor` | GCD only where a C API demands a `dispatch_queue_t` (ADR-SWIFT-S07) |
| Persistence | `UserDefaults` + files | see ADR-SWIFT-S08. No Core Data / SwiftData without a relational need |
| Logging | **`os.Logger`** (unified logging) | never `print` in shipped code (ADR-SWIFT-S09) |
| Tests | **Swift Testing** (`import Testing`) for new tests; XCTest for UI tests and inherited suites | changes how test code is written, so it is a stack choice |
| Lint / format / gates | **SwiftLint** + **`swift-format`** | tiering, tool rationale, and the conflict rule → [ADR-SWIFT-S10](ADR-SWIFT-S10-quality-gates.md) |
| Dependencies | **SPM**; none by default | CocoaPods only when inherited from a vendored tree |

### Why AppKit is the shell, not SwiftUI

SwiftUI's `App`/`Scene` lifecycle is a lossy abstraction over `NSApplication`. A system-level macOS app needs, at minimum:

- `NSApplication.setActivationPolicy(.accessory)` and switching it at runtime (dock icon on/off)
- `NSStatusItem` with precise click/right-click/drag behaviour and a template image
- window level, collection behaviour, and non-activating panels (`NSPanel`, `.nonactivatingPanel`)
- the Services menu, the dock menu, `application(_:open:)` URL handling
- `NSEvent` global/local monitors and `CGEvent` taps

Each is reachable from SwiftUI only through an `NSApplicationDelegateAdaptor` plus an escape hatch — at which point AppKit is running the app anyway, with the lifecycle obscured. Starting from AppKit and hosting SwiftUI *inside* it is the same amount of SwiftUI with none of the indirection.

**The rule:** anything that talks to `NSApplication`, a window, the menu bar, or the event stream is AppKit. Anything that is a rectangle of content is SwiftUI.

### Dependency policy

A dependency must clear all four before it is added:

1. It solves a problem that is genuinely hard (a protocol implementation, a parser, a crypto primitive) — not a convenience wrapper.
2. It is compatible with hardened runtime and does not require disabling library validation.
3. It is SPM-consumable and pinned to an exact version.
4. Its absence would cost more than a week to reimplement.

Sparkle (updates) and a crash reporter typically clear this bar. UI convenience libraries, reactive frameworks, and DI containers do not.

## Out of scope

- **Concurrency mechanics and the main-thread boundary** — ADR-SWIFT-S07.
- **Which gate runs when, and how the tools are kept from fighting** — ADR-SWIFT-S10.
- **Where state is persisted** — ADR-SWIFT-S08.
- **Signing / notarization consequences of a dependency** — ADR-SWIFT-S06.

## Alternatives considered

| Option | Verdict |
|---|---|
| AppKit shell + SwiftUI content | **Chosen** — full platform reach, modern view code where it pays |
| Pure SwiftUI (`App`/`Scene` lifecycle) | Rejected — activation policy, status item behaviour, panels, and event taps all require an AppKit escape hatch; the lifecycle ends up AppKit-driven but hidden |
| Pure AppKit (`NSViewController` + xib everywhere) | Rejected — view code is 3–5× the volume for the same result; xib diffs are unreviewable |
| Catalyst / cross-platform | Rejected — macOS-only app; Catalyst forfeits exactly the AppKit surface this class of app needs |
| Objective-C for new code | Rejected — no memory-safety or concurrency checking; only justified when a C-level symbol contract forces it (see the consuming project's ADRs) |
| Combine for state | Rejected for new code — Observation covers the need with less ceremony and no retain-cycle class of bug |

## Consequences

**Positive:** the whole platform stays reachable; SwiftUI is used where it is strongest (declarative content) and avoided where it is weakest (lifecycle and chrome); strict concurrency turns a category of shipping bug into a build failure; a near-zero dependency surface keeps notarization and library validation uncomplicated.

**Negative:** two UI paradigms in one codebase — the AppKit↔SwiftUI seam (`NSHostingView`, bridging state) has to be written and understood; strict concurrency has a real up-front cost on any code touching legacy callback APIs; `@Observable` sets a floor on the deployment target that must be checked against the product's support matrix.

## Related

- **Layout:** [ADR-SWIFT-S01](ADR-SWIFT-S01-repository-structure.md) — the structure this stack assumes.
- **Feature anatomy:** [ADR-SWIFT-S03](ADR-SWIFT-S03-feature-structure.md) — where views, state, and services sit relative to the MainActor boundary.
- **Concurrency:** [ADR-SWIFT-S07](ADR-SWIFT-S07-concurrency-and-main-thread.md) — the rules strict concurrency imposes.
- **Conventions:** [`../conventions.md`](../conventions.md) — the copyable patterns for each row of the stack table.
