# Feature QA Checklist (non-UX) — said-swift

> The non-UX quality contract: project-wide gates expressed as `R-GATE-*` rules.
> Companion to [`feature-ux-checklist.md`](feature-ux-checklist.md) (visual / interaction /
> platform-behaviour rules). Consumed by `/said:review-qa` (Inspect's hygiene gate) and by
> `make pre-commit`.
>
> **This file is the only place gate `verify:` actions live.** `CLAUDE.md` names the
> `R-GATE-*` IDs and links here; it never inlines the command.

## How rules are organized

Each rule carries five fields:

- **id** — stable handle the QA report / commits / `Refs:` lines cite (`R-GATE-BUILD`, …).
- **source** — canonical source (ADR file or runtime convention).
- **tier** — when it runs: `pre-commit` (seconds) · `ci` (minutes) · `release` (needs a built bundle) · `opt-in`. Tiering rationale: [ADR-SWIFT-S11](../adr/ADR-SWIFT-S11-quality-gates.md).
- **applies-to** — which task shapes the rule fires for. `any` fires on every task.
- **summary** — one-line statement.
- **verify** — concrete action.

## Command resolution

Gate `verify:` actions invoke **`make <target>`**. The resolution chain is
**`CLAUDE.md` → `Makefile` → `scripts/` → operator**: `make` is the stable verb, the
`Makefile` maps it to a script or `xcodebuild` invocation (the ground-truth tier), and each
`Makefile` gate target carries a comment naming the `R-GATE-*` rule it answers to. Keep the
`Makefile` comments and the rules below in sync.

Never inline a raw `xcodebuild` invocation into a doc, a task entry, or CI — it duplicates
ground truth in a place that will drift (ADR-SWIFT-S10).

## Bundles

```bash
make pre-commit    # FAST  (seconds) — R-GATE-FORMAT → R-GATE-LINT
make ci            # FULL  (minutes) — + R-GATE-BUILD → R-GATE-TEST     ← run at every task close
make validate      # RELEASE         — R-GATE-SIGN → R-GATE-HARDENING
```

**`make ci` is the task-close bundle.** `make pre-commit` is the inner-loop subset wired to the
git `pre-commit` hook; `make ci` is wired to `pre-push`. `make install-hooks` wires both — a
project that installs only the fast hook has moved broken builds to the remote, not removed
them (ADR-SWIFT-S11).

---

## R-GATE-FORMAT — Formatting clean

- **source:** runtime convention (`Makefile` `format-check` → `swift-format lint`)
- **tier:** `pre-commit`
- **applies-to:** `any`
- **summary:** Swift sources match the project's `swift-format` configuration.
- **verify:**
  ```bash
  make format-check
  ```
  Exit 0. `make format` rewrites in place.

## R-GATE-LINT — Lint clean

- **source:** runtime convention (`Makefile` `lint` → `swiftlint --strict`)
- **tier:** `pre-commit`
- **applies-to:** `any`
- **summary:** SwiftLint reports no violations; warnings are errors under `--strict`.
- **verify:**
  ```bash
  make lint
  ```
  Exit 0.

## R-GATE-BUILD — Build succeeds

- **source:** runtime convention (`Makefile` `build` → the project's build entry point)
- **tier:** `ci`
- **applies-to:** `any`
- **summary:** the app target compiles and links, with no warnings escalated by
  `Project-Base.xcconfig` and no Swift 6 concurrency diagnostics (ADR-SWIFT-S07).
- **verify:**
  ```bash
  make build
  ```
  Build succeeds. Swift has no separate typecheck step — the build is the typecheck.

## R-GATE-TEST — Tests pass

- **source:** runtime convention (`Makefile` `test` → `xcodebuild test`)
- **tier:** `ci`
- **applies-to:** `any` (skip only when the project has no test target yet — say so explicitly in `### Fix`)
- **summary:** the unit-test suite passes; the count moved in the expected direction.
- **verify:**
  ```bash
  make test
  ```
  Exit 0. Record the before → after count in the task's `### Fix` line.

## R-GATE-SIGN — Signature and Gatekeeper clean

- **source:** [ADR-SWIFT-S10](../adr/ADR-SWIFT-S10-build-signing-distribution.md)
- **tier:** `release`
- **applies-to:** `release` — any task that touches signing identity, entitlements,
  `Info.plist`, bundle identifier, hardened runtime, or the release chain
- **summary:** the Release bundle is correctly signed, hardened, notarized, stapled, and
  accepted by Gatekeeper; its entitlements are the intended set.
- **verify:**
  ```bash
  make validate
  ```
  Which must cover, each fatal:
  ```bash
  codesign --verify --deep --strict --verbose=2 <bundle>
  spctl --assess --type execute --verbose=4 <bundle>   # `execute` — `install` is for pkg/dmg, not .app
  xcrun stapler validate <bundle>                      # unstapled = fails for offline users
  # entitlements ASSERTED against the source file — a gate that only prints cannot fail:
  diff <(xmllint --c14n --format <entitlements-file>) \
       <(codesign -d --entitlements :- <bundle> | xmllint --c14n --format -)
  ```
  The gate reports **per stage**, because the stages have different prerequisites:

  | Stage | Needs | Verified |
  |---|---|---|
  | 1 signature valid | any identity, incl. ad-hoc | ✅ passes on an ad-hoc build |
  | 2 Gatekeeper accepts | **Developer ID + notarization** | ⛔ cannot pass before then — expected FAIL |
  | 3 notarization stapled | **notarization** | ⛔ cannot pass before then — expected FAIL |
  | 4 entitlements as reviewed | the entitlements file | ✅ verified both ways (matches; detects tampering) |

  Stages 2–3 failing on a development build is **not a defect in the gate**. Do not "fix" it
  by weakening them; they are the reason the gate exists. A mismatch at stage 4 means the
  shipped entitlements are not the reviewed ones. Whether each entry in the source file is
  *justified* is `R-GATE-DEPS`, not this rule.

## R-GATE-DEPS — No unreviewed dependency or entitlement growth

- **source:** [ADR-SWIFT-S02](../adr/ADR-SWIFT-S02-app-stack.md) dependency policy,
  [ADR-SWIFT-S10](../adr/ADR-SWIFT-S10-build-signing-distribution.md) entitlement audit
- **tier:** `ci`
- **applies-to:** `any` task that adds a package, framework, or entitlement
- **summary:** a new dependency clears the four-point bar; a new entitlement is justified in
  writing; neither arrived as a side effect.
- **verify:** the task's `### Fix` or the ADR it references names the addition and the
  justification. `git diff` on the entitlements file and the package manifest shows only
  intended changes.

## R-GATE-HARDENING — Shipped bundle is hardened

- **source:** [ADR-SWIFT-S10](../adr/ADR-SWIFT-S10-build-signing-distribution.md) § Hardening the shipped bundle
- **tier:** `release`
- **applies-to:** `release` — any task touching entitlements, `Info.plist`, signing, or the release chain
- **summary:** the built bundle carries no debug-attach entitlement, has the hardened-runtime
  flag actually set, carries no unjustified hardened-runtime exception, and does not disable ATS.
- **verify:**
  ```bash
  make hardening        # also runs as part of `make validate`
  ```
  Asserts, each fatal:
  - `com.apple.security.get-task-allow` **absent** — lets any process attach a debugger and
    read the app's memory; also a notarization rejection. Never allowlistable.
  - `codesign --display` reports `flags=…(runtime)` — the flag is actually on the signature,
    not merely requested in an xcconfig.
  - every `com.apple.security.cs.*` exception present is listed in `HARDENING_ALLOW` in the
    `Makefile` — the written-justification rule, made mechanical.
  - `NSAllowsArbitraryLoads` is not true in the shipped `Info.plist`.

## R-GATE-SECRETS — No secrets committed *(opt-in)*

- **source:** [ADR-SWIFT-S11](../adr/ADR-SWIFT-S11-quality-gates.md) rule 10
- **tier:** `opt-in` (promote to `ci` once the tool is installed)
- **applies-to:** `any`
- **summary:** no credentials, tokens, or keys in the working tree or history.
- **verify:**
  ```bash
  make scan-secrets
  ```
  Fails closed if `gitleaks` is not installed — a silent skip is indistinguishable from a pass.

## R-GATE-DEADCODE — No unreachable code *(opt-in)*

- **source:** [ADR-SWIFT-S11](../adr/ADR-SWIFT-S11-quality-gates.md)
- **tier:** `opt-in` (promote to `ci` once the tool is installed)
- **applies-to:** `any`
- **summary:** no unused declarations left behind by a refactor.
- **verify:**
  ```bash
  make scan-deadcode
  ```
  Fails closed if `periphery` is not installed.

## R-GATE-TOOLING — The formatter and the linter agree

- **source:** [ADR-SWIFT-S11](../adr/ADR-SWIFT-S11-quality-gates.md) rule 4
- **tier:** `on config change` — after editing `.swiftlint.yml` / `.swift-format`, or bumping either tool
- **applies-to:** any task touching either config or the `Brewfile`
- **summary:** `swift-format` is idempotent, and its output passes `swiftlint --strict` — so
  `make format` followed by `make lint` can both pass.
- **verify:**
  ```bash
  make tooling-check
  ```
  A failure means the two tools disagree and no source file can satisfy both. Disable the
  SwiftLint rule (the formatter owns formatting) rather than leaving it — an unfixable gate
  gets bypassed, and then nothing is enforced.

---

## Enforcement ("always")

Awareness is in `CLAUDE.md` (the `R-GATE-*` names). Enforcement is mechanical — a passive
pointer is skippable by an agent under long context:

- **`make install-hooks`** → points `core.hooksPath` at `scripts/hooks/`: `pre-commit` runs
  the fast tier, `pre-push` runs the full tier. Both, or broken builds simply move to the remote.
- **CI** → one step running `make ci`.
- **`/said:review-qa`** → reads this file at task close and runs each applicable rule's `verify:`.
- **`make doctor`** → reports what cannot currently run, whether the hooks are installed, and
  whether the linter's scope still matches `APP_SOURCES` (a stale path lints zero files and
  passes vacuously — the most dangerous failure a gate has).

## Optional gates (add as the project grows)

- **R-GATE-UITEST** → `make uitest` — when an XCUITest target exists.
- **R-GATE-DOCS** → `make docs` — when the project generates API documentation as part of the
  build and lints its docstrings.
- **R-GATE-A11Y** → an Accessibility Inspector audit run — currently a manual item in the UX
  checklist; promote here if it becomes scriptable.
- **R-GATE-TSAN** → the suite under Thread Sanitizer. High value for an app doing event taps
  and background work: TSan sees through the ObjC/C the app links against, where Swift's
  strict concurrency cannot reach.

Each new gate: add the `R-GATE-*` rule here, add a `Makefile` target with the rule comment,
add it to the `pre-commit` chain if it is `applies-to: any`, and add its ID to `CLAUDE.md`
Quality Gates.

---

## When a gate cannot run

A gate with nothing to act on — no app target yet, no test target yet, no Release bundle —
is **reported, never silently skipped**. `make doctor` prints what is present; the task's
`### Fix` names the gate and why it could not run. "Vacuous pass" and "pass" are different
claims, and a task log that conflates them is a defect (`template-tasks.md`, close-of-task
step 4).
