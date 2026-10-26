#!/usr/bin/env bash

set -euo pipefail

# release.sh ===================================================================
# What it does:
# - Builds a universal Release archive of Arturo, signed with a Developer ID
#   Application certificate, hardened runtime on, secure timestamp attached.
# - Exports the signed app, wraps it in a DMG, signs the DMG, notarizes it with
#   the notary service, staples the ticket, and verifies the result.
#
# Requirements:
#   - Xcode 26.x (pinned in .xcode-version) with xcodebuild, codesign,
#     notarytool, stapler, spctl, lipo, hdiutil
#   - xcodegen (brew bundle — see Brewfile)
#   - A "Developer ID Application" identity in the login keychain
#     (see docs/distribution.md § Credentials)
#   - For notarization: a stored keychain profile created with
#       xcrun notarytool store-credentials arturo-notary \
#         --key AuthKey.p8 --key-id <KEY_ID> --issuer <ISSUER_ID>
#
# Notes:
# - --skip-notarize builds and signs only. The result is a valid Developer ID
#   signature that Gatekeeper still refuses, because the ticket is missing.
#   Use it to exercise the build and signing path before credentials exist.
# - Nothing here writes to the repository. All output goes to build/.

## Help ========================================================================

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    cat <<'HELP'
Build, sign, notarize, and staple a distributable Arturo DMG.

Usage: release.sh [OPTIONS]

Options:
  -h, --help            Show this help message and exit
  --skip-notarize       Build and sign only; do not submit to the notary service
  --profile <name>      Keychain profile name for notarization credentials
                        (default: arturo-notary)

Output:
  build/Arturo-<version>.dmg   signed, notarized, stapled — the shippable artifact
  build/Arturo.xcarchive       signed archive
  build/export/Arturo.app      exported signed app

Example:
  scripts/release.sh --skip-notarize          # prove the build and signing path
  scripts/release.sh                          # full release, requires credentials
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
SIGN_IDENTITY="Developer ID Application"
NOTARY_PROFILE="arturo-notary"
SKIP_NOTARIZE="false"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --skip-notarize)
            SKIP_NOTARIZE="true"
            shift
            ;;
        --profile)
            if [ -z "${2:-}" ]; then
                echo "Usage: release.sh [--skip-notarize] [--profile <name>]" >&2
                exit 2
            fi
            NOTARY_PROFILE="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Usage: release.sh [--skip-notarize] [--profile <name>]" >&2
            exit 2
            ;;
    esac
done

ARCHIVE_PATH="build/${APP_NAME}.xcarchive"
EXPORT_DIR="build/export"
EXPORTED_APP="${EXPORT_DIR}/${APP_NAME}.app"

## Preflight ===================================================================

echo "Checking toolchain"
for tool in xcodebuild xcodegen codesign xcrun spctl lipo hdiutil; do
    if ! command -v "${tool}" > /dev/null 2>&1; then
        echo "✗ missing requirement: ${tool} — run 'brew bundle' (see Brewfile)" >&2
        exit 2
    fi
done

# The identity is the one thing that cannot be generated locally. Prove it is
# present and has its private key before spending a build on it.
echo "Checking for a ${SIGN_IDENTITY} identity"
if ! security find-identity -v -p codesigning 2> /dev/null | grep -q "${SIGN_IDENTITY}"; then
    echo "✗ no '${SIGN_IDENTITY}' identity with a private key in any keychain" >&2
    echo "  Create one: docs/distribution.md § Credentials" >&2
    echo "  Check with: security find-identity -v -p codesigning" >&2
    exit 2
fi
echo "✓ identity present"

TEAM_ID=$(security find-identity -v -p codesigning 2> /dev/null \
    | grep "${SIGN_IDENTITY}" \
    | head -1 \
    | sed -n 's/.*(\([A-Z0-9]*\)).*/\1/p')
if [ -z "${TEAM_ID}" ]; then
    echo "✗ could not parse the team ID from the identity name" >&2
    exit 2
fi
echo "✓ team ${TEAM_ID}"

# A dirty tree means the artifact does not correspond to any commit.
if [ -n "$(git status --porcelain 2> /dev/null)" ]; then
    echo "✗ working tree is not clean — commit or stash before releasing" >&2
    git status --short >&2
    exit 2
fi
echo "✓ working tree clean"

if [ "${SKIP_NOTARIZE}" = "false" ]; then
    if ! xcrun notarytool history --keychain-profile "${NOTARY_PROFILE}" > /dev/null 2>&1; then
        echo "✗ notary credentials for profile '${NOTARY_PROFILE}' are missing or invalid" >&2
        echo "  Store them once:" >&2
        echo "    xcrun notarytool store-credentials ${NOTARY_PROFILE} \\" >&2
        echo "      --key AuthKey.p8 --key-id <KEY_ID> --issuer <ISSUER_ID>" >&2
        echo "  Or build and sign without notarizing: --skip-notarize" >&2
        exit 2
    fi
    echo "✓ notary credentials valid (profile ${NOTARY_PROFILE})"
fi

## Archive =====================================================================

echo "Regenerating the project from project.yml"
xcodegen generate > /dev/null

rm -rf "${ARCHIVE_PATH}" "${EXPORT_DIR}" "build/${APP_NAME}.dmg"

echo "Archiving ${APP_NAME} (Release, universal, hardened runtime)"
# CODE_SIGN_STYLE=Manual is required, not tidiness. The DesignSystem SPM package
# inherits automatic signing from the project, and forcing a Developer ID
# identity onto it fails with "conflicting provisioning settings" because
# automatic signing expects Apple Development. Manual applies the one identity
# to every target, the package included.
xcodebuild \
    -project "${APP_NAME}.xcodeproj" \
    -scheme "${APP_NAME}" \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -archivePath "${ARCHIVE_PATH}" \
    -quiet \
    CODE_SIGNING_ALLOWED=YES \
    CODE_SIGNING_REQUIRED=YES \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="${SIGN_IDENTITY}" \
    DEVELOPMENT_TEAM="${TEAM_ID}" \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    OTHER_CODE_SIGN_FLAGS="--timestamp --options runtime" \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO \
    archive

if [ ! -d "${ARCHIVE_PATH}" ]; then
    echo "✗ archive was not produced at ${ARCHIVE_PATH}" >&2
    exit 1
fi
echo "✓ archived"

## Export ======================================================================

echo "Exporting with method developer-id"
xcodebuild \
    -exportArchive \
    -archivePath "${ARCHIVE_PATH}" \
    -exportPath "${EXPORT_DIR}" \
    -exportOptionsPlist ExportOptions.plist \
    -quiet

if [ ! -d "${EXPORTED_APP}" ]; then
    echo "✗ export did not produce ${EXPORTED_APP}" >&2
    exit 1
fi
echo "✓ exported"

## Verify the signed app =======================================================

echo "Verifying the signature"
if ! codesign --verify --strict --verbose=2 "${EXPORTED_APP}" 2>&1 | tail -2; then
    echo "✗ signature verification failed" >&2
    exit 1
fi

echo "Checking the signing identity actually used"
codesign --display --verbose=2 "${EXPORTED_APP}" 2>&1 | grep -E "Authority|TeamIdentifier|flags" || true

# get-task-allow must be absent or notarization rejects the build.
echo "Checking for get-task-allow"
if codesign --display --entitlements - --xml "${EXPORTED_APP}" 2> /dev/null | grep -q "get-task-allow"; then
    echo "✗ com.apple.security.get-task-allow is present — notarization would reject this build" >&2
    exit 1
fi
echo "✓ no get-task-allow"

echo "Checking architectures"
ARCHS_FOUND=$(lipo -archs "${EXPORTED_APP}/Contents/MacOS/${APP_NAME}")
echo "  ${ARCHS_FOUND}"
case "${ARCHS_FOUND}" in
    *arm64*x86_64* | *x86_64*arm64*) echo "✓ universal" ;;
    *)
        echo "✗ expected arm64 and x86_64, got: ${ARCHS_FOUND}" >&2
        exit 1
        ;;
esac

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${EXPORTED_APP}/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "${EXPORTED_APP}/Contents/Info.plist")
echo "✓ version ${VERSION} (build ${BUILD})"

## DMG =========================================================================

DMG="build/${APP_NAME}-${VERSION}.dmg"

# Stage the volume before imaging it. A DMG containing only the .app leaves the
# user with a lone icon and no drag target, so they have to open a second Finder
# window and hunt for /Applications. The Applications symlink is the missing
# half of drag-to-install — it ships in every commercial macOS DMG for that
# reason. `ditto` rather than `cp -R`: it preserves the signature's extended
# attributes, which a plain copy can drop.
STAGE="build/dmg-stage"
rm -rf "${STAGE}"
mkdir -p "${STAGE}"
ditto "${EXPORTED_APP}" "${STAGE}/${APP_NAME}.app"
ln -s /Applications "${STAGE}/Applications"

# Prove the staged copy is still the bundle that was signed, before wrapping it.
if ! codesign --verify --strict "${STAGE}/${APP_NAME}.app" > /dev/null 2>&1; then
    echo "✗ the staged app no longer verifies — the copy broke the signature" >&2
    exit 1
fi

echo "Building ${DMG}"
hdiutil create \
    -volname "${APP_NAME}" \
    -srcfolder "${STAGE}" \
    -ov -format UDZO \
    "${DMG}" > /dev/null

if [ ! -f "${DMG}" ]; then
    echo "✗ DMG was not produced at ${DMG}" >&2
    exit 1
fi

echo "Signing the DMG"
codesign --force --sign "${SIGN_IDENTITY}" --timestamp "${DMG}"

## Notarize ====================================================================

if [ "${SKIP_NOTARIZE}" = "true" ]; then
    echo
    echo "⚠ skipped notarization — this DMG is signed but NOT notarized."
    echo "  Gatekeeper will refuse it on a machine that did not build it."
    echo "  Verify that refusal deliberately:"
    echo "    spctl -vvv --assess --type exec --ignore-cache '${EXPORTED_APP}'"
    echo "  It must fail until a ticket is stapled. Then run without --skip-notarize."
    exit 0
fi

echo "Submitting to the notary service (this can take several minutes)"
if ! NOTARY_OUTPUT=$(xcrun notarytool submit "${DMG}" \
    --keychain-profile "${NOTARY_PROFILE}" \
    --wait 2>&1); then
    echo "${NOTARY_OUTPUT}" >&2
    echo "✗ notarytool submit failed" >&2
    exit 1
fi
echo "${NOTARY_OUTPUT}"

if ! echo "${NOTARY_OUTPUT}" | grep -q "status: Accepted"; then
    echo "✗ notarization was not accepted" >&2
    echo "  Fetch the reason:" >&2
    SUBMISSION_ID=$(echo "${NOTARY_OUTPUT}" | sed -n 's/^ *id: *//p' | head -1)
    echo "    xcrun notarytool log ${SUBMISSION_ID:-<id>} --keychain-profile ${NOTARY_PROFILE}" >&2
    exit 1
fi
echo "✓ notarization accepted"

## Staple ======================================================================

echo "Stapling the ticket"
xcrun stapler staple "${DMG}"

echo "Validating the staple"
xcrun stapler validate "${DMG}"

## Gatekeeper ==================================================================

# Assess a copy that carries a quarantine flag, which is what a downloader gets.
# Assessing the local build would pass without proving anything about distribution.
echo "Assessing as a downloaded artifact"
QUARANTINE_DIR="${ROOT}/.build/quarantine-check"
rm -rf "${QUARANTINE_DIR}"
mkdir -p "${QUARANTINE_DIR}"
cp "${DMG}" "${QUARANTINE_DIR}/"
xattr -w com.apple.quarantine "0083;$(printf '%x' "$(date +%s)");Safari;" \
    "${QUARANTINE_DIR}/${APP_NAME}-${VERSION}.dmg"

if spctl -vvv --assess --type open --context context:primary-signature \
    "${QUARANTINE_DIR}/${APP_NAME}-${VERSION}.dmg" 2>&1; then
    echo "✓ Gatekeeper accepts the quarantined DMG"
else
    echo "✗ Gatekeeper rejected the quarantined DMG" >&2
    exit 1
fi
rm -rf "${QUARANTINE_DIR}"

echo
echo "✓ release ready: ${DMG}"
echo "  sha256: $(shasum -a 256 "${DMG}" | cut -d' ' -f1)"
echo "  next:   tag v${VERSION}, attach the DMG to the GitHub release, update the cask"
