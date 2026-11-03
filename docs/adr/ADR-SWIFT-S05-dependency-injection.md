# ADR-SWIFT-S05: Dependency Injection

**Date:** 2026-07-25
**Status:** Accepted
**Class:** System (portable across Swift / macOS app projects)

> This is the *how* behind [ADR-SWIFT-S01](ADR-SWIFT-S01-repository-structure.md)'s "features never reach into another feature's internals" and [ADR-SWIFT-S06](ADR-SWIFT-S06-pure-service-modules.md)'s "features receive the protocol, they never construct the implementation."

## Problem

Cocoa's ambient globals make dependency injection feel unnecessary right up until the first test. `NSApp.delegate as! AppDelegate` reaches any object from anywhere. `UserDefaults.standard`, `NSWorkspace.shared`, and `FileManager.default` are one autocomplete away in every file. A `Manager.shared` costs one line and works immediately.

Every one of those is a hidden edge in the dependency graph. The graph becomes unreadable, features cannot be instantiated without the whole app, tests execute in an order-dependent way against shared mutable state, and substituting an implementation means editing every call site.

Unlike a server process, a macOS app has an obvious, single, well-defined composition root — `applicationDidFinishLaunching(_:)` — so there is no structural excuse for ambient access.

**Context:**
- `AppDelegate` is the one object the system constructs; everything else can be constructed from it.
- Features must be instantiable in a test without `NSApplication`, a window, or TCC permissions.
- Most features need only their own service plus their own state; genuine cross-feature needs are the exception.
- Swift 6 `Sendable` checking constrains what may be captured and passed across isolation boundaries.

## Decision

**`AppDelegate` is the composition root. It builds one `AppEnvironment` holding the live `Core/` services, then constructs each feature by handing it the contracts it declared. Features declare cross-feature needs as a `Deps` struct of closures. No singletons for anything with I/O, and no `NSApp.delegate` reach-back — ever.**

## Rules

1. **Default to constructor parameters; add `Deps` only for genuine cross-feature needs.**
   A feature that needs a `Core/` contract takes it as a parameter. It does **not** get a `Deps` struct "for consistency." Reach for `Deps` only when the feature needs a capability **another feature owns**.

2. **`AppEnvironment` is the graph, built once, in the composition root.**

   ```swift
   // App/AppEnvironment.swift — the only place Live* services are constructed
   @MainActor
   struct AppEnvironment {
       let settings: any SettingsService
       let accessibility: any AccessibilityService
       let runtime: any RuntimeService

       static func live() -> AppEnvironment {
           AppEnvironment(
               settings: LiveSettingsService(defaults: .standard),
               accessibility: LiveAccessibilityService(),
               runtime: LiveRuntimeService()
           )
       }
   }
   ```

   ```swift
   // App/main.swift — the entry point (NOT `@main` on the delegate; see ADR-SWIFT-S01 rule 9)
   let application = NSApplication.shared
   let delegate = AppDelegate()
   application.delegate = delegate
   application.setActivationPolicy(.regular)
   application.run()
   ```

   ```swift
   // App/AppDelegate.swift — composes, does not implement
   @MainActor
   final class AppDelegate: NSObject, NSApplicationDelegate {
       private var console: ConsoleCoordinator?

       func applicationDidFinishLaunching(_ note: Notification) {
           let env = AppEnvironment.live()
           console = ConsoleFeature.make(
               runtime: env.runtime,
               deps: .init(evaluate: { [runtime = env.runtime] in try await runtime.eval($0) })
           )
           console?.showWindow()
       }
   }
   ```

3. **`Deps` is a `Sendable` struct of closures, declared inside the feature's public surface.**
   It is that feature's *consumption contract* — what it needs from elsewhere — so it lives next to the factory in `<Name>Feature.swift`, not in `Model/`. Closures rather than protocols keep the surface exactly as wide as the need: one function, one field.

   ```swift
   @MainActor
   struct ConsoleFeature {
       struct Deps: Sendable {
           var evaluate: @Sendable (String) async throws -> String   // owned by the runtime feature
           var report: @Sendable (RuntimeError) -> Void              // owned by diagnostics
       }
       static func make(runtime: any RuntimeService, deps: Deps) -> ConsoleCoordinator { … }
   }
   ```

   Note the error type is the **seam's** error (`RuntimeError`), not an app-wide one —
   ADR-SWIFT-S09 rule 2.

4. **Wire cross-feature closures at the composition root.**
   The composition root is the **only** place that knows about more than one feature. The consumer never imports the producer.

5. **Stub a missing capability as an inline no-op at the composition root.**
   When a capability does not exist yet, satisfy its slot with a typed no-op *where the wiring happens* — never a placeholder module, never a feature flag, never an optional dependency.

   ```swift
   report: { _ in }   // no-op — delete when the diagnostics feature ships
   ```

   The consumer and its tests depend on the signature, not the implementation, so nothing changes when the real one arrives.

6. **Test by constructing the feature with doubles.**
   No app, no window, no permissions. Doubles come from `Core/<Service>/Stub…` (ADR-SWIFT-S06 rule 5); cross-feature closures are supplied inline.

   ```swift
   @Test func evaluatesAndAppends() async throws {
       let feature = ConsoleFeature.make(
           runtime: StubRuntimeService(result: "42"),
           deps: .init(evaluate: { _ in "42" }, report: { _ in })
       )
       #expect(await feature.evaluate("6*7") == "42")
   }
   ```

7. **No singletons for anything with I/O, state, or permissions.**
   `static let shared` is acceptable only for immutable, side-effect-free values (a formatter cache, a constant table). Anything that reads, writes, prompts, or remembers goes through the environment.

8. **Never reach the delegate.**
   `NSApp.delegate as! AppDelegate` — and `NSApplication.shared.delegate` casts generally — are forbidden. If an object needs something the delegate holds, it should have been handed it at construction. This is the single most common way a Cocoa dependency graph becomes unreadable, and it is a hard rule, not a preference.

9. **Framework-imposed globals are wrapped, not embraced.**
   `UserDefaults.standard`, `NSWorkspace.shared`, `FileManager.default`, and `SMAppService` are reachable everywhere by design. Each is reached only from its `Live…` service (ADR-SWIFT-S06 rule 2), which the environment owns.

## DO / DON'T

**DO**
- Build the graph once, in `AppDelegate` → `AppEnvironment`
- Hand a feature the contracts it declared
- Declare `Deps` next to the factory, as `Sendable` closures
- Stub an unbuilt capability as an inline no-op at the root
- Construct features with doubles in tests
- Keep `static let shared` for immutable values only

**DON'T**
- Don't add an empty or pass-through `Deps`
- Don't construct a `Live…` service inside a feature
- Don't read `UserDefaults.standard` outside its service
- Don't cast `NSApp.delegate`
- Don't use a `Manager.shared` for anything with I/O
- Don't put `Deps` in the feature's `Model/`
- Don't add a DI container or a property-wrapper injection framework

## Alternatives considered

| Option | Verdict |
|---|---|
| `AppDelegate` composition root + `AppEnvironment` + per-feature `Deps` closures | **Chosen** — one obvious root, explicit graph, zero runtime machinery |
| Singletons / `Manager.shared` throughout | Rejected — the failure mode this ADR exists to prevent: invisible graph, order-dependent tests, no substitution |
| `NSApp.delegate` reach-back | Rejected — same as above, plus a forced cast on every use |
| A DI container (Swinject, Factory, or `@Injected` property wrappers) | Rejected — runtime resolution replaces a compile-time-checked function parameter with a registration that fails at launch; obscures the graph the ADR is trying to make visible |
| SwiftUI `@Environment` as the app-wide mechanism | Rejected as the primary mechanism — it is view-tree-scoped and does not reach AppKit coordinators, services, or tests. Fine *within* a SwiftUI subtree, seeded from the environment |
| Protocol per cross-feature need instead of closures | Rejected for `Deps` — a one-method protocol plus a conforming type is three declarations where a closure field is one. Protocols stay for `Core/` services (ADR-SWIFT-S06), which are multi-method contracts |

## Consequences

**Positive:** the entire dependency graph is readable in one file; any feature can be constructed in a test with doubles; swapping or stubbing an implementation is a one-line change at the root; no framework, no registration, no launch-time resolution failures; `Sendable` closures make cross-isolation capture explicit rather than accidental.

**Negative:** the composition root grows with the app and needs periodic grouping (per-feature `make…` helpers) to stay readable; adding a cross-feature need means touching two places (the `Deps` declaration and each wiring site); the "no delegate reach-back" rule has to be actively enforced in review because the language and frameworks make the violation trivially easy.

## Related

- **Dependency direction:** [ADR-SWIFT-S01](ADR-SWIFT-S01-repository-structure.md) — declares the rule this ADR implements.
- **Service contracts:** [ADR-SWIFT-S06](ADR-SWIFT-S06-pure-service-modules.md) — what gets injected.
- **Feature structure:** [ADR-SWIFT-S03](ADR-SWIFT-S03-feature-structure.md) — where `Deps` and the factory live.
- **Concurrency:** [ADR-SWIFT-S07](ADR-SWIFT-S07-concurrency-and-main-thread.md) — why `Deps` closures are `@Sendable`.
- **Conventions:** [`../conventions.md`](../conventions.md).
