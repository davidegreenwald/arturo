SHELL := /bin/bash
.DEFAULT_GOAL := verify

.PHONY: verify generate test test-ui lint format hooks doctor profile \
        revert-check mutation install icon release release-signed clean

# The Definition of Done. One command: generate-idempotency + format + lint +
# build + unit tests. Exit 0 means done. CI runs exactly this.
verify:
	@scripts/verify.sh

# Regenerate the Xcode project from project.yml (must leave a clean tree).
# Run this after adding, moving, or deleting any source file.
generate:
	@scripts/generate.sh

# Fast unit suite alone (Swift Testing) — what the gate runs.
test:
	@scripts/verify.sh --tests-only

# Slow suites kept OUT of the fast gate: UI smoke + accessibility.
test-ui:
	@scripts/verify.sh --ui-only

lint:
	@swiftformat --lint . && swiftlint --strict

# Fix formatting in place. The usual remedy for a red `verify` on formatting.
format:
	@swiftformat .

# OPTIONAL. Installs a pre-commit hook that runs the full gate before every
# commit, and a pre-push hook that runs it again. This is a maintainer
# convenience, not a requirement — CI enforces the same gate either way, and
# installing it replaces any global core.hooksPath you already have.
hooks:
	@scripts/install-hooks.sh

# Environment check: Xcode version, tools, signing posture, sandbox caveats.
doctor:
	@scripts/doctor.sh

# Tier-2 profiling: record Time Profiler headlessly, export XML, summarize to
# traces/summary.json. Needs a non-sandboxed terminal with Developer Tools TCC
# access. Maintainer tool — never part of the gate.
profile:
	@scripts/profile.sh

# Regenerate the app icon PNGs from scripts/make-app-icon.swift (the asset
# catalog's Contents.json already points at them).
icon:
	@TMPDIR="$(PWD)/.build/tmp" swift scripts/make-app-icon.swift Sources/Resources/Assets.xcassets/AppIcon.appiconset

# Build Release, ad-hoc sign, and install to /Applications so the app launches
# from Finder, the Dock, or Spotlight. This is also the upgrade command.
install:
	@scripts/install.sh

# Build, Developer ID-sign, notarize, and staple a distributable DMG.
# Maintainer only; needs a Developer ID identity plus notary credentials.
# See docs/distribution.md.
release:
	@scripts/release.sh

# Same pipeline without notarizing. Proves the build and signing path, and
# deliberately leaves an artifact Gatekeeper refuses until a ticket is stapled.
release-signed:
	@scripts/release.sh --skip-notarize

# Prove a regression test actually dies when its fix is reverted.
# Usage: make revert-check FILE=<path> FILTER=<test-filter>
revert-check:
	@test -n "$(FILE)" -a -n "$(FILTER)" || { \
		echo "Usage: make revert-check FILE=<path> FILTER=<test-filter>" >&2; exit 2; }
	@scripts/revert-check.sh "$(FILE)" "$(FILTER)"

# Optional, scheduled, never in the fast gate. Requires muter: brew install muter
mutation:
	@muter run

clean:
	@rm -rf .build Generated traces
	@git clean -fdX -- '*.xcodeproj'
