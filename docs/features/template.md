# <FEAT>-<NN>: [Feature Name]

## Context to load alongside this spec
- `docs/ux/<spec>.md` — <why it applies>
- `docs/adr/ADR-SWIFT-<SXX|00X>-<topic>.md` — <why it applies>
- `<Product>/Features/<related>/` — <related code>
- `docs/features/<FEAT>-<NN>.tasks.md` — implementation log

(Load these before authoring or modifying code in this feature.)

## What & Why
**User Story:** As a [user], I want [goal] so that [benefit]
**Value:** [Why this matters]

## Requirements

### Functional Requirements
- [ ] [Core functionality requirement 1]
- [ ] [Core functionality requirement 2]

### UI Requirements
- [ ] Surface: [WindowName / Settings pane / menu bar item] — [what it shows, how the user reaches it]
- [ ] Shape: [window | panel | sheet | popover | menu | settings pane] — [why this one]
- [ ] State: [`@Observable` model owned by …; what the views read]
- [ ] Empty / loading / error states: [what each shows]
- [ ] Keyboard: [key equivalents, default and cancel buttons, Tab order notes]

### Platform Integration
- [ ] Frameworks touched: [framework — via which `Core/<Service>/` contract]
- [ ] Permissions required: [Accessibility / Automation / Screen Recording / none] — pre-flight
      copy + recovery route
- [ ] Concurrency: [what runs off the main actor; which callbacks hop]
- [ ] Settings keys added: [namespaced key — which store (ADR-SWIFT-S08)]
- [ ] Entitlements / Info.plist changes: [none, or which and why — R-GATE-SIGN applies]

### Performance
- [ ] [Main-thread budget, data volume, launch-time impact]

## Acceptance Criteria
```gherkin
Given [initial state]
When [user action]
Then [observable outcome]

And [additional condition]
Then [additional outcome]
```

## Definition of Done

See quality gates in `CLAUDE.md` (`R-GATE-*`, defined in `docs/qa/feature-qa-checklist.md`).
UI-touching work also passes `docs/qa/feature-ux-checklist.md` via `/said:review-ux`.

## Feature Tasks

<!-- Optional: for features that discover subtasks during implementation.
     Keep the summary table here; put the detailed log in a companion file.
     Create: <FEAT>-<NN>.tasks.md (same directory, same prefix).

| Task | Title | Status |
|---|---|---|
| <FEAT>-<NN>-01 | [Short title] | Todo / Done / Backlog / Canceled |

Detailed task log: [<FEAT>-<NN>.tasks.md](<FEAT>-<NN>.tasks.md)
-->

## Related
- **ADRs:** [relevant architectural decisions]
- **Features:** [dependent / related features]
- **Issues:** [tickets]
