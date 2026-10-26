#!/usr/bin/env bash

set -euo pipefail

# install-hooks.sh =============================================================
# What it does:
# - OPTIONAL. Points this clone's git hooks at the versioned scripts/hooks/
#   directory (core.hooksPath), where pre-commit and pre-push run `make verify`.
#
# Requirements:
#   - git
#
# Notes:
# - core.hooksPath is per-clone config, so run this once after cloning.
# - This REPLACES any global core.hooksPath you already have; it does not chain
#   to it. If you rely on global git hooks, do not install these.
# - CI runs the same gate, so installing these is convenience, not a
#   requirement for contributing.

## Help ========================================================================

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    cat <<'HELP'
Install the commit-time enforcement hooks for this clone.

Usage: install-hooks.sh

Sets core.hooksPath to scripts/hooks (versioned in the repo). From then on,
every commit and push runs the verify gate; a red gate aborts the operation.

Example:
  scripts/install-hooks.sh
HELP
    exit 0
fi

## Script ======================================================================

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

for hook in scripts/hooks/pre-commit scripts/hooks/pre-push; do
    if [ ! -x "${hook}" ]; then
        echo "✗ expected versioned hook missing or not executable: ${hook}" >&2
        exit 1
    fi
done

git config core.hooksPath scripts/hooks
echo "✓ hooks installed: commits and pushes now run scripts/verify.sh"
