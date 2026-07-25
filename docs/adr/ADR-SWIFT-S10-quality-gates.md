# ADR-SWIFT-S10: Quality Gates — Tiering by Feedback Cost

**Date:** 2026-07-25
**Status:** Accepted
**Class:** System (portable across Swift / macOS app projects)

> This ADR decides **when** each gate runs and **why** the tiers are shaped this way. The `verify:` command for each rule lives in [`../qa/feature-qa-checklist.md`](../qa/feature-qa-checklist.md); the executable command lives in the `Makefile`. Three layers, one owner each: **ADR = why and when · checklist = what · Makefile = how.**

## Problem

The obvious policy — "run every gate everywhere" — fails on Swift specifically, and it fails in a way that is worse than having no gates at all.

**Swift has no cheap typecheck.** In a TypeScript project `tsc --noEmit` is seconds, so a pre-commit hook can afford real verification. In Swift the **build *is* the typecheck**, and it costs minutes. A pre-commit hook that builds makes every commit a coffee break. The predictable result is `git commit --no-verify`, first occasionally and then by habit — and a bypassed gate is worse than an absent one, because the project still *believes* it is protected. The green checkmark in the README is now a lie, and nobody knows which commits were actually checked.

The opposite error is equally real: pushing everything to CI alone means a formatting nit costs a full remote round-trip to discover.

There is a second, subtler failure. A project typically runs **two** tools over the same source — a formatter that rewrites and a linter that reports. If their rules overlap and disagree, they produce an **unfixable loop**: `make format` writes X, `make lint` demands Y, fixing Y and reformatting restores X. Nobody can make both pass. The person who hits this does not file a bug; they disable the gate.

**Context:**
- The build is the only typecheck, and it is the expensive step (ADR-SWIFT-S02).
- Signing, notarization, and hardening checks require a *built, signed artifact* — they cannot run in the inner loop at all.
- Gates must be runnable by an agent at task close, so each needs a stable verb and an honest exit code.
- Some valuable tools (dead-code, secret scanning) are optional installs; a gate that silently no-ops when its tool is absent is indistinguishable from a passing gate.

## Decision

**Gates are tiered by cost, and each tier is bound to the moment its cost is acceptable. `make pre-commit` is seconds and runs on commit; `make ci` is minutes and runs on push; `make validate` acts on a built bundle and runs at release. Both git hooks are wired, so the fast tier never becomes the only tier.**

### The ladder

| Tier | Trigger | Budget | Contains | Gates |
|---|---|---|---|---|
| **Editor** | on save | instant | `make format` | *(no gate — this is what makes the next tier a non-event)* |
| **`make pre-commit`** | git `pre-commit` hook | seconds | format-check, lint | `R-GATE-FORMAT`, `R-GATE-LINT` |
| **`make ci`** | git `pre-push` hook + CI | minutes | + build, test | `R-GATE-BUILD`, `R-GATE-TEST` |
| **`make validate`** | release | needs a signed bundle | signature, Gatekeeper, staple, entitlements, hardening | `R-GATE-SIGN`, `R-GATE-HARDENING` |
| **`make scan`** | opt-in | varies | secrets, dead code | `R-GATE-SECRETS`, `R-GATE-DEADCODE` |

`make install-hooks` points `core.hooksPath` at `scripts/hooks/`. Wiring **both** hooks is the load-bearing part: without the `pre-push` hook, moving the build out of `pre-commit` just moves broken builds to the remote.

## Rules

1. **Tier by cost, and name the tier for when it runs.**
   `pre-commit` / `ci` / `validate` — two venues and one object. Do not introduce `check` / `verify` / `validate` as three separate targets; they are synonyms and no one will remember which is which.

2. **The editor tier is not optional, even though it has no gate.**
   Format-on-save is what makes `R-GATE-FORMAT` a non-event. Without it the hook rewrites files underneath the developer mid-commit, which is exactly the experience that gets hooks uninstalled.

3. **One owner per concern — and prove it.**
   Where the formatter and the linter overlap, the **formatter wins** and the linter's rule is disabled. This is not a style preference; overlapping ownership produces an unfixable loop (see Problem). Verified conflicts to date: `trailing_comma` (swift-format *adds* trailing commas to multiline literals; SwiftLint's default rule forbids them) and `line_length` (swift-format breaks what it can; a long string literal is unbreakable, so the linter's copy of the rule is pure noise).

4. **Assert that the two tools agree, mechanically.**
   `make tooling-check` formats a representative file, asserts the formatter is **idempotent**, then lints its own output — any violation is a config conflict. Run it after changing either config or bumping either tool. A prose note saying "keep these in sync" is not a control.

5. **Warnings-as-errors is staged, never global from day one.**
   Enable `SWIFT_TREAT_WARNINGS_AS_ERRORS` in the Release/CI configuration first. Turning it on in the inner loop teaches people to comment code out to get a build, which is the opposite of the intent.

6. **A gate that cannot run says so; it never passes vacuously.**
   No app target, no test target, no bundle, no installed tool — each is *reported*, and the task's `### Fix` names it. "Vacuous pass" and "pass" are different claims. Correspondingly, an optional gate whose tool is missing **fails closed** rather than skipping: a silent skip is indistinguishable from success.

7. **Prove the gate inspected something; do not assume it did.**
   A linter pointed at a path that no longer exists lints zero files and exits 0 — the most dangerous failure a gate has, because it is invisible and permanent. `make doctor` compares the linter's `included:` path against the Makefile's `APP_SOURCES`.

   **Scope is per-path, and every path must be listed.** A gate configured for the app
   directory silently ignores the test directory: test code is code, the same rules apply
   there, and nothing reports the omission. Verified here — 12 files linted while the entire
   test target went unchecked. `doctor` now asserts every source root appears in the linter's
   scope, and reports which are MISSING.

   The same class bites through tooling bugs, not just stale config. Two found in practice here: `swift-format --recursive` renders each file's display path by naively stripping the CWD *string* prefix and then opening that, so when the target's absolute path merely starts with the CWD without being inside it (cwd `…/proj`, target `…/proj-src/…`) every file fails to open; and a build whose artifact lands in a hashed DerivedData directory leaves the release gates pointing at a path that never exists. Enumerate inputs explicitly (`find … | xargs`) and pin output locations (`-derivedDataPath`) rather than trusting a tool's own traversal or defaults.

8. **Pin the tools.**
   Neither SwiftLint nor swift-format has a config-level version field, so a silent upgrade can stop enforcing a rule. Pin in a `Brewfile`. Do **not** install swift-format from a package manager — it ships with the Xcode toolchain, and a second copy means formatting with one version and linting with another.

9. **Do not run linters as build-tool plugins.**
   An SPM build-tool plugin puts the linter on the critical path of every compile, needs sandbox exceptions to write anywhere, and couples tool failure to build failure. The `make` facade keeps them separable.

10. **Security gates split by what they inspect.**
    Checks on the **artifact** (entitlements, `get-task-allow`, hardened runtime, ATS) belong to the release tier and are specified in ADR-SWIFT-S06 — they are the highest-yield security gates a macOS app has, because generic SAST does not look at bundles. Checks on the **repository** (secrets, dead code, SAST) are CI-tier and opt-in here.

11. **A gate must be executed against a real artifact before it is trusted.**
    Reviewing a gate's command tells you it is plausible; running it tells you whether it
    inspects anything. Every defect below survived careful review and died on first execution:
    a `BUNDLE` path pointing where the build never writes (release gates permanently
    unreachable while appearing configured); a formatter invocation that inspected zero files;
    a linter scope that silently excluded the test target; an entitlements assertion that
    reached the network. **The minimum bar is that a gate has been shown to both pass and
    fail** — a gate only ever observed passing is indistinguishable from one that cannot fail.

12. **State the tier in the failure message, not only in the docs.**
    A release-tier gate run against a debug artifact must say so. `R-GATE-HARDENING` cannot
    pass on a Debug bundle by construction: Xcode's debug-dylib layout (`ENABLE_DEBUG_DYLIB`)
    ships a shim plus `*.debug.dylib`/`__preview.dylib` and is signed **without** hardened
    runtime, regardless of `ENABLE_HARDENED_RUNTIME = YES`. Reporting "hardened runtime is not
    enabled" sends the reader hunting a build setting that is already correct; the gate now
    detects the debug layout and names the tier instead.

13. **A multi-stage gate reports per stage, and names stages it cannot verify locally.**
    Aborting at the first failure with a bare exit code tells the reader nothing about which
    of four checks failed or why. Report each stage. More importantly, some stages **cannot
    pass without an external authority** — `R-GATE-SIGN`'s Gatekeeper and stapling checks
    require a Developer ID and a completed notarization round-trip, so they fail on every
    development build by construction. Say so in the output. An unexplained permanent failure
    invites someone to "fix" it by weakening the check, which deletes the only thing it was
    guarding. Stages that *can* be verified locally (signature validity, entitlements matching
    the reviewed file) should be, and should be shown passing.

## Tool selection

Chosen because each is the ecosystem default with no meaningful contender — recorded for completeness, not because the choice was hard.

| Concern | Tool | Note |
|---|---|---|
| Format | **`swift-format`** via `xcrun` | Ships with the toolchain. Pick this *or* the third-party SwiftFormat — never both; two rewriters is rule 3's failure mode by construction |
| Lint | **SwiftLint** `--strict` | Custom regex rules are the cheapest way to make an architecture rule enforceable rather than aspirational |
| Test | **Swift Testing** | XCTest retained for UI and performance tests |
| Dead code | **periphery** | Opt-in |
| Secrets | **gitleaks** | Opt-in |

Note that `--strict` reports **every** violation as an error, so a `severity: warning` custom rule still fails the run. Write custom rules precisely enough that a false positive never blocks correct code.

## Out of scope

- **The `verify:` command per rule** — [`../qa/feature-qa-checklist.md`](../qa/feature-qa-checklist.md), the single source.
- **Release-chain ordering, signing, notarization, and the artifact-hardening gates** — [ADR-SWIFT-S06](ADR-SWIFT-S06-build-signing-distribution.md).
- **Compiler settings** (strict concurrency, upcoming features, diagnostics) — [ADR-SWIFT-S02](ADR-SWIFT-S02-app-stack.md) decides the posture; `stencils/Build Configs/Project-Base.xcconfig` carries the values.

## Alternatives considered

| Option | Verdict |
|---|---|
| Tier by cost; both git hooks wired | **Chosen** — feedback arrives as early as its cost allows, and nothing is only-in-CI |
| Everything in `pre-commit` | Rejected — minutes per commit ⇒ `--no-verify` becomes habit ⇒ the gate protects nothing while appearing to |
| Everything in CI only | Rejected — a formatting nit costs a remote round-trip; the inner loop learns nothing |
| Only a `pre-commit` hook, no `pre-push` | Rejected — moving the build out of `pre-commit` without a second hook just relocates broken builds to the remote |
| SPM build-tool plugins for lint/format | Rejected — on the critical path of every build, sandbox exceptions to write, tool failure becomes build failure |
| Fastlane lanes | Rejected — a Ruby toolchain and a second command vocabulary for what `make` plus two scripts already do |
| Xcode "Run Script" build phase for SwiftLint | Rejected — same critical-path problem, plus it only fires for people building in Xcode, so CI and agents diverge from developers |

## Consequences

**Positive:** each gate runs at the earliest point its cost is acceptable, so the fast feedback stays fast and stays used; both hooks together mean no tier is skippable by habit; the formatter/linter conflict class is eliminated and *kept* eliminated by an executable check rather than a comment; vacuous passes — the failure mode where a gate reports success while inspecting nothing — are surfaced by `doctor` and by fail-closed optional gates.

**Earned in practice:** this ADR's rules 4, 7, 11 and 12 were each written *after* a gate
failed to do what its own definition claimed. That is the argument for rule 11 in miniature —
the tiering was sound on paper from the start, and four of its controls were still wrong.

**Negative:** two hooks plus a `Makefile` is more machinery than one `pre-commit` chain, and `make install-hooks` is a step every clone must run (`doctor` reports when it hasn't); the tier boundary is a judgment call that will need re-litigating whenever a gate's cost changes — which is precisely why it is written down here; `--strict` means a badly-written custom lint rule blocks correct code, so custom rules carry a higher precision bar than advisory ones.

## Related

- **Release tier and artifact hardening:** [ADR-SWIFT-S06](ADR-SWIFT-S06-build-signing-distribution.md) — owns `R-GATE-SIGN` and `R-GATE-HARDENING`.
- **Stack and compiler posture:** [ADR-SWIFT-S02](ADR-SWIFT-S02-app-stack.md) — what the gates enforce.
- **Concurrency diagnostics:** [ADR-SWIFT-S07](ADR-SWIFT-S07-concurrency-and-main-thread.md) — strict concurrency is a build-tier gate, not a lint rule.
- **Gate definitions:** [`../qa/feature-qa-checklist.md`](../qa/feature-qa-checklist.md).
- **Conventions:** [`../conventions.md`](../conventions.md).
