#!/usr/bin/env bash

set -euo pipefail

# doctor.sh ====================================================================
# What it does:
# - Environment check for building Arturo: Xcode floor, required tools, hook
#   installation, signing posture, and known sandbox/TCC caveats.
# - Fails on a toolchain below the floor; warns on optional gaps.
#
# Requirements:
#   - macOS 26.2+ (Xcode 26's own minimum host), Xcode 26.0+, git
#   - Optional: xcodegen/swiftlint/swiftformat (brew bundle), muter
#
# Note the single floor and how it is met: the app RUNS on macOS 26+, and
# BUILDING it needs Xcode 26, which will not run below macOS 26.2. The check
# below is about the build host.

## Help ========================================================================

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    cat <<'HELP'
Check this environment against the requirements for building Arturo.

Usage: doctor.sh

Exit status 0 when every required check passes; 1 otherwise. Warnings do not
affect the exit status.

Example:
  scripts/doctor.sh
HELP
    exit 0
fi

## Script ======================================================================

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

FAILURES=0
WARNINGS=0

check_required() {
    local label="$1"
    shift
    if "$@" > /dev/null 2>&1; then
        echo "✓ ${label}"
    else
        echo "✗ ${label}" >&2
        FAILURES=$((FAILURES + 1))
    fi
}

check_optional() {
    local label="$1"
    shift
    if "$@" > /dev/null 2>&1; then
        echo "✓ ${label}"
    else
        echo "⚠ ${label} (optional)" >&2
        WARNINGS=$((WARNINGS + 1))
    fi
}

echo "— doctor —"

# macOS version — build-host floor, set by Xcode 26's own minimum (26.2)
MACOS_VERSION=$(sw_vers -productVersion)
if [ "$(printf '%s\n' "26.2" "${MACOS_VERSION}" | sort -V | head -n 1)" = "26.2" ]; then
    echo "✓ macOS ${MACOS_VERSION} (build host)"
else
    echo "✗ macOS ${MACOS_VERSION} — building needs 26.2+, because Xcode 26 requires it (the app itself runs on 26+)." >&2
    FAILURES=$((FAILURES + 1))
fi

# Xcode presence + floor check. .xcode-version is a FLOOR, not an exact pin:
# a newer Xcode is fine, an older one is not.
check_required "xcodebuild selected ($(xcode-select -p 2> /dev/null || echo 'none'))" command -v xcodebuild
if command -v xcodebuild > /dev/null 2>&1; then
    FLOOR="$(head -n 1 .xcode-version | tr -d '[:space:]')"
    INSTALLED="$(xcodebuild -version 2> /dev/null | awk '/^Xcode/{print $2}')"
    if [ "$(printf '%s\n' "${FLOOR}" "${INSTALLED}" | sort -V | head -n 1)" = "${FLOOR}" ]; then
        echo "✓ Xcode ${INSTALLED} (floor ${FLOOR})"
    else
        echo "✗ Xcode ${INSTALLED} is older than the ${FLOOR} floor in .xcode-version" >&2
        FAILURES=$((FAILURES + 1))
    fi
fi

# Required tools
check_required "xcodegen" command -v xcodegen
check_required "swiftlint" command -v swiftlint
check_required "swiftformat" command -v swiftformat
check_required "git" command -v git

# Optional tools
check_optional "muter (optional mutation testing)" command -v muter
check_optional "shellcheck (script hygiene)" command -v shellcheck

# Hook installation (per-clone config)
HOOKS_PATH="$(git config core.hooksPath 2> /dev/null || true)"
if [ "${HOOKS_PATH}" = "scripts/hooks" ]; then
    echo "✓ git hooks point at scripts/hooks"
else
    echo "⚠ optional pre-commit hooks not installed — run: make hooks" >&2
    WARNINGS=$((WARNINGS + 1))
fi

# Signing posture. Local builds are unsigned by design (ADR-004), so a missing
# Developer ID identity is a warning here — `release.sh` enforces it as a hard
# failure. The point of this check is to answer "do I have it?" without a build.
echo "— signing —"
if security find-identity -v -p codesigning 2> /dev/null | grep -q "Apple Development"; then
    echo "✓ Apple Development identity present (on-device builds)"
else
    echo "⚠ no Apple Development identity — building is unaffected; on-device runs are not" >&2
    WARNINGS=$((WARNINGS + 1))
fi

if security find-identity -v -p codesigning 2> /dev/null | grep -q "Developer ID Application"; then
    DEV_ID=$(security find-identity -v -p codesigning 2> /dev/null \
        | grep "Developer ID Application" \
        | head -1 \
        | sed -n 's/.*"\(.*\)"/\1/p')
    DEV_ID_EXPIRY=$(security find-certificate -c "Developer ID Application" -p 2> /dev/null \
        | openssl x509 -noout -enddate 2> /dev/null \
        | cut -d= -f2)
    echo "✓ ${DEV_ID}"
    echo "  expires ${DEV_ID_EXPIRY} — G2 certificates are valid one year and must be renewed annually"
else
    echo "⚠ no Developer ID Application identity — distribution signing unavailable; see docs/distribution.md" >&2
    WARNINGS=$((WARNINGS + 1))
fi

# Profiling caveats: xctrace needs privileges that sandboxes deny
echo "ℹ profiling: run scripts/profile.sh from a normal Terminal (not a sandboxed agent shell); grant Developer Tools TCC if prompted"

printf '\n'
if [ "${FAILURES}" -gt 0 ]; then
    echo "doctor: ${FAILURES} required failure(s), ${WARNINGS} warning(s)" >&2
    exit 1
fi
echo "doctor: all required checks passed (${WARNINGS} warning(s))"
