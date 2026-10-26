# ADR-000: ADR format and numbering

**Status:** Accepted · **Date:** 2026-08-25

## Context
Arturo keeps a decision record so that the reasons behind structural choices
survive longer than the conversation that produced them. ADRs must be
append-only, greppable, and stable to reference from code comments and pull
requests.

## Decision
Files are `docs/adr/adr-NNN-slug.md`, four-digit-padded, monotonic, append-only.
Format per file:

```markdown
# ADR-NNN: <decision title>
**Status:** Accepted | Proposed | Superseded by ADR-NNN · **Date:** YYYY-MM-DD
## Context   ## Decision   ## Consequences   ## Alternatives considered
```

Numbers are never reused and never renumbered. A decision that changes is not
edited away — a new ADR supersedes it and says so. Revisions that correct a
factually wrong premise in place are permitted and marked with a `Revised:`
date, so the correction is visible without losing the number.

Three-digit and higher numbers are ordinary decisions; there is no reserved
block.

## Consequences
Superseding means writing a new ADR that names its predecessor, so history is
never rewritten and the trail of *why* stays intact. The cost is that reading
the current state requires following the supersede chain rather than reading one
file.

## Alternatives considered
One rolling DECISIONS.md — rejected: no per-decision status lifecycle and
hostile to merging. Numberless slugs — rejected: ordering and reference
stability lost, and code comments could not cite a stable id.
