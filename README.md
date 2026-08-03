# SAID-swift — Software AI Delivery for macOS apps

AI-native **Swift 6 / macOS** starter: AppKit shell with SwiftUI content, strict concurrency, system frameworks behind contracts, and a signed-and-notarized delivery chain. Self-contained — its own conventions, ADRs, quality gates, and AI development guide (`CLAUDE.md`).

A **documentation-and-gates spine, not a code scaffold** — it ships no `.xcodeproj`, because an Xcode project is trivial to create and impossible to keep generic.

## What's included

### Documentation (`docs/`)
- **`CLAUDE.md`** — AI development guide (entry point for Claude Code)
- **`conventions.md`** — Swift/macOS code patterns, copyable
- **`idea.md` / `vision.md`** — project context stubs
- **`adr/ADR-SWIFT-S01..S09`** — System ADRs:

  | ADR | Decides |
  |---|---|
  | S01 | Repository structure — `App/` composes, `Features/` implement, `Core/` wraps frameworks; **all build settings in xcconfig** |
  | S02 | Stack — Swift 6 strict concurrency; **AppKit shell hosting SwiftUI content**; four-point dependency bar |
  | S03 | Feature anatomy organized around the **`@MainActor` boundary** |
  | S04 | System frameworks behind protocols; **exactly one file imports each framework** |
  | S05 | `AppDelegate` → `AppEnvironment` composition root; per-feature `Deps`; no I/O singletons |
  | S06 | xcconfig layering, `make` facade, notarize → **staple**, derived versioning, one-way doors |
  | S07 | Actor isolation; **every legacy callback hops on its first line**; no `DispatchQueue.main.sync` |
  | S08 | Three stores split by "does the user open it in a text editor?" |
  | S09 | Typed per-seam errors; **expected vs unexpected**; `os.Logger`; permission failures get a route |
  | S10 | Quality gates **tiered by feedback cost**; both git hooks wired; one owner per concern, asserted |

- **`features/`, `qa/`, `ux/`** — feature-spec + append-only task-log stencils, `R-GATE-*` definitions, and a per-surface macOS UX checklist (window / settings / menubar / list / form / alert / permission)

### Tooling
- **`Makefile`** — the command facade every gate resolves through. One "Project seam" block at the top is the only thing a consuming project edits.
- **`.swiftlint.yml`** — enforces several ADR rules **mechanically**, not just in prose:

  | Custom rule | Blocks |
  |---|---|
  | `no_main_sync` | `DispatchQueue.main.sync` (ADR-SWIFT-S07 rule 6) |
  | `no_delegate_reachback` | `NSApp.delegate as!` (ADR-SWIFT-S05 rule 8) |
  | `no_print` | `print` / `NSLog` (ADR-SWIFT-S09 rule 7) |
  | `no_ambient_user_defaults` | `UserDefaults.standard` outside its service (ADR-SWIFT-S08 rule 2) |
  | `no_ambient_workspace` | `NSWorkspace.shared` outside its service (ADR-SWIFT-S05 rule 9) |
  | `no_unjustified_unchecked_sendable` | unexplained `@unchecked Sendable` (ADR-SWIFT-S07 rule 4) |

- **`.swift-format`** — formatter config. Note `OrderedImports` requires **one lexicographic import block**; `conventions.md` documents this because a grouped-and-commented import list silently fails `make format-check`.
- **`scripts/tooling-fixedpoint.sh`** (`make tooling-check`) — asserts the formatter and the linter *agree*: formats a representative file, checks idempotency, then lints the formatter's own output. Catches the unfixable loop where `make format` writes X and `make lint` demands Y. Two conflicts were found and fixed this way (trailing commas, line length).
- **`scripts/hooks/`** (`make install-hooks`) — `pre-commit` → fast tier, `pre-push` → full tier.
- **`Brewfile`** — pins the tooling. Neither SwiftLint nor swift-format has a config-level version field, so an unpinned bump can silently stop enforcing a rule.
- **`stencils/Build Configs/Project-Base.xcconfig`** — a starting build configuration: Swift 6 strict concurrency, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, upcoming-feature flags, the two `-warn-long-*` compile-time alarms, and hardening. Every value verified against Swift 6.3.3 / Xcode 26.6.
- **`.github/workflows/ci.yml`** — runs the same `make` verbs a developer runs.

## Commands

```bash
make doctor         # what can run, hooks installed, lint scope agreement
make pre-commit     # FAST tier (seconds) — format-check + lint         → pre-commit hook
make ci             # FULL tier (minutes) — + build + test              → pre-push hook, CI
make validate       # RELEASE tier — signature, Gatekeeper, staple, entitlements + hardening
make tooling-check  # assert swift-format and SwiftLint agree
make install-hooks  # wire both git hooks
make scan           # opt-in: gitleaks + periphery
```

**Tiered by cost** (ADR-SWIFT-S10): in Swift the build *is* the typecheck and costs minutes,
so a pre-commit hook that builds gets bypassed — and a bypassed gate is worse than none,
because the project still believes it is protected.

Gate definitions live in [`docs/qa/feature-qa-checklist.md`](docs/qa/feature-qa-checklist.md) — the only place a `verify:` command is written down.

**Requires:** Xcode, `bash` (the `Makefile` uses process substitution), and the tools in the `Brewfile` (`brew bundle`). `swift-format` is deliberately *not* in the Brewfile — it ships with the Xcode toolchain, and a second copy means formatting with one version and linting with another.

## Workflow

Feature work runs the SAID phases over this spine — scope → architect → implement → verify → debrief — via the `said:` plugin. See the **SAID workflow** section of [`CLAUDE.md`](CLAUDE.md).

## After cloning

1. Set the **Project seam** block at the top of the `Makefile` — `APP_NAME`, `APP_ROOT`.
2. Set `included:` in `.swiftlint.yml` to the same path as `APP_SOURCES`. **They must agree** — a stale path lints zero files and passes vacuously.
3. Create the Xcode project with the ADR-SWIFT-S01 layout, and put every build setting in `Build Configs/*.xcconfig` from the first commit — retrofitting settings out of `project.pbxproj` later is miserable.
4. Copy `stencils/Build Configs/Project-Base.xcconfig` into `<APP_SOURCES>/Build Configs/` and settle `MACOSX_DEPLOYMENT_TARGET` — `@Observable` needs macOS 14+, and swapping the observation mechanism across a built UI is expensive (`conventions.md`).
5. `brew bundle` then `make install-hooks`, and run `make doctor` to confirm.
6. Fill in `docs/idea.md`, `docs/vision.md`, and the **project-specific section** at the bottom of `CLAUDE.md`.
7. Read `CLAUDE.md`, then `docs/adr/README.md` for the decision landscape.

## Divergence

The `ADR-SWIFT-S0x` files are the template. If you edit one, your copy has forked — record *why* in a project ADR (`ADR-SWIFT-00x`) that names the system ADR it overrides. Silent divergence is how a template stops being one.
