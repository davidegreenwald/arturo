# ADR-100: Viewer behaviour — pages, fit, and when the screen is claimed

**Status:** Accepted · **Date:** 2026-10-23 (point 2 amended by adr-101: fill is an opt-in crop, and by adr-103: full bleed, no shadow, dark canvas; point 3 superseded by adr-102: the viewer launches blank)

## Context

Arturo is a reader for a folder, not a library. Four behaviours had more than
one defensible answer, and each one changes what the user sees within a second
of pressing a key: how far an arrow skips, whether an image may be cropped to
fill its column, when the window enters full screen, and whether changing the
dwell time interrupts the current one.

## Decision

1. **A skip moves one page, not one image.** `→` advances by the number of
   visible columns, wrapping modulo the folder. With three across, all three
   photographs change together; with one across, it is one at a time. The timer
   restarts at the moment of the skip.
2. **Images are fitted, never cropped** (see adr-101 for the opt-in fill mode). Each photograph keeps its aspect ratio
   inside its column and letterboxes against the canvas. The stage is 1, 2 or 3
   equal columns, capped at the folder's size, so a two-photo folder shows two
   full-height halves rather than three with a gap.
3. **Full screen is claimed when a folder is opened, and only then.** (There is
   no restored session at all since adr-102.)
4. **A dwell-time change applies to the next rotation.** The running sleep is
   not interrupted; the new value is read when the next sleep begins.

## Consequences

Arrow keys mean "next set", which is unambiguous while all visible images change
together, but a user hunting for one specific photograph must page rather than
nudge — acceptable because the position readout names the exact folder indices.
Fitted images leave canvas visible on portrait photographs; that canvas is the
token `DS.Color.canvas`, deliberately near-neutral so it cannot tint the picture.
The no-interrupt rule means the slider feels slightly lagging by design; it never
makes a photograph disappear sooner than it was promised to stay.

## Alternatives considered

- **Shift by one image per skip** — turns the three-up view into a filmstrip and
  makes "skip ahead" ambiguous between one image and one screen; rejected.
- **Cover-crop to fill each column** (mockup direction C) — fills the screen
  edge to edge but silently discards the top and bottom of every portrait;
  rejected as a default for a viewer whose job is to show the photograph.
- **Enter full screen at launch** — convenient for a kiosk, hostile for a
  desktop app that was just restored; rejected.
- **Restart the timer on every dwell-time adjustment** — makes the slider feel
  responsive at the cost of skipping an image the user was looking at; rejected.
