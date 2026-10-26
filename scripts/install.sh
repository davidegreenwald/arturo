#!/usr/bin/env bash

set -euo pipefail

# install.sh ===================================================================
# What it does:
# - Builds Arturo in Release, ad-hoc signs it, and copies the bundle to
#   /Applications (or ~/Applications when /Applications is not writable) so it
#   launches from Finder, the Dock, or Spotlight like any other app.
# - Replaces an existing installation; quits a running copy first.
#
# Requirements:
#   - Xcode 26.x (pinned in .xcode-version)
#   - xcodegen (brew bundle — see Brewfile)
#
# Notes:
# - Signing is ad-hoc and local (ADR-004: distribution signing stays deferred).
#   An unsigned bundle is refused by macOS 26 once it carries a quarantine flag,
#   and ad-hoc costs nothing.
# - TMPDIR is redirected inside the repo because some sandboxed environments
#   deny writes to the system temp dir.

## Help ========================================================================

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    cat <<'HELP'
Build and install Arturo for regular use.

Usage: install.sh

Installs to /Applications, falling back to ~/Applications. Deletes and replaces
any previous copy, so this is also the upgrade command.

Example:
  scripts/install.sh && open -a Arturo
HELP
    exit 0
fi

## Configuration ===============================================================

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

TMPDIR="${ROOT}/.build/tmp"
export TMPDIR
mkdir -p "${TMPDIR}"

APP_NAME="Arturo"

## Preflight ===================================================================

for tool in xcodebuild xcodegen; do
    if ! command -v "${tool}" > /dev/null 2>&1; then
        echo "✗ missing requirement: ${tool} — run 'brew bundle' (see Brewfile)" >&2
        exit 2
    fi
done

## Build =======================================================================

echo "Generating the project from project.yml"
xcodegen generate > /dev/null

echo "Building ${APP_NAME} (Release)"
xcodebuild \
    -scheme "${APP_NAME}" \
    -configuration Release \
    -destination "platform=macOS" \
    -derivedDataPath ".build/DerivedData" \
    -quiet \
    build \
    CODE_SIGNING_ALLOWED=YES \
    CODE_SIGNING_REQUIRED=YES \
    CODE_SIGN_IDENTITY=-

BUILT_APP="${ROOT}/.build/DerivedData/Build/Products/Release/${APP_NAME}.app"
if [ ! -d "${BUILT_APP}" ]; then
    echo "✗ build finished but ${BUILT_APP} is missing" >&2
    exit 1
fi

## Destination =================================================================

INSTALL_DIR="/Applications"
if [ ! -w "${INSTALL_DIR}" ]; then
    INSTALL_DIR="${HOME}/Applications"
    mkdir -p "${INSTALL_DIR}"
    echo "  /Applications is not writable — installing to ${INSTALL_DIR}"
fi

INSTALLED_APP="${INSTALL_DIR}/${APP_NAME}.app"

if pgrep -x "${APP_NAME}" > /dev/null 2>&1; then
    echo "Quitting the running copy"
    osascript -e "quit app \"${APP_NAME}\"" > /dev/null 2>&1 || true
    sleep 1
fi

echo "Installing to ${INSTALLED_APP}"
rm -rf "${INSTALLED_APP}"
ditto "${BUILT_APP}" "${INSTALLED_APP}"

if [ ! -d "${INSTALLED_APP}" ]; then
    echo "✗ copy failed: ${INSTALLED_APP} does not exist" >&2
    exit 1
fi

# Prove the bundle the system will launch is intact, signature included.
if ! codesign --verify --strict "${INSTALLED_APP}" > /dev/null 2>&1; then
    echo "✗ signature check failed for ${INSTALLED_APP}" >&2
    exit 1
fi

## Registration ================================================================

# The Debug build carries the same bundle id, so LaunchServices would happily
# resolve "open -a Arturo" to it. Retire that record and pin the installed
# copy, otherwise the freshly installed app is not the one that launches.
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
DEBUG_APP="${ROOT}/.build/DerivedData/Build/Products/Debug/${APP_NAME}.app"

if [ -x "${LSREGISTER}" ]; then
    if [ -d "${DEBUG_APP}" ]; then
        "${LSREGISTER}" -u "${DEBUG_APP}" > /dev/null 2>&1 || true
    fi
    "${LSREGISTER}" -f "${INSTALLED_APP}" > /dev/null 2>&1 || true
fi

echo "✓ installed: ${INSTALLED_APP}"
echo "  launch:    open -a ${INSTALLED_APP}"
echo "  reinstall: make install   (after any code change)"
