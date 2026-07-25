# Swift / macOS Code Conventions — said-swift

How to write code in this project. **Patterns + copyable examples** — verify against the actual files before acting; this doc describes intent, not current state.

## Core Philosophy

- **KISS** — simple solutions over complex ones.
- **YAGNI** — build only what's needed now.
- **MVP First** — working version, then iterate.
- **Compile-time safety** — let the type system and strict concurrency catch it; a runtime check is the fallback, not the plan.
- **Main thread is sacred** — anything that can block, doesn't run on it.

## Stack

| Concern | Choice |
|---|---|
| Language | Swift 6, `SWIFT_STRICT_CONCURRENCY = complete` |
| App shell | AppKit — `NSApplication`, windows, `NSStatusItem`, menus |
| View content | SwiftUI, hosted via `NSHostingView` / `NSHostingController` |
| State | `@Observable` (`@MainActor`), value types across boundaries — **requires macOS 14+**; see the deployment-target note below |
| Concurrency | `async/await`, `Task`, `actor`, `@MainActor` — GCD only where a C API demands a queue |
| Persistence | `UserDefaults` behind a typed facade + files (ADR-SWIFT-S08) |
| Logging | `os.Logger` — never `print` |
| Tests | Swift Testing (`import Testing`); XCTest for UI tests |
| Lint / format | SwiftLint `--strict` + `swift-format` |
| Build settings | `.xcconfig` only — never the target editor |
| Commands | `make` facade → `scripts/` + `xcodebuild` (see **Quality gates**) |

Full rationale: [ADR-SWIFT-S02](adr/ADR-SWIFT-S02-app-stack.md).

> **Deployment target — decide before the first feature.** Every `@Observable` example below
> assumes **macOS 14+** (Observation's floor). If the project must support macOS 13, replace
> `@Observable` with explicit change callbacks throughout — retrofitting the observation
> mechanism across a built UI is expensive, so settle `MACOSX_DEPLOYMENT_TARGET` in
> `Project-Base.xcconfig` first (`stencils/` carries a starting file). Record the choice as a
> project ADR; the examples here take the 14+ path because it is the recommendation, not
> because it is decided for you.

---

## Project structure

```
<Product>/
├── App/                 # AppDelegate + AppEnvironment — the composition root
├── Features/<Name>/     # feature modules (ADR-SWIFT-S03)
├── Core/                # <Service>/ seams, Extensions/, Support/
├── UI/                  # shared cross-feature views + design tokens
├── Resources/           # Assets.xcassets, xibs, .strings
├── Supporting/          # Info.plist, entitlements, bridging header
└── Build Configs/       # *.xcconfig — ALL build settings
```

Canonical structure: [ADR-SWIFT-S01](adr/ADR-SWIFT-S01-repository-structure.md). Feature anatomy: [ADR-SWIFT-S03](adr/ADR-SWIFT-S03-feature-structure.md).

### Feature anatomy

```
Features/<Name>/
├── <Name>Feature.swift       # public surface: factory + Deps
├── <Name>Coordinator.swift   # @MainActor — owns this feature's windows/menus
├── Views/                    # @MainActor — renders, does not decide
├── State/                    # @MainActor @Observable — read model, no I/O
├── Services/                 # explicitly `nonisolated` — the logic, the tested layer
└── Model/                    # Sendable value types
```

Only `<Name>Feature.swift` and `Views/` are expected in every feature. Add the rest when the feature earns them — an empty `State/` "for consistency" is noise.

### File granularity

> Files map to sources of truth, not to concerns. Co-locate derivatives with their source; split only when sources are independent.

A new file is justified when **all** hold: (1) it's an **independent source of truth**; (2) it's expected to **multiply** (N+1 of the same kind); (3) it's **not** a sub-20-line single declaration wrapping another file's contract.

- NOT: a `ConsoleLine.defaultStyle` static → bottom of `ConsoleLine.swift`, not `ConsoleStyles.swift`.
- NOT: a `displayName` computed property on an enum → next to the enum, not `Formatting.swift`.
- YES: a second service conforming to the same protocol → its own file.

One primary type per file, named for it: `ConsoleState.swift` declares `ConsoleState`.

### File naming

| Type | Convention | Example |
|---|---|---|
| Type declaration | `<TypeName>.swift` | `ConsoleState.swift` |
| Protocol + impls | `<Name>Service.swift`, `Live<Name>Service.swift`, `Stub<Name>Service.swift` | `SettingsService.swift` |
| Extension | `<Type>+<Feature>.swift` | `NSWindow+Positioning.swift` |
| Feature surface | `<Name>Feature.swift` | `ConsoleFeature.swift` |
| Tests | `<TypeName>Tests.swift`, mirroring the source path | `ConsoleFormatterTests.swift` |

Types `PascalCase`; members and cases `camelCase`; acronyms follow the surrounding case (`urlString`, `URLLoader`) — matching the standard library, not `URLString`.

### Cross-feature rules

**Allowed:** another feature's `Model/` value types · `Core/*` · `UI/*` · a `Deps` closure wired at the composition root.
**Forbidden:** another feature's `Views/`, `State/`, `Services/`, or coordinator · constructing a `Live…` service inside a feature · `NSApp.delegate as!` (ADR-SWIFT-S05 rule 8).

Swift's single-module compilation will not enforce this. Review does.

---

## The `@MainActor` boundary

**UI is main-actor; logic is not.** Annotate the type, not individual methods.

```swift
// Features/Console/State/ConsoleState.swift — main actor, no I/O
@MainActor @Observable
final class ConsoleState {
    private(set) var lines: [ConsoleLine] = []
    var filter: String = ""
    func append(_ line: ConsoleLine) { lines.append(line) }
}

// Features/Console/Services/ConsoleFormatter.swift — not main actor, pure, tested
nonisolated struct ConsoleFormatter: Sendable {
    func format(_ event: RuntimeEvent) -> ConsoleLine { … }
}
```

- **Write `@MainActor` and `nonisolated` explicitly**, both of them. An app target may set
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, under which an unannotated type is main-actor —
  relying on the *absence* of an annotation silently drags services onto the main thread.
- **Views render; they don't decide.** A view reads state, calls closures it was handed, and returns. No file I/O, no framework calls, no business rules.
- **Blocking work never runs on the main actor** — file I/O, network, `Process`, scripting evaluation, large parses.
- **What crosses is `Sendable`** — value types. A reference type crossing usually means state that should have stayed on one side.
- **`@unchecked Sendable` carries a one-line justification** or it doesn't ship.

Full rules: [ADR-SWIFT-S07](adr/ADR-SWIFT-S07-concurrency-and-main-thread.md).

### Legacy callbacks hop on their first line

A C or Objective-C callback carries no isolation information — never assume, never annotate your way out of it:

```swift
// ✗ Wrong: assumes the framework's delivery thread and will be right until it isn't.
@MainActor func handle(_ event: FileEvent) { state.apply(event) }

// ✓ Right: hop explicitly, first statement.
let handler: @Sendable (FileEvent) -> Void = { event in
    Task { @MainActor in state.apply(event) }
}
```

**`DispatchQueue.main.sync` is forbidden** — deadlocks from the main thread, and is a latent deadlock from anywhere else. Use `await MainActor.run { }`.

### Bridging a callback API into a stream

The recurring shape: a `Core/` service converts a callback framework into an `AsyncStream`; the feature consumes it on the main actor.

```swift
actor LiveFileWatcher: FileWatcher {
    func events(for url: URL) -> AsyncStream<FileEvent> {
        AsyncStream { continuation in
            let stream = /* FSEventStreamCreate — callback yields into continuation */
            continuation.onTermination = { _ in /* stop + release */ }
        }
    }
}

@MainActor
final class ConfigCoordinator {
    private var watchTask: Task<Void, Never>?

    func start(watcher: some FileWatcher, url: URL) {
        watchTask = Task { [weak self] in
            for await event in await watcher.events(for: url) {
                self?.state.apply(event)
            }
        }
    }

    deinit { watchTask?.cancel() }
}
```

**Anything you start, you own and cancel.** Tasks, `NotificationCenter` observers, `NSEvent` monitors, timers, event taps — stored, and torn down in `deinit` or an explicit `stop()`.

---

## Service modules (system frameworks behind contracts)

See [ADR-SWIFT-S04](adr/ADR-SWIFT-S04-pure-service-modules.md). Short version:

> Every system framework and external system is reached through a protocol in `Core/<Service>/`, with a live implementation and a test double. **Exactly one file imports the framework.**

```swift
// Core/Accessibility/AccessibilityService.swift — the contract, in the app's own types
protocol AccessibilityService: Sendable {
    var isTrusted: Bool { get async }
    func requestTrust() async
    func focusedWindowFrame() async throws -> CGRect
}

// Core/Accessibility/LiveAccessibilityService.swift — the ONLY file importing the framework
import ApplicationServices

actor LiveAccessibilityService: AccessibilityService { … }

// Core/Accessibility/StubAccessibilityService.swift — written with the contract, not later
struct StubAccessibilityService: AccessibilityService {
    var trusted = true
    var isTrusted: Bool { get async { trusted } }
    func requestTrust() async {}
    func focusedWindowFrame() async throws -> CGRect { .zero }
}
```

- The contract speaks the app's vocabulary. **`AXUIElement`, `OSStatus`, `CFTypeRef`, and vendor SDK types never cross it** — translate at the boundary (ADR-SWIFT-S09 rule 1).
- Permission state is part of the contract: expose authorization and a request path; never infer permission from a failure.
- `grep -r "import ApplicationServices" --include=*.swift` returning more than one hit is a violation.

**Gets a service module:** permission-gated frameworks, process-global state (login items, status item, event taps), watched/written file system, network, update feeds, scripting runtimes, crash reporting, clock/randomness when behaviour depends on them.
**Doesn't:** pure computation (`Core/Support/`), `UserDefaults` (typed settings facade), AppKit view classes.

---

## Dependency injection

`AppDelegate` builds the graph; features receive what they declared. See [ADR-SWIFT-S05](adr/ADR-SWIFT-S05-dependency-injection.md).

```swift
// App/AppEnvironment.swift — the only place Live* services are constructed
@MainActor
struct AppEnvironment {
    let settings: any SettingsService
    let accessibility: any AccessibilityService

    static func live() -> AppEnvironment {
        AppEnvironment(
            settings: LiveSettingsService(defaults: .standard),
            accessibility: LiveAccessibilityService()
        )
    }
}

// Features/Console/ConsoleFeature.swift — Deps declared next to the factory
@MainActor
struct ConsoleFeature {
    struct Deps: Sendable {
        var evaluate: @Sendable (String) async throws -> String   // owned by the runtime feature
        var report: @Sendable (RuntimeError) -> Void              // seam's error type, not an app-wide one
    }
    static func make(accessibility: any AccessibilityService, deps: Deps) -> ConsoleCoordinator { … }
}

// App/AppDelegate.swift — composes, does not implement
func applicationDidFinishLaunching(_ note: Notification) {
    let env = AppEnvironment.live()
    console = ConsoleFeature.make(
        accessibility: env.accessibility,
        deps: .init(
            evaluate: { [runtime = env.runtime] in try await runtime.eval($0) },
            report: { _ in }        // no-op stub — delete when diagnostics ships
        )
    )
}
```

- **Only add `Deps` for genuine cross-feature needs.** A feature taking only its own service takes it as a parameter — no `Deps` "for consistency."
- **Stub an unbuilt capability inline at the composition root** — never a placeholder module, never a feature flag.
- **`static let shared` is for immutable values only.** Anything that reads, writes, prompts, or remembers goes through the environment.

---

## Settings

`UserDefaults` is reached through one typed facade; keys and defaults are defined once.

```swift
// Core/Settings/SettingsService.swift
protocol SettingsService: Sendable {
    var configDirectory: URL { get }
    var showsDockIcon: Bool { get set }
}

// Core/Settings/LiveSettingsService.swift — the only file touching UserDefaults
enum SettingsKey {
    static let configDirectory = "app.config.directory"   // namespaced (ADR-SWIFT-S08 rule 4)
    static let showsDockIcon   = "app.ui.showsDockIcon"
}
```

- **Register defaults once** at launch (`register(defaults:)`) — a `?? false` at each read site defines the default N times and they will diverge.
- **Namespace the app's own keys.** Relevant whenever another mechanism (a scripting API, say) can write into the same domain.
- Never tell a user to hand-edit a preference plist — `cfprefsd` caches it. Documentation says `defaults write`.

Storage layout: [ADR-SWIFT-S08](adr/ADR-SWIFT-S08-settings-and-data-storage.md).

---

## Errors and logging

```swift
// Core/Config/ConfigError.swift — typed per seam, carries context as associated values
enum ConfigError: Error {
    case notFound(URL)                       // expected
    case unreadable(URL, underlying: Error)  // unexpected
}

// Core/Support/Log.swift — one category per feature/service
enum Log {
    static let app     = Logger(subsystem: bundleID, category: "app")
    static let config  = Logger(subsystem: bundleID, category: "config")
}
```

**Classify at the throw site:**

- **Expected** — file not found, invalid input, permission not yet granted, offline, cancellation. Return as a value or throw a case the caller handles. Never an alert on its own.
- **Unexpected** — a violated invariant, an undocumented framework status. Log at `.error` with context; surface only if the user's next action depends on it.

```swift
do { return .loaded(try await store.read()) }
catch ConfigError.notFound { return .empty }          // expected → empty state
catch {
    Log.config.error("config read failed: \(error, privacy: .public)")
    return .failed                                    // unexpected → logged + recovery affordance
}
```

- **`NSAlert` is for decisions, not information.** Validation, recovered failures, and background retries do not interrupt.
- **Permission failures get a route** — what's needed, why, and a button to the right System Settings pane. Not an OK button.
- **Log privacy defaults to redacted.** Mark values `.public` deliberately; never blanket-disable.
- **`fatalError` / `try!` / force-unwrap are for programmer errors only** — never for anything originating outside the binary.

Full contract: [ADR-SWIFT-S09](adr/ADR-SWIFT-S09-error-handling-and-logging.md).

---

## AppKit ↔ SwiftUI

AppKit owns the shell; SwiftUI renders content.

```swift
@MainActor
final class SettingsWindowController: NSWindowController {
    convenience init(state: SettingsState) {
        let host = NSHostingController(rootView: SettingsPane(state: state))
        let window = NSWindow(contentViewController: host)
        window.title = String(localized: "Settings")
        window.setFrameAutosaveName("SettingsWindow")   // state restoration
        self.init(window: window)
    }
}
```

- **AppKit** for anything touching `NSApplication`, windows, the menu bar, the event stream, activation policy, or the dock.
- **SwiftUI** for rectangles of content.
- State crosses the seam as an `@Observable` object owned by the AppKit side; SwiftUI observes it.
- No logic in `.xib` beyond outlets and actions. Prefer programmatic construction.

---

## Imports

**One lexicographically sorted block. No grouping, no group comments.** This is not a
preference — `swift-format`'s `OrderedImports` rule enforces it, and it will reflow a grouped
list into a single sorted block, stranding any group comments in meaningless positions.
`make format-check` (R-GATE-FORMAT) fails on anything else.

```swift
import AppKit
import Foundation
import OSLog
import Sparkle
```

`@testable` imports form their own block after the regular ones — `swift-format` handles the
separation.

Swift has no path aliases, and a single-module app has no import statements between its own
folders — the dependency direction is enforced by discipline, not the compiler (ADR-SWIFT-S01).
Keep imports minimal: an `import AppKit` in a `Services/` file is a signal that logic and UI
have merged, and an `import` of a system framework anywhere but its `Live…` service violates
ADR-SWIFT-S04 rule 2.

---

## Named constants over literals

Numeric or string knobs that recur live as named constants, not inline literals — recurring literals are under-noticed sites of drift.

**Rule:** if a literal appears at more than one call site **and** means *the same idea* at each, name it. Litmus: *if the value changed, would I update more than one file?* Yes → extract; no → leave inline.

- YES: `defaultsSuiteName`, a `UserDefaults` key, a bundle identifier, a notification name.
- YES: a window's minimum size used by both the controller and its restoration path.
- NOT: a one-off `0.2` animation duration in a single view.

Applies equally to magic strings — defaults keys, notification names, URL schemes, log categories.

---

## Forbidden practices

- **No build settings in `project.pbxproj`** — xcconfig only (ADR-SWIFT-S06).
- **No `DispatchQueue.main.sync`** — ever.
- **No `NSApp.delegate as!`** — the dependency should have been injected.
- **No singletons with I/O, state, or permissions** — `static let shared` is for immutable values.
- **No `UserDefaults.standard` outside its service** — same for `NSWorkspace.shared`, `FileManager.default`.
- **No framework imports outside the owning `Live…` service.**
- **No force-unwrap / `try!` / `fatalError` on external input** — only on the app's own violated invariants.
- **No `print` / `NSLog`** — `os.Logger`.
- **No blocking work on the main actor.**
- **No `@unchecked Sendable` without a written justification.**
- **No logic in `AppDelegate`** — it composes and hands off.
- **No logic in `.xib`.**
- **No user-facing string that isn't `String(localized:)`.**
- **No commits without explicit user request.**

---

## Testing

Swift Testing (`import Testing`) for new tests, mirroring the source tree under `<Product>Tests/`. Test the layer that has no UI: feature `Services/`, `Core/` logic, and contract translation.

```swift
import Testing

@Test func formatsRuntimeErrorsAsErrorLines() {
    let line = ConsoleFormatter().format(.error("boom"))
    #expect(line.kind == .error)
}

@Test func evaluatesThroughInjectedDeps() async throws {
    let feature = ConsoleFeature.make(
        accessibility: StubAccessibilityService(),
        deps: .init(evaluate: { _ in "42" }, report: { _ in })
    )
    #expect(try await feature.evaluate("6*7") == "42")
}
```

- **No test needs `NSApplication`, a window, or a TCC prompt.** If one does, a dependency wasn't injected (ADR-SWIFT-S05) or a framework wasn't wrapped (ADR-SWIFT-S04).
- Prefer testing pure functions and contract translation over rendering.
- Doubles come from `Core/<Service>/Stub…`, written alongside the contract.

---

## Quality gates

Before marking a task complete, pass the `applies-to: any` gates in [`qa/feature-qa-checklist.md`](qa/feature-qa-checklist.md):

```bash
make pre-commit    # FAST (seconds) — format-check + lint; the git pre-commit hook
make ci            # FULL (minutes) — + build + test; the git pre-push hook ← task close
```

`make install-hooks` wires both hooks. Gates are tiered by cost because in Swift the build
*is* the typecheck and costs minutes — a hook that builds gets bypassed, and a bypassed gate
is worse than none ([ADR-SWIFT-S10](adr/ADR-SWIFT-S10-quality-gates.md)).

`make` is the command facade (→ `scripts/` + `xcodebuild`); never inline an `xcodebuild` invocation in documentation. Concrete commands live in the `Makefile`; rule definitions live in the QA checklist.

UI-touching tasks additionally run the UX gate — [`qa/feature-ux-checklist.md`](qa/feature-ux-checklist.md), via `/said:review-ux`.

---

## References

- [`adr/ADR-SWIFT-S01-repository-structure.md`](adr/ADR-SWIFT-S01-repository-structure.md) — repo layout, dependency direction
- [`adr/ADR-SWIFT-S02-app-stack.md`](adr/ADR-SWIFT-S02-app-stack.md) — Swift 6, AppKit+SwiftUI, dependency policy
- [`adr/ADR-SWIFT-S03-feature-structure.md`](adr/ADR-SWIFT-S03-feature-structure.md) — feature anatomy
- [`adr/ADR-SWIFT-S04-pure-service-modules.md`](adr/ADR-SWIFT-S04-pure-service-modules.md) — the framework seam
- [`adr/ADR-SWIFT-S05-dependency-injection.md`](adr/ADR-SWIFT-S05-dependency-injection.md) — `AppEnvironment`, `Deps`
- [`adr/ADR-SWIFT-S06-build-signing-distribution.md`](adr/ADR-SWIFT-S06-build-signing-distribution.md) — xcconfig, `make`, notarization
- [`adr/ADR-SWIFT-S07-concurrency-and-main-thread.md`](adr/ADR-SWIFT-S07-concurrency-and-main-thread.md) — isolation rules
- [`adr/ADR-SWIFT-S08-settings-and-data-storage.md`](adr/ADR-SWIFT-S08-settings-and-data-storage.md) — the three stores
- [`adr/ADR-SWIFT-S09-error-handling-and-logging.md`](adr/ADR-SWIFT-S09-error-handling-and-logging.md) — errors, logging, alerts
- [`vision.md`](vision.md) — architecture overview
