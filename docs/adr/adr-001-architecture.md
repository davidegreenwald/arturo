# ADR-001: Architecture — SwiftUI default, AppKit behind named seams

**Status:** Accepted · **Date:** 2026-08-25

## Context
Arturo is a single-window macOS app. Structure has to be diffable text that a
contributor can review in a pull request, not a hand-maintained project file
whose changes are invisible in a diff. UI investment should land where the
platform concentrates it, and there should be an obvious, narrow place for the
AppKit that SwiftUI genuinely cannot express.

## Decision
- **D1 Generation:** XcodeGen owns structure. `.xcodeproj` and `Generated/` are
  gitignored outputs regenerated deterministically from `project.yml`, and the
  gate proves regeneration is idempotent.
- **D2 Framework posture:** SwiftUI by default. AppKit only at these enumerated
  seams, all of which this app actually uses:
  - opening a folder (`NSOpenPanel`, in `Sources/App/Bridges/FolderPanelBridge.swift`)
  - full-screen and window chrome SwiftUI cannot express
    (`Sources/App/Bridges/FullScreenBridge.swift`)
  - global key handling (`NSEvent` local monitor, in
    `Sources/App/Bridges/KeyboardMonitorBridge.swift`)

  Bridges live in `Sources/App/Bridges/`, one concern per file. SwiftUI owns
  state, and frameworks never mix inside one component. A single `@Observable`
  model layer drives both sides.
- **D3 Deployment target:** macOS 26.0. One floor, not two: the app runs on
  macOS 26+, and macOS 26 is also what the build host and CI run, so the floor
  is runtime-testable rather than only compile-checked. Building still needs
  Xcode 26, which wants a macOS 26.2 host, but that no longer implies supporting
  an older OS than the one being developed on. Revisit if reach matters more
  than testing confidence: the code uses no API newer than macOS 15, so lowering
  the target is a one-line change plus a test pass on the older OS.
- **D4 State:** `@Observable` models, constructor-injected, Environment-scoped.
  Other architectures require an explicit ADR deviation.
- **D5 Persistence:** `UserDefaults` via a property wrapper. Arturo stores only
  display preferences (column count, hold time, fill mode). If a future feature
  needs more, choose the storage mechanism up front rather than growing one.
- **D6 Identity:** app name `Arturo`, bundle id `app.arturo.viewer`. The bundle
  id is permanent — changing it after release resets preferences, LaunchServices
  registration, and the notarization record for every existing user.
- **D7 DesignSystem:** a local SPM package at `Packages/DesignSystem`, carrying
  tokens only. It can later become a remote package if a second app needs it.

### The boundary the build enforces
Two arrows, both checkable:

1. **Module direction:** `Packages/DesignSystem` imports nothing from the app
   target. SPM enforces this — the package has no app dependency.
2. **Framework seam:** AppKit outside `Sources/App/Bridges/` is a review-blocking
   deviation. Swift has no standalone import-linter, so this one is enforced by
   review rather than by the build.

## Consequences
New UI inherits the system design language for free. The cost is that bridge
discipline is enforced by review only, and any deviation from these house
patterns has to be argued in an ADR rather than introduced quietly.

## Alternatives considered
AppKit-first — maximum control, forfeits the design-language flywheel and makes
the SwiftUI previews and tests harder to keep. Tuist — more machinery than a
single-target app needs. A third-party composable architecture — no problem
here large enough to justify it.
