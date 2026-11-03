# ADR-SWIFT-S07: Concurrency and the Main-Thread Boundary

**Date:** 2026-07-25
**Status:** Accepted
**Class:** System (portable across Swift / macOS app projects)

## Problem

A macOS app has one thread that must never block and a great many callbacks that arrive on threads nobody chose. AppKit is main-thread-only. Meanwhile `FSEvents` delivers on its own queue, `CGEvent` taps run on the run loop they were installed on, `NSWorkspace` notifications arrive wherever the poster was, `DispatchSource` fires on whatever queue it was given, and a C library callback arrives on whichever thread the library felt like using.

Get this wrong in one direction and the app beachballs; get it wrong in the other and AppKit corrupts state or crashes with an assertion the user will never report usefully. Historically both were runtime failures found by users.

Swift 6 changes the economics: with strict concurrency, most of this class of bug becomes a compile error — but only if the code is organized so the compiler can see the boundary.

**Context:**
- `SWIFT_STRICT_CONCURRENCY = complete` (ADR-SWIFT-S02) — data-race safety is checked, not advised.
- AppKit types are `@MainActor`-isolated by declaration.
- A system-level app is *made of* callbacks from C and Objective-C APIs that predate structured concurrency and carry no isolation information.
- The app must stay responsive while doing file, network, and scripting work.

## Decision

**`@MainActor` is the default for UI and the app's coordination layer. Everything else is explicitly isolated: `actor` for mutable shared state, `Sendable` value types for what crosses. Every callback from a legacy API hops to a known isolation as its first statement.**

## Rules

1. **UI is `@MainActor`; the annotation goes on the type.**
   Views, view controllers, coordinators, and `@Observable` state (ADR-SWIFT-S03) are `@MainActor`. Annotate the type, not individual methods — per-method annotations produce a type that is half-isolated and reads as if the split were meaningful.

2. **Shared mutable state that outlives a view is an `actor`.**
   Caches, in-flight registries, watchers with subscriber lists. Not a class with a lock; not a class with a serial queue. `actor` is the mechanism the compiler understands.

3. **What crosses an isolation boundary is `Sendable`.**
   Value types (`struct`/`enum` of `Sendable` members) cross freely. A reference type crossing is a design smell — it is usually state that should have stayed on one side, or a model that should have been a value type.

4. **`@unchecked Sendable` requires a written justification.**
   One comment line stating what actually guarantees safety (immutable after init; protected by an internal lock; only ever touched from one queue). No justification, no `@unchecked`.

5. **Every legacy callback hops explicitly, on its first line.**
   A C or Objective-C callback carries no isolation information. Do not assume, and do not annotate your way out of it:

   ```swift
   // FSEvents / CGEvent tap / NSWorkspace notification — unknown thread
   let handler: @Sendable (FileEvent) -> Void = { event in
       Task { @MainActor in state.apply(event) }   // first statement, always
   }
   ```

   The alternative — marking the callback `@MainActor` and hoping — is a crash waiting for the day the framework changes which thread it uses.

6. **`DispatchQueue.main.sync` is forbidden.**
   From the main thread it deadlocks immediately; from a background thread it is a deadlock waiting for the reverse dependency to appear. There is no case where it is the right answer. Use `await MainActor.run { }` or `Task { @MainActor in }`.

7. **Blocking work never runs on the main actor.**
   File I/O, network, `Process` invocation, scripting evaluation, and large parsing run in an `actor` or a detached task and return a `Sendable` result. "It is only a few milliseconds" is measured on a warm SSD and an unloaded machine; the user's is neither.

8. **Long-running work is cancellable and checks for it.**
   Anything triggered by user action that can outlive the interaction holds its `Task` and cancels it on window close, view disappearance, or re-trigger. Loops call `try Task.checkCancellation()`. A task nobody can cancel is a leak with a UI attached.

9. **Timers, observers, and taps are owned and torn down.**
   `NotificationCenter` observers, `NSEvent` monitors, `DispatchSourceTimer`s, and event taps are stored and removed in `deinit` or an explicit `stop()`. Capture `self` weakly, or capture the specific values needed instead of `self`.

10. **GCD only where a C API demands a `dispatch_queue_t`.**
    Some framework APIs take a queue parameter. Pass one, then hop into structured concurrency in the callback body (rule 5). Do not build new architecture on `DispatchQueue`.

11. **`nonisolated` is a deliberate claim, not a way to silence a warning.**
    Marking a method `nonisolated` asserts that it touches no isolated state. If the compiler complained and `nonisolated` made it stop, the fix was probably wrong — re-read what the method actually touches.

## Default actor isolation (Swift 6.2+)

An app target may set `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, which makes every unannotated declaration main-actor-isolated. For an **app** this is the better default — most app code is main-actor anyway, so you annotate the handful of exceptions instead of annotating nearly every type. Do not set it on a framework or library target; libraries should stay non-isolated.

It inverts the *annotation direction*, not the architecture:

| | Default isolation `nonisolated` | Default isolation `MainActor` |
|---|---|---|
| UI, state, coordinators | annotate `@MainActor` | nothing to write |
| `Services/`, `Core/` logic | nothing to write | annotate `nonisolated` |

Protocols are isolated by this setting too: an unannotated `protocol` becomes main-actor,
forcing every conformance onto the main actor. A `Core/` contract must be `nonisolated` on the
protocol *and* its requirements, or the service seam silently collapses onto the main thread.

**Write both annotations explicitly regardless of the mode.** `@MainActor` on UI types and `nonisolated` on service types is correct under either setting, so the code's isolation does not silently change with a build flag. Relying on the absence of an annotation is what makes a project unable to change this setting later.

## The bridging pattern

The recurring shape in a system-level app: a `Core/` service (ADR-SWIFT-S06) wraps a callback-based framework, converts it into an `AsyncStream`, and the feature consumes it on the main actor. The unknown-thread callback is contained in one file; the feature sees a typed, cancellable, main-actor stream.

**This starter ships no compiled example — treat the shape below as unverified until your own code builds it.** When the pattern was first genuinely compiled in a consuming project it produced three errors that a written example had concealed:

1. **The observer token is not `Sendable`** and cannot cross into the `@Sendable` `onTermination` closure — it needs an explicit box with a justification (rule 4).
2. **The service is main-actor-isolated by default** under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, silently negating the bridge, until `nonisolated` is written on it (rule 11, ADR-SWIFT-S03 rule 3).
3. **`Task.cancel()` is nonisolated**, which is precisely why it can be called from `deinit` on a `@MainActor` consumer.

The shape: a `nonisolated` service in `Core/<Service>/Live*.swift` returning `AsyncStream` with the framework's teardown wired to `continuation.onTermination`; a `@MainActor` consumer owning the `Task` and cancelling it in `deinit`; a `Stub*` that yields a scripted sequence then calls `finish()`, so a consuming `for await` terminates rather than hanging a test.

Teardown belongs to the stream: cancelling the consuming task removes the observer, leaving no second lifetime to track (rule 9).

## Out of scope

- **Which folder each side of the boundary lives in** — ADR-SWIFT-S03.
- **How framework errors are typed and surfaced** — ADR-SWIFT-S09.

## Alternatives considered

| Option | Verdict |
|---|---|
| `@MainActor` UI + actors + explicit hops, strict concurrency complete | **Chosen** — the boundary is compiler-checked |
| `SWIFT_STRICT_CONCURRENCY = minimal` and manual discipline | Rejected — returns this entire class of bug to runtime, where it is found by users |
| GCD queues with `dispatch_assert_queue` | Rejected — assertions are runtime checks in debug builds; the compiler already knows |
| Locks (`NSLock` / `os_unfair_lock`) around shared state | Rejected as the default — an `actor` expresses the same guarantee in the type system. Locks remain valid inside a `Live…` service wrapping a lock-based C API |
| `@MainActor` on everything | Rejected — makes the app single-threaded by annotation; the beachball this ADR exists to prevent |
| `@preconcurrency import` to silence framework warnings | Acceptable as a temporary, commented measure on a specific import. Rejected as a strategy |

## Consequences

**Positive:** data races and main-thread violations become build failures; the responsive/blocking boundary is visible in the type signature; legacy callbacks are contained at one hop site per service; cancellation is structural rather than a flag someone remembers to check.

**Negative:** strict concurrency imposes real cost when wrapping older frameworks — `Sendable` conformances, `@unchecked` justifications, and occasional `@preconcurrency` imports; `AsyncStream` bridging is more code than a raw callback; developers new to actor isolation will hit a period where the compiler rejects code that "obviously works."

## Related

- **Stack:** [ADR-SWIFT-S02](ADR-SWIFT-S02-app-stack.md) — where strict concurrency is turned on.
- **Feature structure:** [ADR-SWIFT-S03](ADR-SWIFT-S03-feature-structure.md) — the folder split that mirrors this boundary.
- **Service modules:** [ADR-SWIFT-S06](ADR-SWIFT-S06-pure-service-modules.md) — where legacy callbacks are contained.
- **Dependency injection:** [ADR-SWIFT-S05](ADR-SWIFT-S05-dependency-injection.md) — why `Deps` closures are `@Sendable`.
- **Conventions:** [`../conventions.md`](../conventions.md).
