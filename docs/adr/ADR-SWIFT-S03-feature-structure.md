# ADR-SWIFT-S03: Feature Structure

**Date:** 2026-07-25
**Status:** Accepted
**Class:** System (portable across Swift / macOS app projects)

> This ADR is the anatomy of one `Features/<Name>/` folder from [ADR-SWIFT-S01](ADR-SWIFT-S01-repository-structure.md). The boundary it organizes around is **`@MainActor` vs not** — the macOS analogue of a server/client split.

## Problem

"Feature folder" without a defined interior degenerates in two predictable ways: everything becomes a view controller with state and I/O inside it, or everything becomes a manager singleton that views reach into. Both are untestable, and on macOS both tend to end with blocking work on the main thread.

The organizing question is not "model / view / controller". It is **what runs on the main actor and what does not** — because on macOS that boundary is enforced by the compiler under Swift 6, is where the app freezes if you get it wrong, and is exactly the line along which a feature becomes testable.

**Context:**
- Swift 6 strict concurrency makes `@MainActor` isolation a type-level property, not a convention.
- AppKit views and view controllers are `@MainActor` by declaration; nothing else in a feature has to be.
- A feature must be unit-testable without launching `NSApplication`, opening a window, or triggering a TCC permission prompt.

## Decision

**Each feature is a folder owning its views, its observable state, its feature-local logic, and its types, with one file as its public surface. Views and state are `@MainActor`; logic and services are not. Cross-feature needs are injected, never imported.**

### Anatomy

```
Features/<Name>/
├── <Name>Feature.swift       # the feature's public surface: factory + entry point
├── <Name>Coordinator.swift   # @MainActor — owns windows/menus for this feature (when it has any)
├── Views/                    # @MainActor — NSViewController / SwiftUI views. Rendering only.
├── State/                    # @MainActor — @Observable models the views read
├── Services/                 # explicitly `nonisolated` — feature-local logic, pure or actor-isolated
└── Model/                    # Sendable value types owned by this feature
```

Only `<Name>Feature.swift` and `Views/` are expected in every feature. `Coordinator`, `State/`, `Services/`, and `Model/` are added when the feature earns them — a feature that renders one pane from injected data needs none of them.

### Rules

1. **`Views/` renders; it does not decide.**
   A view reads `State/`, calls closures/methods it was handed, and renders. No file I/O, no framework calls into `Core/`, no business rules, no `Task { }` doing real work. If a view needs data, it was given it.

2. **`State/` is `@MainActor` and `@Observable`; it holds no I/O.**
   State objects are the read model for views. They are mutated by the coordinator or by a service result being handed back — not by the state object reaching out and fetching something.

3. **`Services/` is explicitly `nonisolated` and owns the logic.**
   Feature-local computation, sequencing, and validation live here as `struct`s of pure functions or as an `actor` when the feature owns mutable state that outlives a view. This is the layer with tests.

   **This applies to protocols too, not only to types.** Under
   `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` a *protocol declaration* is itself
   main-actor-isolated, which silently forces every conformance onto the main actor and
   defeats the seam — found when a `Core/` contract's live implementation compiled fine but
   could not be called from a non-main-actor test. Mark the protocol **and** its requirements
   `nonisolated`.

   Write the `nonisolated` keyword rather than relying on the *absence* of `@MainActor`. An app target may set `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (Swift 6.2+), under which an unannotated declaration is main-actor — silently pulling this layer onto the main thread and undoing the split. Explicit `nonisolated` is correct under **both** isolation modes, so the code does not depend on a build setting. See ADR-SWIFT-S07.

4. **`Model/` types are `Sendable` value types.**
   `struct`/`enum` crossing the actor boundary. A model type that cannot be `Sendable` is a signal that it is really state (rule 2) or a service handle (rule 3).

5. **The feature declares its needs; it does not resolve them.**
   `<Name>Feature.swift` exposes a factory taking the protocols it needs (ADR-SWIFT-S06 contracts, plus a `Deps` struct for genuine cross-feature needs). It never constructs a `Core/` service itself, never reads `UserDefaults` directly, and never reaches `NSApp.delegate`. Wiring happens at the composition root — ADR-SWIFT-S05.

6. **Features never import another feature's internals.**
   Another feature's `Model/` types are fair game (they are value types). Its `Views/`, `State/`, `Services/`, or coordinator are not. Cross-feature capability arrives through `Deps`.

7. **One public surface per feature.**
   Everything outside the feature folder talks to `<Name>Feature.swift`. In a single-module app the compiler will not enforce this; the file's existence is what makes a violation visible in review.

### The boundary in practice

```swift
// Features/Console/State/ConsoleState.swift — main actor, no I/O
@MainActor @Observable
final class ConsoleState {
    private(set) var lines: [ConsoleLine] = []   // ConsoleLine: Sendable model
    var filter: String = ""
    func append(_ line: ConsoleLine) { lines.append(line) }
}

// Features/Console/Services/ConsoleFormatter.swift — not main actor, pure, tested
nonisolated struct ConsoleFormatter: Sendable {
    func format(_ event: RuntimeEvent) -> ConsoleLine { /* … */ }
}

// Features/Console/ConsoleFeature.swift — the public surface
@MainActor
struct ConsoleFeature {
    struct Deps: Sendable {                       // genuine cross-feature needs only
        var evaluate: @Sendable (String) async throws -> String
    }
    static func make(runtime: any RuntimeService, deps: Deps) -> ConsoleCoordinator { /* … */ }
}
```

The test for `ConsoleFormatter` needs no window, no `NSApplication`, and no permissions. That is the point of the split.

### When a feature has no state

A feature that renders injected data and reports user intent through closures is complete with `Views/` and `<Name>Feature.swift` alone. Do not add an empty `State/` or a pass-through service "for consistency" — see ADR-SWIFT-S05 rule 1 for the same principle applied to `Deps`.

## Out of scope

- **Where the folder sits** — ADR-SWIFT-S01.
- **How `Core/` services are written** — ADR-SWIFT-S06.
- **How dependencies are wired** — ADR-SWIFT-S05.
- **Actor-hopping mechanics and callback bridging** — ADR-SWIFT-S07.

## Alternatives considered

| Option | Verdict |
|---|---|
| Feature folder split along the `@MainActor` boundary | **Chosen** — matches what the compiler enforces and what makes code testable |
| MVVM with a `ViewModel` per view, I/O inside the view model | Rejected — a view model that fetches is main-actor-bound and untestable without mocking the world; the split here puts the logic one layer further out |
| VIPER / Clean-architecture layering per feature | Rejected — five protocols per screen; the ceremony exceeds the problem for an app of this size |
| Kind-based folders (`Controllers/`, `Models/`, `Views/`) at the app level | Rejected — see ADR-SWIFT-S01 alternatives; a feature's files scatter |
| A `Manager` singleton per feature | Rejected — untestable, hides the dependency graph, and is the failure mode this ADR exists to prevent |

## Consequences

**Positive:** the testable layer is identifiable by folder; the compiler's actor isolation and the folder structure agree, so "where does this go" usually has one answer; a feature can be reviewed by reading one file (`<Name>Feature.swift`) plus the folder listing.

**Negative:** a small feature can look over-structured if the optional folders are created reflexively — the guard is rule "add when earned"; the single-module caveat from ADR-SWIFT-S01 applies, so the one-public-surface rule is a review convention, not a compile error.

## Related

- **Layout:** [ADR-SWIFT-S01](ADR-SWIFT-S01-repository-structure.md) — where `Features/` sits.
- **Stack:** [ADR-SWIFT-S02](ADR-SWIFT-S02-app-stack.md) — AppKit shell / SwiftUI content, `@Observable` state.
- **Service modules:** [ADR-SWIFT-S06](ADR-SWIFT-S06-pure-service-modules.md) — the protocols a feature is handed.
- **Dependency injection:** [ADR-SWIFT-S05](ADR-SWIFT-S05-dependency-injection.md) — `Deps` and the composition root.
- **Concurrency:** [ADR-SWIFT-S07](ADR-SWIFT-S07-concurrency-and-main-thread.md) — the isolation rules this anatomy encodes.
- **Conventions:** [`../conventions.md`](../conventions.md).
