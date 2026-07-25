# Feature specs

Feature specs and append-only task logs live here.

## File pattern

- `<FEAT>-<NN>.md` — feature spec (per [`template.md`](template.md))
- `<FEAT>-<NN>.tasks.md` — append-only task log (per [`template-tasks.md`](template-tasks.md))
- Sub-phased variant: `<FEAT>-<NN>-<slug>.md` (e.g. `INIT-02-signing.md`)

## Discover features

`ls docs/features/*.md` — the file list is the registry. No central index (no drift).

## Authoring

Feature authoring principles per the SAID workflow:

- **New feature**: `/said:architect <scope-path>` — Phase 2 generates spec + initial tasks log
  from a `scope.md`
- **New task on an existing feature**: `/said:add-task <feature-id> [bug] [priority=High|Medium|Low]`
- **Implement**: `/said:impl <task-id>` — drives Phase A (Classify + Inventory) → Phase B
  (Implement) → Phase C (Verify + close)

## Related

- [`template.md`](template.md) — feature-spec stencil
- [`template-tasks.md`](template-tasks.md) — task-log stencil + authoring discipline +
  working-folder-vs-task-body rule
- [`../adr/README.md`](../adr/README.md) — ADR registry (decisions + relationships)
- [`../ux/`](../ux/) — UX shape specs (shell / menubar / settings / lists / errors)
- [`../qa/feature-qa-checklist.md`](../qa/feature-qa-checklist.md) — the `R-GATE-*` definitions
