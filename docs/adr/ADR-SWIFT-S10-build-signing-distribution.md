# ADR-SWIFT-S10: Build, Signing & Distribution

**Date:** 2026-07-25
**Status:** Accepted
**Class:** System (portable across Swift / macOS app projects)

## Problem

A macOS app that ships outside the App Store has a delivery chain with no forgiving steps: build settings, code signature, hardened runtime, entitlements, notarization, stapling, and an update feed. Each has a failure mode that is invisible on the developer's machine and fatal on a user's — Gatekeeper refusing a downloaded build, an entitlement silently disabling a capability, an unstapled ticket failing when the user is offline, a `CFBundleVersion` that went backwards freezing every future update.

Two structural problems make this worse than it needs to be. Build settings default to `project.pbxproj`, where changes are unreviewable. And the commands that produce a shippable artifact are long, order-dependent `xcodebuild` invocations that end up living in someone's shell history rather than the repo.

**Context:**
- Direct distribution (Developer ID + notarization), not the App Store.
- The same artifact must be reproducible in CI and locally.
- Quality gates must be mechanically runnable by an agent at task close (`R-GATE-*`, `docs/qa/feature-qa-checklist.md`).
- Version identity feeds the updater and can only move forward.

## Decision

**All build settings live in layered `.xcconfig` files. Every build, gate, and release step is a `make` target that wraps a script — never a bare `xcodebuild` in documentation or CI. The release chain is build → validate → notarize → staple → publish, and each step fails closed.**

### xcconfig layering

```
<Product>/Build Configs/
├── Project-Base.xcconfig        # warnings, deployment target, Swift version/concurrency, language dialects
├── <Product>-Base.xcconfig      # PRODUCT_NAME, bundle ID, INFOPLIST_FILE, entitlements, hardened runtime
├── <Product>-Debug.xcconfig     # #include the two above; ad-hoc signing, no optimization
└── <Product>-Release.xcconfig   # #include the two above; Developer ID identity, DEVELOPMENT_TEAM
```

Rules:

1. **Nothing in `project.pbxproj`.** The target's Build Settings tab shows no overrides. A setting that is not in an xcconfig is a setting nobody reviewed.
2. **`PRODUCT_NAME` is the source of truth for the bundle name.** Any script variable naming the app (`APP_NAME` and friends) must be set to the same value, or the scripts will look for a bundle Xcode never produced.
3. **`PRODUCT_BUNDLE_IDENTIFIER` is a one-way door.** macOS ties TCC grants (Accessibility, Automation, Screen Recording) to signing identity + bundle ID. Changing it after release silently re-prompts every user for every permission. Settle it before the first build that leaves the machine.
4. **Secrets are not xcconfig values.** Signing identities and team IDs are fine (they are public in the signature anyway). API keys, DSNs, and notarization credentials come from the environment or a keychain profile.
5. **A downstream override hook is worth having.** A single `#include?` of an untracked file at the end of Debug/Release lets a fork or a local machine override identity without touching tracked files.

### Signing and hardening

- `ENABLE_HARDENED_RUNTIME = YES` — required for notarization, non-negotiable.
- Entitlements are **additive and audited**. Every entitlement in the file must be traceable to a capability the app actually ships. `com.apple.security.cs.disable-library-validation` and `allow-unsigned-executable-memory` in particular must be justified in writing or removed — they materially weaken the binary.
- Debug builds sign ad-hoc (`CODE_SIGN_IDENTITY = -`). For a permission-gated app this re-prompts for Accessibility on every rebuild; a self-signed local certificate with a stable identity avoids that and is worth the one-time setup.
- Release builds sign with `Developer ID Application: <Entity> (<TeamID>)`. **Copy that string from `security find-identity -v -p codesigning`** — character for character, including any trailing punctuation in the registered entity name. Do not hand-type it.

### Notarization

Notarization credentials live in a keychain profile, created once:

```bash
xcrun notarytool store-credentials "<PROFILE>" --key AuthKey_XXX.p8 --key-id XXX --issuer <uuid>
```

Prefer an App Store Connect API key over an Apple ID + app-specific password: it does not expire on password change and is scopeable.

The chain, in order, each step fatal:

1. Zip the bundle with **`ditto -c -k --keepParent`** (Apple's documented form). The flag that matters is `ditto` itself, not its options: `zip` flattens symlinks and drops extended attributes, and a bundle flattened by `zip` fails notarization or fails to launch. Add `--norsrc` / `--sequesterRsrc` only if the project has a reason to — they decide what happens to resource forks, which a modern bundle does not have.
2. `xcrun notarytool submit --wait`.
3. `xcrun stapler staple` the bundle. **Skipping this is the classic mistake** — an unstapled notarized app passes Gatekeeper only while the user is online.
4. Verify: `codesign --verify --deep --strict --verbose=2` and `spctl --assess --type execute` (**`execute`**, not `install` — `install` assesses installer packages, not `.app` bundles), then assert the shipped entitlements match the source file rather than merely printing them (`R-GATE-SIGN`).

Notarization is a gate on the artifact, not a build step. It runs against an already-validated Release build.

### Versioning

`CFBundleShortVersionString` (marketing) and `CFBundleVersion` (build) are derived at build time — from git tags and commit count, or from CI — never hand-edited in `Info.plist`.

- Apple requires `CFBundleShortVersionString` to be three dot-separated integers, so **tags must be plain `X.Y.Z`**.
- `CFBundleVersion` feeds the updater's version comparison and **must increase monotonically forever**. The first public release sets a permanent floor; a value that starts high can never come down.
- Inheriting a tag namespace (from a fork or a rename) imports its version history. Decide the starting version deliberately before the first release, and check both `git describe --tags --abbrev=0` and the highest tag by version sort — they can disagree when tags exist off the current history.

### The `make` facade

Every command an agent, a CI job, or a human runs is a `make` target. The `Makefile` maps the verb to a script or `xcodebuild` invocation, and each gate target carries a comment naming the `R-GATE-*` rule it answers to.

**Which gate runs at which moment is ADR-SWIFT-S11's decision**, not this one. This ADR owns the *release* tier: `make validate` runs `R-GATE-SIGN` (signature, Gatekeeper, staple, entitlements asserted against the source file) and `R-GATE-HARDENING` (below) against a built bundle.

Documentation names the `make` verb. Concrete commands live in the `Makefile`; gate definitions live in `docs/qa/feature-qa-checklist.md`. Neither is duplicated into `CLAUDE.md`.

### Hardening the shipped bundle

The highest-yield security checks a macOS app has are assertions about its own bundle — generic source scanners do not look there. All are release-tier and all fail closed:

- **`com.apple.security.get-task-allow` must be absent.** Xcode injects it into Debug builds; it lets any process attach a debugger and read the app's memory. It is simultaneously a genuine vulnerability and a notarization rejection, and it is one `grep` away from impossible. Never allowlistable.
- **The hardened-runtime flag must actually be set on the signature** — not merely requested in an xcconfig.
- **Hardened-runtime exceptions are allowlisted or absent.** `disable-library-validation`, `allow-unsigned-executable-memory`, `allow-dyld-environment-variables`, and `disable-executable-page-protection` each materially weaken the binary. Each must appear in an explicit, committed allowlist carrying a written justification, or the gate fails. "Justified in writing" becomes mechanical rather than aspirational.
- **`NSAllowsArbitraryLoads` must not be true** in the shipped `Info.plist`.

### Updates

If the app ships an updater (Sparkle or equivalent):

- The feed URL must point at infrastructure the project controls. A feed inherited from a template or a fork will update users into a different product.
- Serve the appcast over HTTPS.
- Update signing (EdDSA) is a separate signature from code signing and a separate key to manage. Adding it is a real per-release step; decide before the first release rather than retrofitting, since existing installs validate against whatever the first version shipped.

## Out of scope

- **Where the app stores data once installed** — ADR-SWIFT-S08.
- **What the gates check semantically** — `docs/qa/feature-qa-checklist.md` (this ADR names them; that file defines them).
- **CI provider specifics** — project concern.

## Alternatives considered

| Option | Verdict |
|---|---|
| Layered xcconfig + `make` facade over scripts | **Chosen** — reviewable settings, one command vocabulary for humans, CI, and agents |
| Settings in the Xcode target editor | Rejected — unreviewable `pbxproj` diffs; drift between configurations goes unnoticed |
| Bare `xcodebuild` invocations in docs and CI | Rejected — long, order-dependent, and duplicated in three places that drift |
| A build tool generating the project (Tuist / XcodeGen) | Rejected as the default — real benefits for large or multi-target projects, but adds a generation step and a second source of truth. Reconsider past ~5 targets |
| Fastlane | Rejected — a Ruby toolchain and a second command vocabulary for what `notarytool` and a shell script already do |
| App Store distribution | Out of scope for this class of app — sandbox requirements are incompatible with system-level capability |

## Consequences

**Positive:** every build setting is a reviewable text diff; one command vocabulary serves humans, CI, and agents; the release chain is scripted, ordered, and fails closed; version identity is derived, so it cannot drift from the repository.

**Negative:** xcconfig layering is a concept Xcode's UI actively fights — a setting edited in the target editor silently lands in `pbxproj` and must be caught in review; the `make`→script→`xcodebuild` indirection is one more hop when debugging a build failure; notarization adds minutes to every release and depends on an Apple service being available.

## Related

- **Layout:** [ADR-SWIFT-S01](ADR-SWIFT-S01-repository-structure.md) — where `Build Configs/` and `scripts/` sit.
- **Stack:** [ADR-SWIFT-S02](ADR-SWIFT-S02-app-stack.md) — the dependency policy that keeps signing uncomplicated.
- **Gates:** [`../qa/feature-qa-checklist.md`](../qa/feature-qa-checklist.md) — the `R-GATE-*` definitions.
- **Conventions:** [`../conventions.md`](../conventions.md).
