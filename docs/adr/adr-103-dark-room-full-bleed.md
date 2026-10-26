# ADR-103: A dark room, full bleed, and no shadow

**Status:** Accepted · **Date:** 2026-10-24 · **Amends:** adr-100 §2 (framing)

## Context

The viewer shipped with three framing habits inherited from the mockup rather
than chosen for the product: an 8 pt margin between the photographs and the
window edge, a soft drop shadow under each fitted photograph, and an adaptive
canvas that turned near-white in the light system appearance.

Watching real photographs changed all three. The margin meant a slideshow never
filled its own window. The shadow implied the photographs were cards resting on a
surface — they are not; they are the surface. And the light canvas put a bright
field around low-key images, which is the one thing a light table is for and a
viewer must not do.

## Decision

1. **Full bleed.** No margin between a photograph and the window edge. A gutter
   exists only *between* tiles, so the stage is flush at 1, 2, and 3 across.
2. **No shadow.** Neither fitted nor filled photographs cast one. The canvas
   separates them from the room; nothing else is needed.
3. **The canvas is near-black in both system appearances** (`DS.Color.canvas` is a
   constant `#0B0B0B`-ish value, no dynamic provider). The window opts into dark
   chrome so the material, the transport pill, and the empty state all resolve
   against the canvas instead of against a white window.
4. **Hold time starts at half a second.** The range is 0.5–30 s in half-second
   steps; the pill reads `0.5s`, `1s`, `1.5s`. The floor is not zero: a hold of
   nothing is a flicker, not a slideshow.

## Consequences

Photographs now reach the edges of the window for the first time, which is what
"full screen" was supposed to mean. The app no longer follows the system
appearance, so a user in light mode gets a dark viewer — intentional for a photo
viewer, and the same posture as Quick Look and most media apps. Fitted images
still letterbox, but against black rather than paper, so the letterbox reads as
absence instead of as a mount.

The one visible cost: the folder label now sits on top of a photograph instead of
on empty canvas, so it carries a text shadow to stay legible.

## Alternatives considered

- **Keep the adaptive canvas, margin, and shadow** — the mockup's default, and
  wrong for the medium; rejected.
- **Margin but no shadow** — still refuses to fill the window; rejected.
- **Dark canvas only in the dark appearance** — leaves light-mode users with the
  washed-out version; rejected.
- **Hold floor of 0 s** (or 0.25 s) — indistinguishable from a broken timer at
  large folders; half a second is the fastest speed that still reads as a
  slideshow.
