# UX shape specs

Durable, per-surface UX contracts — the *shape* a surface must have (window chrome, panes,
fields, columns, actions, menu structure, and empty / loading / error / permission states),
independent of visual styling. Cited from feature specs and task `Reading list` / `Refs`.

## Why separate from feature specs

A feature spec says *what* a feature does; a UX shape spec says *how a surface is laid out* —
reused across features and evaluated mechanically. Keeping them apart lets `/said:review-ux`
check a surface against a stable contract and `/said:uxtoc` outline a spec for fast iteration.

## Files (author per your product)

One file per surface archetype. A common set for a macOS app:

- `shell.md` — app shell: activation policy, window inventory, toolbar conventions, what the
  app looks like with zero windows open
- `menubar.md` — status item behaviour, menu structure, key equivalents, the crowded-menu-bar
  and no-dock-icon cases
- `settings.md` — the Settings window: pane inventory, grouping, immediate-apply rule,
  restart-required settings, reset scope
- `lists.md` — list / table surfaces: columns, sorts, filters, row actions, selection
  behaviour, empty state
- `form.md` — detail and edit surfaces: field grouping, validation surface, commit and
  destructive-action patterns
- `errors.md` — error, empty, loading, and **permission** states (pairs with ADR-SWIFT-S09 and
  the permission block of the UX gate)
- `fields.md` — field-type rendering conventions (paths, keystrokes, durations, toggles)

The template ships this README plus the mechanical checklist
([`../qa/feature-ux-checklist.md`](../qa/feature-ux-checklist.md)); author concrete surface
specs as the product takes shape — they are inherently project-specific.

## Rules

- A UX spec is descriptive **shape**, not visual styling.
- Every interactive surface has explicit **empty / loading / error** states, and every
  permission-gated one has an explicit **not-yet-granted** state with a recovery route
  (ADR-SWIFT-S09 rule 6).
- Shape decisions are stated in platform terms — window, panel, sheet, popover, menu — because
  the choice between them *is* the decision. "A dialog" is not a shape.
- Frozen decisions get a number so tasks can cite them (e.g. `shell.md frozen #8`).
- A spec describes one surface. If it needs a second heading level for a different window, it
  is two specs.
