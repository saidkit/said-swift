# ADR-SWIFT-XXX: [Decision Title]

**Date:** YYYY-MM-DD
**Status:** Proposed | Accepted | Rejected | Deprecated | Superseded by ADR-SWIFT-XXX
**Class:** System (portable across Swift / macOS app projects) | Project (this product)
**Context:** [feature-id / working-notes that drove this]

## Problem

[What needs to be decided, and why the obvious answer is wrong or insufficient. Keep it concrete — name the failure mode.]

**Context:**
- [Platform constraint — OS version, framework behaviour, sandbox/TCC, signing]
- [Technical constraint]
- [Product requirement]

## Decision

**[The decision, stated in one bolded sentence someone can act on.]**

[Layout / mechanism / diagram if the decision has a shape.]

## Rules

1. **[Rule name.]** [What must hold, and the failure mode if it doesn't.]
2. **[Rule name.]** [Code example when the rule is easier shown than stated.]

## Out of scope

- [What this ADR deliberately does not decide — with a pointer to the ADR that does.]

## Alternatives considered

| Option | Verdict |
|---|---|
| [The chosen option] | **Chosen** — [why] |
| [A plausible option] | Rejected — [why it fails *here*, specifically] |

> Keep alternatives a reader might plausibly have picked. Drop straw men.

## Consequences

**Positive:** [what gets easier or safer]

**Negative:** [what gets harder, what discipline this now requires, what it costs]

## Related

- **[Relationship]:** [ADR-SWIFT-SXX](ADR-SWIFT-SXX-topic.md) — [how they relate]
- **Instance / Overrides:** [project ADR that instantiates or contradicts this, if any]
- **Conventions:** [`../conventions.md`](../conventions.md)

---

## Template notes (delete when authoring)

- **macOS ADRs earn their keep at the platform seams** — permissions/TCC, signing and entitlements, main-thread and actor isolation, on-disk footprint, framework lifecycle. A decision that would read the same for any language probably belongs in `conventions.md`, not here.
- **One-way doors get called out explicitly** — bundle identifier, `CFBundleVersion` floor, entitlement grants, update-feed identity, public API surface. Say so in the Problem section.
- **Link, don't paraphrase.** If another ADR already decided something, cite it in one line.
- **Record what was rejected and why**, in the reader's terms — the value of an ADR is mostly in the options it closed.
