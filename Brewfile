# Build toolchain — install with: brew bundle
#
# Homebrew has no durable pin channel for these three tools, so
# `brew bundle` always installs the current version. If a formula update
# breaks the gate, `brew pin <formula>` is a local stopgap, and this file
# should record the reason.

brew "xcodegen"
brew "swiftlint"
brew "swiftformat"

# Not brew-managed: muter (optional mutation testing, `make mutation`).
# `muter` presence is optional — doctor reports it, and nothing in
# `make verify` depends on it.
