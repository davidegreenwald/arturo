#!/usr/bin/env bash

set -euo pipefail

# revert-check.sh ==============================================================
# What it does:
# - Factor 14 (lightweight form): proves a regression test can fail.
#   Reverts the most recent commit that touched FILE, expects the named test
#   to go RED, restores FILE, expects the test to go GREEN again.
#
# Requirements:
#   - git, xcodebuild; a committed bug fix with its regression test.
#
# Conventions:
#   TEST_FILTER uses AppTest targeting: "SuiteName" or "SuiteName/testName".
#   Run from a clean tree for the touched file.

## Help ========================================================================

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ] || [ $# -lt 2 ]; then
    cat <<'HELP'
Prove a regression test dies on revert of its fix.

Usage: revert-check.sh <file> <test-filter>

Arguments:
  file          source file whose latest commit is reverted for the red check
  test-filter   -only-testing filter under AppTests, e.g. "SlideshowModelTests"

Example:
  make revert-check FILE=Sources/Features/Slideshow/SlideshowModel.swift FILTER=SlideshowModelTests
HELP
    exit 0
fi

## Configuration ===============================================================

TARGET_FILE="$1"
TEST_FILTER="$2"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

## Script ======================================================================

# Guard: refuse on a dirty working tree for the target file — the revert dance
# needs a known starting state.
if ! git diff --quiet HEAD -- "${TARGET_FILE}"; then
    echo "✗ ${TARGET_FILE} has uncommitted changes — commit or stash first" >&2
    exit 2
fi

FIX_COMMIT="$(git log -1 --format=%H -- "${TARGET_FILE}")"
if [ -z "${FIX_COMMIT}" ]; then
    echo "✗ no commit found touching ${TARGET_FILE}" >&2
    exit 2
fi

restore() {
    git checkout -- "${TARGET_FILE}"
}
trap restore EXIT

echo "— revert-check: ${TARGET_FILE} @ ${TEST_FILTER} —"

# RED: reverse the fix commit's changes to this file, expect failure.
echo "[1/4] reverting fix (${FIX_COMMIT:0:8}) for ${TARGET_FILE}"
git show "${FIX_COMMIT}" -- "${TARGET_FILE}" | git apply -R --

echo "[2/4] expecting RED..."
if xcodebuild \
    -scheme Arturo \
    -destination 'platform=macOS' \
    -derivedDataPath .build/DerivedData \
    -quiet \
    test \
    -only-testing:"AppTests/${TEST_FILTER}" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO > /dev/null 2>&1; then
    echo "✗ test PASSED without the fix — it does not actually cover the behavior" >&2
    exit 1
else
    echo "✓ RED confirmed: test fails on reverted fix"
fi

# GREEN: restore the fix, expect success.
echo "[3/4] restoring fix"
restore
trap - EXIT

echo "[4/4] expecting GREEN..."
if xcodebuild \
    -scheme Arturo \
    -destination 'platform=macOS' \
    -derivedDataPath .build/DerivedData \
    -quiet \
    test \
    -only-testing:"AppTests/${TEST_FILTER}" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO > /dev/null 2>&1; then
    echo "✓ GREEN confirmed: test passes with the fix"
else
    echo "✗ test FAILED even with the fix — flaky or wrong filter" >&2
    exit 1
fi

echo "✓ revert-check passed: the test can fail"
