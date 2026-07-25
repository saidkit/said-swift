# ADR-SWIFT-S04: Pure Service Modules (system frameworks behind contracts)

**Date:** 2026-07-25
**Status:** Accepted
**Class:** System (portable across Swift / macOS app projects)

## Problem

A macOS app's hardest-to-test code is not its own — it is Apple's. The Accessibility API prompts for consent and returns nothing until granted. `NSWorkspace` reflects whatever apps happen to be running. `SMAppService` mutates login-item state for the whole user account. `CGEvent` taps need a running run loop. `FSEvents` fires on its own queue. None of it can be exercised in a unit test, and all of it is process-global.

Called directly from a feature, each of these makes that feature untestable and non-deterministic. Worse, permission-gated APIs fail *silently and differently* depending on TCC state, so a bug reproduces on one machine and not another.

**Context:**
- Permission-gated frameworks (Accessibility, Automation, Screen Recording, Input Monitoring) return empty or throw depending on state the test cannot control.
- Process-global frameworks (login items, status bar, event taps) cannot be instantiated twice or reset between tests.
- Some services are genuinely external: an embedded scripting runtime, a network API, an update feed.
- Features must be testable without `NSApplication`, without a window, and without a TCC prompt.

## Decision

**Every system framework and external system is reached through a protocol defined in `Core/<Service>/`, with a live implementation and at least one test double. Features depend on the protocol, never on the framework.**

### Shape

```
Core/Accessibility/
├── AccessibilityService.swift        # the protocol — the contract
├── LiveAccessibilityService.swift    # the only file that imports ApplicationServices
└── StubAccessibilityService.swift    # deterministic double for tests + previews
```

```swift
// Core/Accessibility/AccessibilityService.swift
protocol AccessibilityService: Sendable {
    var isTrusted: Bool { get async }
    func requestTrust() async
    func focusedWindowFrame() async throws -> CGRect
}
```

The contract is expressed in the app's own vocabulary and its own types. It does **not** leak `AXUIElement`, `AXError`, `OSStatus`, `CFTypeRef`, or a vendor SDK type across the seam — if it does, the seam is decorative and swapping or faking the implementation is impossible.

### Rules

1. **One protocol per external system, in `Core/<Service>/`.**
   Named for what it does (`UpdateService`, `LoginItemService`), not for the framework it wraps (`SMAppServiceWrapper`).

2. **Exactly one file imports the framework.**
   `Live<Service>.swift` is the only place `import ApplicationServices` / `import ServiceManagement` / a vendor SDK appears. `grep -r "import ApplicationServices" --include=*.swift` returning more than one hit is a violation.

3. **The contract speaks the app's types.**
   Framework errors are translated into a typed `Error` at this boundary (ADR-SWIFT-S09). `OSStatus`/`AXError` never escape.

4. **Contracts are `Sendable`; implementations are `actor` or immutable.**
   Services cross actor boundaries by definition. Async methods where the underlying call can block, is I/O, or needs a permission round-trip — which is nearly always.

5. **Ship a double with every contract.**
   A `Stub…` (fixed answers) or `Mock…` (recorded calls) lives next to the protocol. Written at the same time as the contract, not when the first test is finally attempted.

6. **Permission state is part of the contract.**
   Any permission-gated service exposes its authorization state and a request path. Features render a pre-flight explanation and a recovery route from that state — they never infer permission from a failure (see the UX gate in `docs/qa/feature-ux-checklist.md`).

7. **Features receive the protocol; they never construct the implementation.**
   `Live…` is instantiated once, at the composition root — ADR-SWIFT-S05.

8. **A service is not a place for feature logic.**
   If it decides *what the app should do* rather than *how to talk to the outside*, it belongs in a feature's `Services/` (ADR-SWIFT-S03).

### What does and does not get a service module

**Does:** permission-gated frameworks (Accessibility, Automation, Screen Recording, Input Monitoring); process-global state (login items, status item, activation policy, event taps); the file system when watched or written outside a pure helper; network and update feeds; an embedded scripting/plugin runtime; crash reporting and telemetry; the clock and randomness when behaviour depends on them.

**Does not:** pure computation (formatting, parsing, geometry) — those are free functions or `struct`s in `Core/Support/`; `UserDefaults`, which gets a typed settings facade instead (ADR-SWIFT-S08); AppKit view classes, which are the UI layer, not an external system.

## Out of scope

- **Wiring and lifetime of the live instances** — ADR-SWIFT-S05.
- **Error type design** — ADR-SWIFT-S09.
- **Settings storage specifically** — ADR-SWIFT-S08.

## Alternatives considered

| Option | Verdict |
|---|---|
| Protocol + `Live`/`Stub` in `Core/<Service>/` | **Chosen** — testable, one import site, swappable |
| Direct framework calls in features | Rejected — feature untestable; TCC state leaks into unrelated tests; framework types spread |
| A thin wrapper that re-exports framework types | Rejected — a seam that passes `AXUIElement` through is not a seam |
| Singleton `Manager` per framework (`AXManager.shared`) | Rejected — hides the dependency graph, cannot be substituted, order-dependent tests |
| Closure-based dependencies instead of protocols (a struct of function values) | Viable, and used for small `Deps` sets (ADR-SWIFT-S05). Rejected as the default here — a multi-method system framework reads better as a named protocol with a documented contract |

## Consequences

**Positive:** features are testable without permissions, windows, or a run loop; framework churn is contained to one file per service; permission handling becomes explicit and reviewable instead of an implicit failure mode; test doubles double as SwiftUI preview fixtures.

**Negative:** an extra indirection for every framework touch, including trivial ones — the "does / does not" list exists to stop that from becoming ceremony; a contract that outgrows its framework (methods added for one caller) drifts toward being a feature service and needs periodic re-reading against rule 8.

## Related

- **Layout:** [ADR-SWIFT-S01](ADR-SWIFT-S01-repository-structure.md) — `Core/<Service>/` and the dependency direction.
- **Feature structure:** [ADR-SWIFT-S03](ADR-SWIFT-S03-feature-structure.md) — how a feature consumes a contract.
- **Dependency injection:** [ADR-SWIFT-S05](ADR-SWIFT-S05-dependency-injection.md) — where `Live…` is constructed.
- **Settings:** [ADR-SWIFT-S08](ADR-SWIFT-S08-settings-and-data-storage.md) — the typed facade over `UserDefaults`.
- **Errors:** [ADR-SWIFT-S09](ADR-SWIFT-S09-error-handling-and-logging.md) — translating framework errors at this boundary.
- **Conventions:** [`../conventions.md`](../conventions.md).
