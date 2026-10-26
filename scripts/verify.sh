#!/usr/bin/env bash

set -euo pipefail

# verify.sh ====================================================================
# What it does:
# - The Definition of Done gate (ADR-002). Exit 0 = done.
# - full mode (default): XcodeGen idempotency -> SwiftFormat lint ->
#   SwiftLint strict -> build -> unit tests (Swift Testing).
# - --tests-only: build + unit tests (fast iteration loop).
# - --ui-only: UI smoke suite only (slow; never part of the commit gate).
#
# Requirements:
#   - Xcode 26.x (pinned in .xcode-version)
#   - brew bundle (xcodegen, swiftlint, swiftformat — see Brewfile)
#
# Notes:
# - Builds and tests run unsigned (CODE_SIGNING_ALLOWED=NO, ADR-004).
# - TMPDIR is redirected inside the repo because some sandboxed environments
#   deny writes to the system temp dir.

## Help ========================================================================

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    cat <<'HELP'
Run the quality gate for Arturo.

Usage: verify.sh [MODE]

Modes:
  (none)        Full gate: idempotency + format + lint + build + unit tests
  --tests-only  Build + unit tests only (fast iteration)
  --ui-only     Build + UI smoke suite only (slow; kept out of the commit gate)

Example:
  scripts/verify.sh
HELP
    exit 0
fi

## Configuration ===============================================================

MODE="full"
case "${1:-}" in
    "") ;;
    --tests-only) MODE="tests" ;;
    --ui-only) MODE="ui" ;;
    *)
        echo "Usage: verify.sh [--tests-only|--ui-only]" >&2
        exit 2
        ;;
esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

# Sandbox-safe temp dir: some environments deny writes to the system TMPDIR.
TMPDIR="${ROOT}/.build/tmp"
export TMPDIR
mkdir -p "${TMPDIR}"

DERIVED_DATA="${ROOT}/.build/DerivedData"
DESTINATION="platform=macOS"
BUDGET_SECONDS=120
START=$SECONDS

## Preflight ===================================================================

for tool in git xcodebuild swiftlint swiftformat; do
    if ! command -v "${tool}" > /dev/null 2>&1; then
        echo "✗ missing requirement: ${tool} — run 'brew bundle' (see Brewfile) or 'make doctor'" >&2
        exit 2
    fi
done

if ! command -v xcodegen > /dev/null 2>&1; then
    echo "✗ missing requirement: xcodegen — run 'brew bundle' (see Brewfile)" >&2
    exit 2
fi

banner() {
    printf '\n━━ %s ━━\n' "$1"
}

snapshot_hash() {
    # Hash every generated artifact; comparing two consecutive generations
    # proves determinism regardless of starting tree state.
    find Arturo.xcodeproj Generated -type f -print0 2> /dev/null \
        | sort -z \
        | xargs -0 shasum -a 256 2> /dev/null \
        | shasum -a 256 \
        | cut -d' ' -f1
}

run_xcodebuild() {
    # The fast lane builds unsigned (ADR-004). The UI lane cannot: the system
    # launches AppUITests-Runner itself and refuses an unsigned bundle
    # ("damaged and can't be opened"). Ad-hoc signing is local-only and keeps
    # the deferred-distribution posture intact.
    local signing=("CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO")
    if [ "${MODE}" = "ui" ]; then
        signing=("CODE_SIGNING_ALLOWED=YES" "CODE_SIGNING_REQUIRED=YES" "CODE_SIGN_IDENTITY=-")
    fi

    xcodebuild \
        -scheme Arturo \
        -destination "${DESTINATION}" \
        -derivedDataPath "${DERIVED_DATA}" \
        -quiet \
        "$@" \
        "${signing[@]}"
}

## Stage 1 — generation is idempotent (ADR-002) ================================

if [ "${MODE}" = "full" ]; then
    banner "generate ×2 — idempotency check"
    xcodegen generate > /dev/null
    HASH_ONE="$(snapshot_hash)"
    xcodegen generate > /dev/null
    HASH_TWO="$(snapshot_hash)"
    if [ "${HASH_ONE}" != "${HASH_TWO}" ]; then
        echo "✗ generation is NOT idempotent — project.yml or a generator bug changed output between runs" >&2
        exit 1
    fi
    echo "✓ two consecutive generates produced identical output"

    banner "swiftformat --lint"
    swiftformat --lint .

    banner "swiftlint --strict"
    swiftlint --strict --quiet
fi

## Stage 2 — build =============================================================

banner "xcodebuild build"
run_xcodebuild build
echo "✓ build green"

## Stage 3 — tests =============================================================

if [ "${MODE}" = "ui" ]; then
    banner "UI smoke suite (slow lane, ADR-002)"
    # A copy installed in /Applications shares this bundle id. A running
    # instance keeps the keyboard, so the test-launched build never receives the
    # key events the suite asserts on.
    pkill -x Arturo > /dev/null 2>&1 || true
    run_xcodebuild test -only-testing:AppUITests
else
    banner "unit tests (Swift Testing)"
    run_xcodebuild test -only-testing:AppTests
fi

## Summary =====================================================================

ELAPSED=$((SECONDS - START))
printf '\n'
if [ "${ELAPSED}" -gt "${BUDGET_SECONDS}" ]; then
    echo "⚠ verify green but took ${ELAPSED}s — budget is ${BUDGET_SECONDS}s (ADR-002); investigate before adding surface"
else
    echo "✓ verify green in ${ELAPSED}s"
fi
