# Feature UX checklist — said-swift

Mechanical per-surface UX gate for a macOS app. `/said:review-ux` runs each applicable rule
against a changed surface and returns PASS / FAIL / SOFT-FLAG with `file:line` evidence (or a
run-the-app observation). Rules are tagged by **surface shape** so only the relevant ones apply.

Surface shapes: `window` · `settings` · `menubar` · `list` · `form` · `alert`.

Verification here is source-inspection plus, where stated, a manual observation in a running
build. There is no browser automation on this platform — a rule that cannot be checked from
source says so and stays a manual item.

## applies-to: any

- [ ] **Appearance** — renders correctly in **Light and Dark**. Colors come from semantic
      `NSColor` / SwiftUI `Color` roles or asset-catalog appearance-aware colors, never
      hardcoded RGB (`file:line` on any literal color).
- [ ] **Accent and contrast** — respects the system accent color; legible with
      *Increase Contrast* and *Reduce Transparency* enabled.
- [ ] **Text scaling** — no clipped or truncated labels at the largest system text size;
      layout uses intrinsic sizes, not fixed frames sized to today's string.
- [ ] **Keyboard** — every action reachable without the mouse. Tab traversal is ordered,
      Return triggers the default button, Escape cancels. Full Keyboard Access on.
- [ ] **Accessibility labels** — every non-text control has an accessibility label; images
      that carry meaning have descriptions, decorative ones are hidden from VoiceOver.
- [ ] **Main thread** — no synchronous I/O, `Process` launch, or scripting evaluation on the
      main actor in the changed path (ADR-SWIFT-S07). `file:line` evidence.
- [ ] **Empty state** — collections render a deliberate empty state with a next action, not a
      blank rectangle.
- [ ] **Loading state** — any operation that can exceed ~1s shows progress and stays
      cancellable; the window never appears frozen.
- [ ] **Error state** — expected failures surface in place; unexpected ones are logged and
      surfaced only if the user's next action depends on them (ADR-SWIFT-S09). No bare error
      codes in user-facing text.
- [ ] **Localization-ready** — user-facing strings go through `String(localized:)`; no
      runtime concatenation of sentence fragments.
- [ ] **No placeholder shipping** — no lorem ipsum, no "TODO" label, no debug-only control
      reachable in a Release build.

## applies-to: window

- [ ] **Frame restoration** — `setFrameAutosaveName` set; the window reopens where the user
      left it, on a valid screen.
- [ ] **Minimum size** — a min size is set and the layout survives it; resizing does not
      overlap or clip controls.
- [ ] **Title and identity** — the window title says what it is; the app name is not
      duplicated inside the content.
- [ ] **Close behaviour is deliberate** — closing the last window either quits or leaves a
      documented way back (menu bar item, dock icon, `applicationShouldHandleReopen`).
- [ ] **Multiple displays** — usable on a secondary display and after a display disconnect.

## applies-to: settings

- [ ] **Standard shape** — the Settings window follows the platform pattern (toolbar-selected
      panes, standard sizing), opened by the standard menu item and its `⌘,` equivalent.
- [ ] **Immediate apply** — settings take effect on change. No OK / Apply / Cancel triad.
- [ ] **Backed by a registered default** — every control's value has a registered default and
      round-trips through the settings facade (ADR-SWIFT-S08), not a raw `UserDefaults` read.
- [ ] **Reset scope is honest** — any "reset" affordance states which stores it clears
      (defaults domain vs user configuration directory) — see ADR-SWIFT-S08 rule 10.
- [ ] **Restart-required settings say so** — a setting that only takes effect on relaunch
      says that at the control, not in a later error.

## applies-to: menubar

- [ ] **Template image** — the status item icon is a template image, so it adapts to light /
      dark menu bars and highlighting.
- [ ] **Activation policy is deliberate** — `.accessory` when there is no dock icon; any
      runtime policy switch is intentional and reversible.
- [ ] **Menu is complete** — every capability reachable only from the menu bar is in the menu,
      including quit and settings.
- [ ] **Key equivalents** — global shortcuts are discoverable in the menu, and conflicts with
      system shortcuts are resolved.
- [ ] **Survives the crowded menu bar** — the app degrades sanely when the status item is
      hidden by lack of space (notch / many items).

## applies-to: list

- [ ] Columns, sort, and filters match the surface's UX shape spec in `docs/ux/`.
- [ ] Row actions are keyboard-reachable; the primary action is obvious and has a default
      binding (Return / double-click).
- [ ] Selection survives a data refresh; the list does not scroll-jump on update.
- [ ] Large collections do not block the main actor while loading or filtering.

## applies-to: form

- [ ] Validation surfaces **at the field**, on commit — not as an alert.
- [ ] Destructive actions confirm, and the confirmation names what will be lost.
- [ ] In-progress state disables the commit control rather than allowing a double submit.
- [ ] Success and failure are both explicit; silence is not feedback.

## applies-to: alert

- [ ] **The alert is a decision.** `NSAlert` is used only when the user must choose, or when
      work stopped and they need to know why (ADR-SWIFT-S09 rule 5). Informational messages,
      validation, and recovered failures do not interrupt.
- [ ] Buttons are verbs describing outcomes ("Replace" / "Cancel"), not "OK".
- [ ] The destructive choice is not the default button.
- [ ] Message text says what happened and what to do next; the error code is in the log.

## applies-to: permission (any surface gated by TCC)

- [ ] **Pre-flight explanation** — the app says what permission it needs and why *before*
      triggering the system prompt.
- [ ] **Recovery route** — a denied or not-yet-granted state offers a button that opens the
      relevant System Settings pane. A dead-end "permission denied" message is a FAIL
      (ADR-SWIFT-S09 rule 6).
- [ ] **Degrades, not breaks** — capability blocked by a missing permission leaves the rest of
      the app usable, and the affected UI says why it is unavailable.
- [ ] **Re-checks on return** — regaining focus after the user grants permission re-evaluates
      state rather than requiring a relaunch (or says a relaunch is required).

## verify:

Each rule's evidence is a `file:line`, a `grep` result, or a stated manual observation in a
running build. SOFT-FLAG = reviewer judgment; FAIL = contract violation.

Rules that are inherently manual today — VoiceOver traversal, an Accessibility Inspector
audit, secondary-display behaviour — are reported as such rather than silently passed. A
report that claims PASS on a manual rule without stating the observation is itself a defect.
