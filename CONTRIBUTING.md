# Contributing to Arturo

Thanks for looking. This file is the fast path from a fresh clone to a green
build, plus the conventions that keep the codebase coherent.

## Requirements

- macOS 26 or later, and Xcode 26 or later to build. Xcode 26 wants a host of
  macOS 26.2 or later, so in practice that is the build floor.
- Homebrew, for the build toolchain.

```sh
brew bundle   # xcodegen, swiftlint, swiftformat
make doctor   # confirms your environment meets the floor
```

If `make doctor` fails, fix that first — everything below assumes it passes.

## Get to green

```sh
git clone https://github.com/davidegreenwald/arturo.git
cd arturo
brew bundle
make generate   # writes Arturo.xcodeproj from project.yml
open Arturo.xcodeproj    # optional: build and run from Xcode
make verify     # the gate — should be green before you change anything
```

That last step matters. Confirming the gate is green *before* you touch anything
is how you tell your change from a pre-existing problem.

## The one command that decides "done"

```sh
make verify
```

It runs, cheapest first: generator idempotency, `swiftformat --lint`,
`swiftlint --strict`, a build, then the unit test suite. Exit 0 means done. CI
runs exactly this on every push and pull request.

If it fails on formatting, `make format` usually fixes it.

Slow lanes stay out of the gate on purpose:

| Command | What it does |
|---|---|
| `make test-ui` | UI smoke suite. Slower, and needs an ad-hoc signature. |
| `make revert-check FILE=… FILTER=…` | Proves a regression test actually fails without its fix. |
| `make mutation` | Optional mutation testing via `muter`. |
| `scripts/bench-folder-scan.sh --files N --max-ms M` | Times the folder scan against a synthetic corpus. Maintainer tool — see [performance-baseline.md](docs/performance-baseline.md). |

### Project structure is generated

`project.yml` is the only source of truth for targets, files, and settings.
`Arturo.xcodeproj` and `Generated/` are build outputs and are gitignored.

- **Never hand-edit `Arturo.xcodeproj`.** It is regenerated and your edit is lost.
- **After adding, moving, or deleting a file, run `make generate`.** XcodeGen
  discovers sources by directory, so a new file is not in the project until you
  regenerate.
- Keep the two deployment floors in step: `project.yml` sets it for the app, and
  `Packages/DesignSystem/Package.swift` sets it for the package. If they drift,
  the build fails with a deployment-target mismatch.

## House conventions

These are not preferences. They are the shapes the codebase already has, and
matching them is what makes a change reviewable.

### SwiftUI first, AppKit behind three named seams

SwiftUI by default. AppKit is permitted only in `Sources/App/Bridges/`, one
concern per file, for these three things:

- `FolderPanelBridge` — `NSOpenPanel`, the only system-vetted folder picker
- `FullScreenBridge` — the full-screen transition, not expressible in SwiftUI
- `KeyboardMonitorBridge` — a local `NSEvent` monitor, because `.onKeyPress`
  depends on focus and a focused `Slider` eats the arrow keys

Adding AppKit anywhere else is a review-blocking change unless it comes with an
ADR explaining why.

### Design tokens, not literals

Colour, spacing, and type come from `Packages/DesignSystem`. Do not hardcode a
hex value or a magic padding number in a view. That package imports nothing from
the app — the dependency arrow points one way only, and SPM enforces it.

### State

`@Observable` models, constructor-injected, Environment-scoped. No other
architecture without an ADR.

### Tests

Swift Testing, not XCTest, for unit tests. Red before green: write the test from
the acceptance criteria and confirm it fails before the fix lands. If you wrote
the test after the change, revert the change and check the test goes red —
otherwise you do not know it can fail.

Prefer deterministic tests over timing-dependent ones. The rotation loop is
tested with an injected clock in `RotationLoopTests` precisely because wall-clock
timers are unreliable under App Nap.

### Accommodative detail that matters here

- Decoding is off the main actor and at display size, never at full resolution.
  Keep it that way.
- The image cache is bounded by frame count, not bytes.
- Nothing writes to disk. Arturo is read-only, and a change that copies, moves,
  or edits a photograph needs a very good reason.

## User-visible changes

If the user will see it, agree the look before writing the Swift. A
self-contained HTML mockup is cheap to iterate on; shipped SwiftUI is not. Open an
issue or a draft pull request with the proposal first. See
[ADR-003](docs/adr/adr-003-mockup-first.md).

This applies to real surface changes, not to a one-word copy fix.

## Pull requests

1. One concern per pull request. A refactor and a behaviour change in the same
   diff are two reviews pretending to be one.
2. `make verify` green, pasted or linked in the description.
3. Say what you changed and why. If you made a tradeoff, name the alternative you
   rejected — that is the part reviewers actually need.
4. If your change alters behaviour a reasonable person might disagree with, add
   an ADR in `docs/adr/`, following the format in
   [ADR-000](docs/adr/adr-000-adr-format.md).

## Reporting a bug

Three things, and the report is useful:

- **What happens**, and what you expected instead.
- **How to reproduce it** — ideally the folder characteristics (count, formats,
  sizes) since decoding is where most surprises live.
- **Your macOS version and how you installed Arturo** (built from source, or
  where you downloaded it).

## License

Contributions are accepted under the MIT license in [LICENSE](LICENSE). By
opening a pull request you agree your contribution is licensed the same way.
