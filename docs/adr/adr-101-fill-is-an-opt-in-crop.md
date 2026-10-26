# ADR-101: Filling a frame is an opt-in crop

**Status:** Accepted · **Date:** 2026-10-23 · **Amends:** adr-100 §2

## Context

adr-100 decided that photographs are fitted, never cropped: a portrait
letterboxes rather than losing its top and bottom. That remains the correct
default for a viewer whose job is to show the photograph.

It is not the only thing a user wants. Three across on a 16:10 screen leaves
generous canvas above and below landscape shots, and someone browsing a folder
as a backdrop may prefer an edge-to-edge wall. The requirement, in the user's
words, is "Cinema Veil with the option to switch to filled instead of fitted".

The question is how to offer a crop without ever applying one by surprise.

## Decision

1. **Fit stays the default**, including on first launch and after any reset.
2. **Fill is a one-click chip in the transport pill**, not a third column
   segment and not a hidden preference — it sits next to the column count
   because both answer "how much of the stage does a photograph occupy?".
3. **Fill crops, and says so.** The chip's glyph changes from a dashed square to
   a filled one, its help text reads "Fill each frame, cropping the overflow",
   and the mode persists per user (`slideshow.fillsFrames`). The same toggle is
   in the View menu as ⌘⇧F.
4. **Filled tiles are clipped to their column.** The picture is larger than its
   column by definition; clipping is what keeps one photograph from painting
   over its neighbour.

## Consequences

The viewer can now produce a crop the user did not ask for — but only after that
user pressed a control whose tooltip names the crop. Saving the choice means the
crop is still not silent: it was chosen once, visibly, and the chip stays lit.
Two rendering paths exist for the same tile (`scaledToFit` and `scaledToFill`),
so the visual difference between them is a supported distinction rather than an
accident, and a future theme can pick a different default only by superseding
this ADR.

## Alternatives considered

- **Third segment in the Across control** — conflates "how many" with "how
  rendered", and implies the two are peers; rejected.
- **Menu-only toggle** — invisible; the user would have to know it exists to
  find it; kept as a shortcut, not as the interface.
- **Fill by default with a fit option** — crops every photograph for someone
  who opened a folder to look at photographs; rejected on adr-100's own
  reasoning.
- **Per-tile aspect-preserving fill (no crop)** — that is just fit; the words
  would lie.
