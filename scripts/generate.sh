#!/usr/bin/env bash

set -euo pipefail

# generate.sh ==================================================================
# What it does:
# - Regenerates Arturo.xcodeproj and Generated/Info.plist from project.yml.
# - Must leave a clean tree relative to two consecutive runs — the gate
#   (scripts/verify.sh) enforces the idempotency invariant.
#
# Requirements:
#   - xcodegen (see Brewfile)

## Help ========================================================================

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    cat <<'HELP'
Regenerate the Xcode project from project.yml.

Usage: generate.sh

The .xcodeproj is a generated artifact — never edit it directly, and never
commit it (it is gitignored). Edit project.yml, rerun this, commit project.yml.

Example:
  scripts/generate.sh
HELP
    exit 0
fi

## Script ======================================================================

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

if ! command -v xcodegen > /dev/null 2>&1; then
    echo "✗ missing requirement: xcodegen — run 'brew bundle' (see Brewfile)" >&2
    exit 2
fi

echo "Regenerating project from project.yml"
xcodegen generate
echo "Done. If you changed structure (files/targets/deps), run 'make verify'."
