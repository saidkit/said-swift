# ADR-SWIFT-S09: Error Handling, Logging & Diagnostics

**Date:** 2026-07-25
**Status:** Accepted
**Class:** System (portable across Swift / macOS app projects)

## Problem

A macOS app's failures arrive in incompatible currencies: Swift `throw`s, `NSError` with a domain and code, `OSStatus`/`AXError` integers, `errno`, `nil` returns that mean "denied" and `nil` returns that mean "not found", and C APIs that report failure by returning a boolean. Left untranslated, these spread through the codebase and every call site invents its own interpretation.

The second half of the problem is what to *do* with a failure. A user typing a bad path and a framework returning an unexpected status are both "errors" and require opposite responses — one is a normal outcome that belongs at the field, the other is a defect that belongs in a log. Treating them alike produces either alert fatigue or silent breakage.

And on a user's machine there is no debugger. Whatever the app recorded at the moment of failure is the entire diagnostic surface.

**Context:**
- Permission-gated frameworks fail *silently and differently* depending on TCC state (ADR-SWIFT-S06).
- Users of a background/menu-bar app never see `stdout`; `print` is invisible in the shipped product.
- Unified logging is queryable after the fact (`log show --predicate`) and privacy-aware by default.

## Decision

**Failures are typed at the seam where they enter, classified as expected or unexpected, and routed accordingly: expected failures are values surfaced in place; unexpected failures are logged with context and shown only if the user's next action depends on them. All logging is `os.Logger`.**

## Rules

1. **Every `Core/` service translates at its boundary.**
   `OSStatus`, `AXError`, `errno`, `NSError`, and vendor error types are converted into a typed Swift `Error` inside the `Live…` implementation (ADR-SWIFT-S06 rule 3). They do not escape into features.

2. **One error enum per seam, not one for the app.**
   `ConfigError`, `RuntimeError`, `UpdateError`. A single app-wide `AppError` with thirty cases forces every handler to switch over failures it cannot encounter. Compose with a wrapping case when a boundary genuinely forwards another's failure.

3. **Errors carry what a human needs to act.**
   The path, the key, the underlying code — as associated values, not interpolated into a string. String-only errors cannot be matched in tests or handled differently by case.

4. **Classify at the throw site: expected or unexpected.**
   - **Expected** — a normal outcome of valid use: file not found, invalid user input, permission not yet granted, network offline, user cancellation. Return it as a value or throw a case the caller explicitly handles. **Never** an alert on its own.
   - **Unexpected** — a defect or a violated invariant: a framework returning an undocumented status, a decode failure on data the app itself wrote. Log at `.error` with context; surface only if the user's next action depends on it.

5. **Alerts are for decisions, not for information.**
   `NSAlert` interrupts everything the user is doing. It is justified when the user must choose (overwrite / cancel) or when work stopped and they need to know why. A failure the app recovered from, a background retry, or a validation message is not an alert — those belong inline, in a status area, or in the log.

6. **Permission failures get a route, not a message.**
   A capability blocked by TCC shows what is needed, why, and a button that opens the relevant System Settings pane. "Accessibility permission denied" with an OK button is a dead end (see `docs/qa/feature-ux-checklist.md`).

7. **`os.Logger` per subsystem/category; never `print`.**

   ```swift
   // Core/Support/Log.swift
   enum Log {
       static let app = Logger(subsystem: bundleID, category: "app")
       static let runtime = Logger(subsystem: bundleID, category: "runtime")
   }
   ```

   Categories match the architecture (one per feature or service), so `log show --predicate 'category == "runtime"'` is a usable filter.

8. **Respect log privacy.**
   Unified logging redacts interpolated values by default. Mark non-sensitive values `.public` deliberately (`"\(path, privacy: .public)"`); never mark user content, tokens, or paths containing usernames public without thinking about it. The redaction default is a feature — do not blanket-disable it.

9. **Levels mean something.**
   `.debug` development only (not persisted) · `.info` notable, non-problem events · `.error` something failed and the user may notice · `.fault` an invariant is broken. Reserve `.error` and `.fault` for real conditions; a log where everything is an error is a log nobody reads.

10. **`fatalError` only for programmer errors, never for runtime conditions.**
    Unreachable switch cases and violated preconditions in the app's own code, yes. A missing file, a failed decode, a denied permission, or a malformed server response — never. Same for force-unwrap and `try!`: each is a `fatalError` in disguise, and each is forbidden on any value that comes from outside the binary.

11. **Crash reporting sits behind a contract and is opt-in.**
    A `CrashReporter` protocol (ADR-SWIFT-S06), with the vendor SDK confined to its `Live…` implementation. Reporting is user-consented, the consent is revocable, and a DSN/endpoint inherited from a template or upstream fork must never be shipped — it sends your users' crashes to someone else.

12. **A user-facing error message says what happened and what to do next.**
    No error codes as the primary text, no stack traces, no "an error occurred". The code goes in the log; the sentence goes to the user.

## The shape, end to end

```swift
// Core/Config/ConfigError.swift — typed at the seam, carries context
enum ConfigError: Error {
    case notFound(URL)                       // expected
    case unreadable(URL, underlying: Error)  // unexpected
}

// Features/Config/Services/ConfigLoader.swift — expected vs unexpected split
func load() async -> ConfigLoadResult {
    do { return .loaded(try await store.read()) }
    catch ConfigError.notFound {
        return .empty                        // expected: render the empty state, no alert
    } catch {
        Log.config.error("config read failed: \(error, privacy: .public)")
        return .failed                       // unexpected: logged; UI shows a recovery affordance
    }
}
```

## Out of scope

- **Which folder each piece lives in** — ADR-SWIFT-S01 / S03.
- **Where logs are persisted if the app writes its own** — ADR-SWIFT-S08 (Application Support).
- **The visual shape of error and empty states** — `docs/ux/` and the UX gate.

## Alternatives considered

| Option | Verdict |
|---|---|
| Typed errors per seam + expected/unexpected classification + `os.Logger` | **Chosen** — matches how the failures actually differ; queryable diagnostics on user machines |
| One app-wide error enum | Rejected — every handler switches over impossible cases; the enum becomes a dumping ground |
| `NSError` throughout | Rejected — stringly-typed domains and codes; no exhaustiveness; nothing the compiler can check |
| `Result` return types everywhere instead of `throws` | Rejected as the default — `throws` composes with `async` and structured concurrency. `Result`-shaped returns stay for the expected-outcome case (as above) |
| `print` / `NSLog` | Rejected — invisible in a shipped background app; no levels, no categories, no privacy handling, no post-hoc query |
| Alert on every failure | Rejected — alert fatigue trains users to dismiss without reading, including the alerts that mattered |
| Always-on crash reporting without consent | Rejected — a privacy decision that is not the developer's to make silently |

## Consequences

**Positive:** a failure's category is visible in its type; users see interruptions only when a decision is theirs to make; permission failures become recoverable instead of dead ends; a support request can be answered from `log show` output rather than a reproduction attempt.

**Negative:** per-seam error enums mean more types and occasional wrapping cases; the expected/unexpected classification is a judgment call that needs review to stay consistent; log privacy annotations are easy to forget, and forgetting them in the safe direction (redacted) makes diagnosis harder while forgetting in the unsafe direction leaks user data.

## Related

- **Service seam:** [ADR-SWIFT-S06](ADR-SWIFT-S06-pure-service-modules.md) — where framework errors are translated.
- **Feature structure:** [ADR-SWIFT-S03](ADR-SWIFT-S03-feature-structure.md) — which layer handles versus surfaces a failure.
- **Concurrency:** [ADR-SWIFT-S07](ADR-SWIFT-S07-concurrency-and-main-thread.md) — cancellation is not an error.
- **UX gate:** [`../qa/feature-ux-checklist.md`](../qa/feature-ux-checklist.md) — error, empty, and permission-state rules.
- **Conventions:** [`../conventions.md`](../conventions.md).
