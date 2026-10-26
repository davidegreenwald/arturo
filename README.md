# Arturo

A minimal full-screen photo slideshow viewer for macOS. Point it at a folder of
photographs and it plays them, up to three side by side, rotating forever, with
nothing on screen but the pictures and a transport pill that hides itself.

![Arturo showing three photographs side by side: a vertical waterfall centred between a dog on a beach and a mountain reflected in a lake](docs/screenshots/hero.jpg)

Three photographs, one page, fit to their columns at their own aspect ratios.
The transport pill had already hidden itself.

## Requirements

macOS 26 or later. To build it, Xcode 26 or later — which needs macOS 26.2 or
later to install, since that is Xcode's own minimum host.

## Install

Download the latest release and drag Arturo into Applications:

**<https://github.com/davidegreenwald/arturo/releases/latest>**

1. Open `Arturo-1.0.0.dmg`.
2. Drag `Arturo.app` into `/Applications`.
3. Launch it and press **⌘O** to choose a folder.

The release build is signed with a Developer ID certificate and notarized by
Apple, so it opens without a Gatekeeper warning. Nothing is copied, imported, or
edited on disk.

Homebrew is not set up yet; a cask is planned once the project has been public
for a while.

### Build from source

```sh
git clone https://github.com/davidegreenwald/arturo.git
cd arturo
brew bundle          # xcodegen, swiftlint, swiftformat
make install         # Release build, ad-hoc signed, copied to /Applications
open -a Arturo
```

`make install` is also the upgrade command: it quits a running copy, replaces
the bundle, and re-registers it with LaunchServices. If `/Applications` is not
writable it falls back to `~/Applications`.

Press **⌘O**, choose a folder, and the window takes the screen.

Reads the formats ImageIO decodes: **HEIC/HEIF**, JPEG, PNG, TIFF, WebP, AVIF,
GIF, and BMP. An iPhone folder plays as-is, EXIF orientation applied, decoded at
display size rather than at full resolution. RAW is deliberately excluded — it
decodes unevenly across machines, and a slideshow that silently skips half a
folder is worse than one that never claimed the format.

### Start a folder without the panel

```sh
open -a Arturo --args --folder ~/Pictures/2024\ 12\ mobile
```

`--folder <path>` opens that folder for this launch only. It is how scripts and
the UI tests start a show; it is not remembered.

## What it does

| Behaviour | How |
|---|---|
| Up to three photographs side by side, full screen | ⌘O, then the window takes the screen |
| Pause and play | transport toggle, or `space` |
| Infinite rotation | wraps in both directions, so ← from the first page lands on the last |
| Dwell time | slider, 0.5–30 s in half-second steps, remembered |
| Fit or fill each frame | Fill chip or ⇧⌘F, remembered |
| Skip a page | ← and → |
| Leaf full screen | `esc` |

![Arturo showing three landscape photographs across the window, with the transport pill visible: pause, page skips, column count, fill toggle, hold time, and position](docs/screenshots/transport.jpg)

The transport pill: page skips either side of play/pause, then the column count,
the fill toggle, the hold-time slider, and the position. It fades after 2.4 s of
playback and returns on hover; pausing keeps it on screen. The photographs are the
interface, so the controls get out of the way.

Column count, hold time, and fill mode are remembered between launches. The
folder is not: every launch starts blank, and a folder is opened only when you
ask for one.

## Design decisions worth knowing

- **Pages, not single images.** → advances one full page, so all visible
  photographs change together; with one column that is one photograph at a time.
- **The photographs are the surface.** Full bleed to the window edge, a gutter
  only between tiles, no drop shadow, and a fixed near-black canvas in both
  system appearances — a light room would wash out a low-key photograph.
- **Fit by default, fill on request.** An image letterboxes inside its column and
  keeps its own aspect ratio; a portrait is not trimmed to a landscape hole. The
  Fill chip covers the column edge to edge and crops instead — opt-in, labelled,
  and remembered.
- **Blank on launch, always.** Nothing from the previous session reopens. The
  app never seizes the screen as a side effect of starting.
- **Decode at display size.** ImageIO thumbnails, off the main actor, bounded to
  nine cached frames — a 24 MP JPEG never becomes 96 MB of pixels.
- **Read-only.** Arturo never copies, imports, moves, or edits a photograph.

More on the reasoning in [docs/design-notes.md](docs/design-notes.md) and the
[ADRs](docs/adr/).

## Contributing

Bug reports, feature ideas, and pull requests are welcome. Start with
[CONTRIBUTING.md](CONTRIBUTING.md) — it covers the clone-to-green path, the
one-command gate, and the house conventions.

The short version:

```sh
make generate   # project.yml -> Arturo.xcodeproj
make verify     # the Definition of Done: format, lint, build, unit tests
```

`Arturo.xcodeproj` is generated and not tracked. `project.yml` is the source of
truth for project structure — never hand-edit the project file.

## Layout

| Path | What it is |
|---|---|
| `project.yml` | The only structure truth; `.xcodeproj` is generated |
| `Sources/App/` | App entry, actions, `AppDelegate`, AppKit bridges |
| `Sources/Features/Slideshow/` | Model, viewer, tiles, controls, decoding |
| `Packages/DesignSystem/` | Design tokens (canvas, hairline, counter type, tile radius) |
| `Tests/AppTests/` | Rotation contract, folder scanning, real ImageIO decode |
| `Tests/AppUITests/` | Slow lane: launch → empty state |
| `docs/adr/` | Decisions and why they were made |
| `docs/design-notes.md` | Decoding, AppKit seams, rotation arithmetic |

## Commands

| Command | Meaning |
|---|---|
| `make verify` | The Definition of Done: idempotency + format + lint + build + unit tests |
| `make test` | Fast unit suite alone |
| `make test-ui` | Slow UI smoke lane |
| `make install` | Release build → `/Applications/Arturo.app` (also the upgrade path) |
| `make generate` / `make format` / `make lint` | Structure, style, lint |
| `make doctor` | Environment check against the build requirements |
| `make icon` | Regenerate the app icon PNGs from `scripts/make-app-icon.swift` |

## Inspiration

*Sliders* ran on Fox from 1995 to 1997 and on the Sci-Fi Channel from 1998 to
2000. Its premise: a student named Quinn Mallory builds a device in his
basement, and it does not move things through space — it moves them sideways,
through parallel versions of the same Earth. Every slide lands somewhere
familiar and wrong. There is no way home. You keep looking.

Professor Maximillian Arturo, played by John Rhys-Davies, is Quinn's mentor and
one of the four original Sliders. He is the one who insists on understanding the
timer before using it, who works out the rules the others keep violating, and
who in the end trades his life for Quinn's. He is, in other words, the character
who takes the looking seriously.

So the name is a joke that happens to fit. A photo viewer is a slideshow. A show
about sliding between worlds is *Sliders*. And of the characters, Arturo is the
one you would trust to build a viewer that leaves your photographs exactly where
they are and asks nothing of them.

The obvious choice was Quinn, the protagonist, and it was the first choice here.
It was set aside on namespace grounds rather than taste: `quinn` is a widely used
QUIC library in Rust, there is a pending US software trademark on the word, and
there is already a photography company trading under it. Arturo is simply less
crowded.

No affiliation with the show, its creators, or its rights holders. Just an
homage from someone who watched it at the right age.

## License

MIT. See [LICENSE](LICENSE).
