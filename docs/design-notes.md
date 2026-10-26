# Design notes

Why Arturo is built the way it is, for the parts where the code alone does not
explain the reasoning. Behavioural decisions are recorded as ADRs in
`docs/adr/`; this file carries the technical research and the choices that
followed from it.

## Decoding at display size

A slideshow of 24 MP photographs will exhaust memory if each frame becomes a
full-resolution bitmap. Arturo decodes with
`CGImageSourceCreateThumbnailAtIndex` plus
`kCGImageSourceCreateThumbnailWithTransform` — the documented ImageIO path for
producing a display-sized bitmap without ever materialising the full image, with
EXIF orientation applied during decode.

The decoder ceilings the longest edge at between 512 and 2600 px depending on
the display, and `ImageStore` caches at most 9 frames. That bounds memory to
roughly 145 MB steady and about 266 MB at the launch peak (six concurrent
decodes) at three columns, measured on a 32 GB Apple Silicon Mac with 6016x6016
sources. It is emphatically not "100 MB": the decoded frame is sized for the
worst-case aspect ratio a tile could hold, not the one the picture actually
needs, so a square photograph is decoded about 3x larger than it is drawn.

Those figures, the method behind them, and the reasons the ceiling was left
alone are recorded in [performance-baseline.md](performance-baseline.md).

`Tests/AppTests/ImageDecoderTests.swift` validates this against a real
1200×800 PNG: the decoded result is ≤ 400 px on its long edge and the landscape
orientation is preserved.

## Why AppKit appears at all

Three seams, each because SwiftUI cannot express the thing:

- **Folder choice** — `NSOpenPanel.runModal()` is the only system-vetted folder
  picker. SwiftUI has no equivalent. See `Sources/App/Bridges/FolderPanelBridge.swift`.
- **Full screen** — the transition is not expressible through SwiftUI's scene
  API, so a bridge calls `NSWindow.toggleFullScreen`. See
  `Sources/App/Bridges/FullScreenBridge.swift`.
- **Arrow keys** — `.onKeyPress` depends on focus, and a focused `Slider` eats
  the arrow keys. A local `NSEvent` monitor reduces the event to `Sendable`
  scalars before touching the main actor. See
  `Sources/App/Bridges/KeyboardMonitorBridge.swift`.

## Rotation arithmetic

`SlideshowModel.pageStart` advances by `columnCount`, and every read of it goes
through modulo arithmetic. That single choice makes the rotation infinite, makes
it reversible, and guarantees a last page that would be short simply wraps
instead of showing a hole.

Advancing by a page rather than by one image is a deliberate decision: with
three columns, ← and → change all three photographs together. With one column it
degrades naturally to one at a time. Shifting by a single image would turn the
three-up view into a filmstrip and make "skip ahead" ambiguous.

`Tests/AppTests/SlideshowModelTests.swift` covers the wrap in both directions.
The test was written from the acceptance criteria and confirmed to fail when the
modulo was replaced with plain addition.

## Folder scanning

`FolderScanner` is deliberately shallow and read-only. It never copies, imports,
or moves a photograph, and it does not recurse. Ordering uses
`localizedStandardCompare`, so `frame2` sorts before `frame10` — the ordering a
person expects, not byte order.

## Preferences, and what is deliberately not stored

`UserDefaults` holds three keys: `arturo.holdSeconds`, `arturo.columns`,
`arturo.fillsFrames`. That is the whole persistence surface.

The folder is not stored. Every launch starts blank, by design (ADR-102): the app
can never show photographs the user did not ask for, and it never seizes the
screen as a side effect of starting. `--folder <path>` opens a folder for one
launch only and is not remembered.

## Rotation cadence

SwiftUI's `task(id:)` owns the cadence, and the transport pill auto-hides on an
idle tick count. Changing the hold time applies to the next rotation rather than
interrupting the current sleep — that is what the approved mockup promised, and
it avoids a jarring mid-hold jump.

Wall-clock rotation is covered deterministically in
`Tests/AppTests/RotationLoopTests.swift` rather than in the UI lane, because App
Nap stretches timers for a backgrounded app under UI testing.

## Known gaps

- No performance-baseline tests and no signposts. ADR-005 documents this
  explicitly rather than implying coverage that does not exist.
