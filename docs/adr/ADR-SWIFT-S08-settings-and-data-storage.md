# ADR-SWIFT-S08: Settings and Data Storage

**Date:** 2026-07-25
**Status:** Accepted
**Class:** System (portable across Swift / macOS app projects)

## Problem

"Where does config go?" conflates kinds of state that have opposite requirements, and the answer is usually chosen once, early, for all of them at once.

A UI toggle and a hand-authored script file are not the same thing. One is machine-written and machine-read, changed only through the app's own UI, and benefits from managed-preference and MDM support. The other is authored in a text editor, kept under version control by users, diffed, and shared. Storing both in one place makes one of them wrong: hand-edited files buried in `~/Library/Application Support/` are undiscoverable and awkward to `git init`, and machine state dropped into a dotfile directory gets committed and diffed as noise.

**Context:**
- macOS provides three conventional locations with different semantics and different tooling.
- `NSUserDefaults` is not a file API — it is a `cfprefsd`-mediated domain with caching, and hand-editing the backing plist while the app runs loses the edit.
- Users of configurable/scriptable apps expect their configuration to be a directory they own.

## Decision

**Three stores, separated by one test: does the user open it in a text editor?**

| Store | Location | Contents |
|---|---|---|
| **App settings** | `~/Library/Preferences/<bundle-id>.plist`, via `UserDefaults` | UI state, toggles, feature flags, window frames |
| **User configuration** | a user-visible directory — `~/.<product>` or `~/Documents/<Product>`; user-settable | hand-authored files, scripts, plugins |
| **App support data** | `~/Library/Application Support/<Product>/` | caches, generated databases, logs — **not created until something needs it** |

If the user edits it by hand, it is user configuration. If only the app writes it and only the app reads it, it is app settings — or, when it is bulk or regenerable, app support data.

## Rules

1. **App settings stay in `UserDefaults`.**
   Not a JSON file, not YAML in the config directory. `UserDefaults` provides managed/forced preferences (MDM, configuration profiles), `defaults read`/`defaults write` tooling, and per-domain isolation for free. A file has no equivalent for the first, and reimplementing it is not worth doing.

2. **`UserDefaults` is reached through one typed facade.**
   A `SettingsService` (ADR-SWIFT-S04) owns the keys and the types. `UserDefaults.standard` appears in exactly one implementation file. Scattered string keys are how two features end up disagreeing about a default value.

3. **Register defaults; never scatter fallbacks.**
   `register(defaults:)` at launch, in one place. A `?? false` at each read site means the default is defined N times and will diverge.

4. **Namespace the app's own keys.**
   `<prefix>.<area>.<name>`. This matters whenever another mechanism can write into the same domain — a scripting API exposing settings to user code, for instance, can otherwise stomp app state through a key collision.

5. **The user-configuration location is itself an app setting.**
   It cannot live inside the directory it points at. This is the one setting that must be read before any configuration is loaded.

6. **Never tell a user to edit a preference plist.**
   `cfprefsd` caches the domain in memory and will overwrite external edits while the app runs. All documentation, support guidance, and issue templates say `defaults write`. Fix this wording before the first document exists — it propagates.

7. **Do not create Application Support speculatively.**
   The directory appears when a cache, database, or log actually needs it. An empty directory in every user's Library is clutter that implies state that is not there.

8. **Changing the configuration location is a lifecycle event.**
   If the app derives paths, watches directories, or `chdir`s at launch, a mid-session change of the config directory needs either a full teardown/reload of whatever consumed it, or a relaunch. Decide which *before* designing the settings UI — retrofitting a reload path into a launch-time assumption is expensive.

9. **State that the app can regenerate is never in user configuration.**
   Caches, indexes, and downloaded artifacts go to Application Support so that deleting them is safe and so users do not commit them.

10. **"Reset to defaults" is explicit about scope.**
    Two stores means two operations — remove the defaults domain *and* the configuration directory. UI that implies one wipe covers both is a support burden. The same applies to uninstall documentation.

## Sandbox note

Under App Sandbox these paths become container-relative and a user-chosen configuration directory requires a security-scoped bookmark, persisted and re-resolved at launch. A directly-distributed system utility is typically unsandboxed, which is why the plain paths above apply — but the choice belongs to the consuming project and changes this ADR's mechanics if made differently.

## Out of scope

- **The repository layout** — ADR-SWIFT-S01 (this ADR is the *installed* footprint).
- **The service protocol shape for `SettingsService`** — ADR-SWIFT-S04.
- **The settings UI** — a feature concern (ADR-SWIFT-S03) and a UX shape spec.

## Alternatives considered

| Option | Verdict |
|---|---|
| Three stores split by the text-editor test | **Chosen** — each kind of state lands where its tooling and expectations already are |
| Everything in `~/Library/Application Support/<Product>/` | Rejected — buries hand-authored files where users cannot find or version them; loses managed-preference support |
| Everything in a dotfile directory, including app settings | Rejected — machine state becomes diff noise in the user's config repo; loses MDM, `defaults`, and forced preferences |
| A single app-owned config file (JSON/TOML) replacing `UserDefaults` | Rejected — reimplements defaults registration, change observation, managed preferences, and per-domain isolation, for no gain |
| `@AppStorage` / property wrappers directly in views | Rejected — puts key strings and defaults in the view layer; unmockable; violates ADR-SWIFT-S05 rule 9 |

## Consequences

**Positive:** nothing has to be built — app settings already work the way macOS expects; managed preferences and `defaults` tooling come free; user configuration stays discoverable and version-controllable; no speculative directories.

**Negative:** state is split across two mechanisms, so reset and uninstall are multi-step operations that must be documented and surfaced honestly; the "never hand-edit the plist" caveat has to be repeated in user-facing docs; a user-settable configuration location introduces a launch-ordering constraint (rule 8) that shapes the settings UI.

## Related

- **Service seam:** [ADR-SWIFT-S04](ADR-SWIFT-S04-pure-service-modules.md) — the typed `SettingsService` facade.
- **Injection:** [ADR-SWIFT-S05](ADR-SWIFT-S05-dependency-injection.md) rule 9 — why `UserDefaults.standard` is not read from features.
- **Repository layout:** [ADR-SWIFT-S01](ADR-SWIFT-S01-repository-structure.md) — the *repo*, as distinct from the installed footprint.
- **Instance:** record your product's concrete three-store layout as a project ADR (`ADR-SWIFT-00x`) and link it here.
- **Conventions:** [`../conventions.md`](../conventions.md).
