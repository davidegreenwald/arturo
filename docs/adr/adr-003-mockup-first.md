# ADR-003: Mockup-first for user-facing changes

**Status:** Accepted · **Date:** 2026-08-25

## Context
The fastest way to converge on the right UI is to iterate in HTML before any
Swift exists. Restyling a self-contained mockup costs minutes; restyling shipped
SwiftUI costs a pull request, a review cycle, and often a second one. The medium
was proven while building Arturo: three visual directions exist as static HTML
and one was implemented.

## Decision
Any change to what the user SEES starts as a self-contained HTML mockup,
presented for agreement BEFORE implementation:

- Self-contained single file: no network requests, no build step, no
  dependencies.
- Light AND dark where colour matters.
- Get agreement in the issue or pull request before implementing. No agreement,
  no implementation.
- Promotion replaces literal CSS values with DesignSystem tokens — the mockup is
  the specification, the tokens are the realization.
- Keep the mockups directory out of version control if you prefer to work
  privately, or commit it if the design history is worth keeping. Decide per
  project and be consistent.

This applies to user-visible changes only. A refactor, a test, or a decoder
change does not need a mockup.

## Consequences
A small recurring artifact cost buys the removal of the most expensive class of
surprise: shipped-but-wrong visuals. The cost is real for small tweaks — a
one-line label change still wants a mockup if the label is user-visible, and
that can feel disproportionate. Reviewers should apply judgement on trivial
copy edits.

## Alternatives considered
Figma or design tools — rejected for this workflow: not diffable text, not
reviewable in a pull request, not editable without the tool. Prose-only
agreement — rejected: prose hides exactly the layout and spacing surprises a
mockup exposes.
