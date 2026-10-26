# Arturo

A minimal photo slideshow viewer for macOS. View up to three photos at once in full screen infinite rotation.

![Arturo showing three photographs side by side: a vertical waterfall centred between a dog on a beach and a mountain reflected in a lake](docs/screenshots/hero.jpg)

This app is free and open-source. Use it, fork it, suggest improvements.

## System Requirements

- Install the DMG application: macOS 26 or later.
- Build from source: macOS 26 or later, with Xcode 26 or later.

## Install

Download the latest release and drag Arturo into Applications:

**<https://github.com/davidegreenwald/arturo/releases/latest>**

1. Open the download: you'll see `Arturo.app` and an `Applications` folder.
2. Drag `Arturo.app` into `/Applications`.
3. Launch it and press **⌘O** to choose a folder.

The release build is signed with a Developer ID certificate and notarized by
Apple, so it opens without a Gatekeeper warning.

Supported image formats: **HEIC/HEIF**, JPEG, PNG, TIFF, WebP, AVIF,
GIF, and BMP. An iPhone folder plays as-is, EXIF orientation applied, decoded at
display size rather than at full resolution.

## Privacy

Arturo shows the folder you pick and nothing else.

- Nothing leaves your Mac. No network calls, no telemetry, no analytics, no account.
- Your photographs are only read and displayed. Nothing is copied, moved, renamed, or edited.
- Three settings are remembered: how many photos across, how long each page
  shows, fit or fill.

The first time you open a folder in Desktop, Documents, Downloads, or iCloud
Drive, macOS asks your permission. That is the system protecting those folders,
not Arturo asking for more than it needs.

## Controls and usage

![Arturo showing three landscape photographs across the window, with the transport pill visible: pause, page skips, column count, fill toggle, hold time, and position](docs/screenshots/transport.jpg)

Open a folder from the app's landing page button, or from the command line:

```sh
open -a Arturo --args --folder ~/Pictures/2024\ 12\ mobile
```

Use the transport pill or keyboard shortcuts to control the image count, slideshow speed, pause/play, or fit the images to the screen.

| Behaviour | How |
|---|---|
| Open a folder | ⌘O, or `o` |
| Pause and play | transport toggle, or `space` |
| Infinite rotation | Default behavior. No controls. |
| Display time | slider, 0.5–30 s in half-second steps |
| Fit or fill each frame | Fill chip in the transport pill, or ⇧⌘F |
| Skip a page | ← and → |
| Enter or leave full screen | `f` |
| Leave full screen | `esc` |

---

## For technical users and contributors

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

### Contributing

Bug reports, feature ideas, and pull requests are welcome. Start with
[CONTRIBUTING.md](CONTRIBUTING.md) — it covers the clone-to-green path, the
one-command gate, and the house conventions.

```sh
make generate   # project.yml -> Arturo.xcodeproj
make verify     # the Definition of Done: format, lint, build, unit tests
```

`Arturo.xcodeproj` is generated and not tracked. `project.yml` is the source of
truth for project structure—never hand-edit the project file.

### Project Layout

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

### Commands

| Command | Meaning |
|---|---|
| `make verify` | The Definition of Done: idempotency + format + lint + build + unit tests |
| `make test` | Fast unit suite alone |
| `make test-ui` | Slow UI smoke lane |
| `make install` | Release build → `/Applications/Arturo.app` (also the upgrade path) |
| `make generate` / `make format` / `make lint` | Structure, style, lint |
| `make doctor` | Environment check against the build requirements |
| `make icon` | Regenerate the app icon PNGs from `scripts/make-app-icon.swift` |

---

## Inspiration

**Arturo** is named after Maximillian Arturo—the prickly professor from 1990s television classic *Sliders*.

> Where the devil are we, Mr. Mallory?

## License

The code is MIT. See [LICENSE](LICENSE).

The screenshots in this README, and the photographs in them, are © 2026
[David Greenwald](https://www.davidgreenwald.com/), the author of this project,
licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).
