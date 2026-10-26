# ADR-004: Signing and distribution — unsigned locally, Developer ID for release

**Status:** Accepted · **Date:** 2026-08-25 · **Revised:** 2026-10-24

## Context
Every developer who clones Arturo should be able to build and test it without an
Apple Developer account, so local builds must not require a signing identity.

At the same time, Arturo is distributed as a download rather than through the
Mac App Store, and that changes the signing requirement materially. Homebrew
applies the macOS quarantine attribute to every cask download — its own
documentation states it does so "so Gatekeeper performs these checks instead of
Homebrew bypassing them" — and the `--no-quarantine` escape hatch was deprecated
in Homebrew 5.0.0, disabled in 5.1.0, and removed entirely by 7.0.x. An unsigned
build is therefore blocked by Gatekeeper on first launch whether the user
downloads it in a browser or installs it with `brew`.

The earlier version of this ADR deferred signing because nothing distributed
binaries. That premise no longer holds.

## Decision
Two signing postures, deliberately different:

- **Local development, `make test`, `make verify`, and CI:** unsigned.
  `CODE_SIGNING_ALLOWED: NO` in `project.yml`, plus explicit flags in the
  scripts. No team ID, no certificate, no entitlement to obtain.
- **Distribution:** Developer ID Application certificate, Hardened Runtime
  enabled, secure timestamp, notarized by Apple, and the ticket stapled to the
  artifact. This runs in release automation with credentials supplied as CI
  secrets — never in the local gate.

`ENABLE_HARDENED_RUNTIME: YES` is set in `project.yml` base settings. It is
inert on unsigned builds and required on the distribution build, so there is no
reason to toggle it per configuration.

App Sandbox is **not** enabled. It is required only for Mac App Store
distribution. Arturo is unsandboxed, so it needs no file-access entitlement to
read a folder the user chooses. This does not bypass TCC: Desktop, Documents,
Downloads, iCloud Drive, and network volumes remain consent-gated by the system
for sandboxed and unsandboxed apps alike.

Full procedure, required credentials, and the release workflow live in
`docs/distribution.md`.

## Consequences
Contributors never need an Apple account, and the fast gate stays fast. The cost
is that the distribution path is not exercised by `make verify` — it is only
proven in release automation, which means a signing regression is found at
release time unless a release dry-run is performed.

The UI test lane cannot run unsigned: the system launches the test runner itself
and refuses an unsigned bundle, so that lane signs ad-hoc (`CODE_SIGN_IDENTITY:
"-"`). If `make test-ui` dies at launch while unit tests pass, that is the seam
to check first.

## Alternatives considered
Ad-hoc signing everywhere — near-zero cost, but it is configuration that rots
unnoticed and it does not satisfy notarization. Mac App Store distribution —
requires sandboxing, and a folder reader is a poor fit for store review and for
the app's "reads photos where they live" premise. Developer ID without
notarization — Gatekeeper still blocks it; notarization is the part users
experience.
