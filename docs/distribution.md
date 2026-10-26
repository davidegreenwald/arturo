# Distribution

How Arturo goes from a git tag to something a stranger can install. This is a
maintainer document: contributors never need any of it, because local builds are
unsigned (ADR-004).

## Why signing is not optional

Homebrew applies the macOS quarantine attribute to every cask download, and its
own documentation says it does so "so Gatekeeper performs these checks instead
of Homebrew bypassing them". The installed source confirms it —
`Quarantine.cask!(cask:download_path:)` runs unconditionally in
`Library/Homebrew/cask/download.rb`. The `--no-quarantine` escape hatch was
deprecated in Homebrew 5.0.0, disabled in 5.1.0, and removed by 7.0.x; there is
no `cask_opts_quarantine` left in `cmd/install.rb` or `cask/`.

The practical consequence: an unsigned build is blocked by Gatekeeper on first
launch whether the user downloads it in a browser or installs it with `brew`.
Signing and notarization are not polish — they are the difference between an app
that opens and a support thread.

## What is required

| Requirement | Detail |
|---|---|
| Certificate | **Developer ID Application**. Not Developer ID Installer (that signs `.pkg`), not Apple Development, not Mac App Distribution. |
| Hardened Runtime | Required for notarization. Already on via `ENABLE_HARDENED_RUNTIME: YES` in `project.yml`. |
| Secure timestamp | Required. `codesign --timestamp`. |
| Entitlements | **None.** See below. |
| App Sandbox | **Not enabled, and not needed.** Required only for Mac App Store distribution. |
| Artifact | A `.dmg` is staplable. A ZIP is **not** — Apple's guidance is to staple the `.app` inside it, then re-zip. Ship a DMG. |
| Certificate validity | **One year.** Certificates from the G2 authority "are valid for one year and must be renewed annually" — <https://developer.apple.com/help/account/certificates/replace-developer-id-certificates/>. The old five-year lifetime no longer applies, so renewal is a recurring task. Check the issuer: `OU=G2` is current; the original Sub-CA stops working 2027-02-01. |

### Expiry is not revocation

Only one of these breaks customers.

| Event | Already-shipped apps | New releases |
|---|---|---|
| Certificate **expires** | Keep working — Gatekeeper evaluates validity at signing time plus the secure timestamp | Blocked until replaced |
| Certificate **revoked** | **Stop installing, and stop launching if already installed** | Blocked until replaced |

Source: <https://developer.apple.com/help/account/certificates/create-developer-id-certificates/>

Revoke only on suspected private-key compromise. Losing a `.p12` is a data-recovery problem first; revoking is a customer-visible outage.

Apple's stated rule: "Use a 'Developer ID' application, kernel extension, system
extension, or installer certificate for your code-signing signature. (Don't use
a Mac Distribution, ad hoc, Apple Developer, or local development certificate.)"

Source: <https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution>

### Why no file-access entitlement

`com.apple.security.files.user-selected.read-only` is a *sandbox* entitlement,
not a Hardened Runtime one. Arturo is unsandboxed, so it needs no entitlement to
read a folder the user picks with `NSOpenPanel`.

This does not bypass TCC. Desktop, Documents, Downloads, iCloud Drive, and
network volumes stay consent-gated by the system for sandboxed and unsandboxed
apps alike. A folder in `~/Pictures` is unprompted; a folder on the Desktop
triggers a consent prompt on first scan, and a denial must be handled as a
permission problem rather than an I/O error.

Source: <https://support.apple.com/guide/security/controlling-app-access-to-files-secddd1d86a6/web>

## Credentials the maintainer must provide

None of these belong in the repository. All go into GitHub Actions secrets.

| Secret | Where it comes from |
|---|---|
| `APPLE_TEAM_ID` | developer.apple.com → Account → Membership details |
| `MACOS_CERT_P12_BASE64` | Developer ID Application cert, exported as `.p12`, then base64-encoded |
| `MACOS_CERT_P12_PASSWORD` | Chosen at export time |
| `MACOS_KEYCHAIN_PASSWORD` | An arbitrary password for the temporary CI keychain |
| `ASC_KEY_P8_BASE64` | App Store Connect → Users and Access → Integrations → Team Keys → generate, then base64-encoded |
| `ASC_KEY_ID` | Shown next to the key in App Store Connect |
| `ASC_ISSUER_ID` | Shown at the top of the Integrations page (Team keys only) |

Creating the certificate: developer.apple.com → Certificates, Identifiers &
Profiles → Certificates → **+** → Software → Developer ID → CSR → download the
`.cer` → install → Xcode → Settings → Accounts → Manage Certificates →
Control-click → Export Certificate. The Account Holder role is required.

The `.p8` can only be downloaded **once**. Store it somewhere durable before
pasting it into the secret.

### Where the files themselves live

Not in this repository, and not on the Desktop. The canonical home on this machine
is **`~/picard/system-setup/signing-credentials/`** — a plain directory on the
FileVault-encrypted disk, mode 700 with files at 600, not a git repo and not synced
to any cloud service. Each file is named `<vendor>-<purpose>-<team-id>.<ext>`, and
the README in that directory holds the fingerprints, validity window, renewal
date, and the Keychain service name holding the `.p12` passphrase.

That location is machine-local, so it is deliberately absent from this document's
instructions for anyone else — a contributor clones the repo and never needs any
of it (ADR-004).

### Local releases: store the credential in the keychain, not in the tree

`notarytool` can read credentials from the login keychain, which keeps the `.p8`
out of the working directory entirely. Do this once:

```sh
xcrun notarytool store-credentials arturo-notary \
  --key AuthKey_XXXXXXXXXX.p8 --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID"
```

`--validate` is on by default, so a wrong key, ID, or issuer fails at store time
rather than at notarization. After that, `scripts/release.sh` authenticates with
`--keychain-profile arturo-notary` and never touches a `.p8` path. Delete the
downloaded key from Downloads once stored.

This matters because the literal `--key authkey.p8` form used below reads the key
from the current directory — the repo — which is how a notarization key ends up in
a commit. Prefer the profile.

API-key auth is preferred over an Apple ID plus app-specific password: it keeps
a human Apple Account and its 2FA out of CI, it is revocable per key, and Apple
revokes all app-specific passwords whenever the account password changes.

A certificate expiring does **not** break apps already shipped: what matters is
that it was valid at signing time.

## The release build

`scripts/release.sh` runs this whole sequence, and `make release` calls it. The
expanded commands are kept here because the script is meant to be read alongside
them, not trusted blind. Use `scripts/release.sh --skip-notarize` (`make
release-signed`) to exercise everything except the notary submission.

The script enforces four preflight conditions that are easy to skip by hand: a
Developer ID identity with its private key is present, the team ID parses out of
it, the working tree is clean, and the notary profile validates. It then signs,
notarizes, staples, and re-assesses the DMG **with a quarantine flag set**, which
is the state a downloader actually receives.

```sh
# 1. Build a universal Release archive, signed and with the runtime flag.
xcodebuild -project Arturo.xcodeproj -scheme Arturo \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath build/Arturo.xcarchive \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGN_IDENTITY="Developer ID Application" \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  OTHER_CODE_SIGN_FLAGS="--timestamp --options runtime" \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  archive

# 2. Export with method developer-id (needs an ExportOptions.plist).
xcodebuild -exportArchive \
  -archivePath build/Arturo.xcarchive \
  -exportPath build/export \
  -exportOptionsPlist ExportOptions.plist

# 3. Build the DMG, sign the DMG itself, then notarize and staple it.
hdiutil create -volname Arturo -srcfolder build/export/Arturo.app \
  -ov -format UDZO build/Arturo.dmg
codesign --force --sign "Developer ID Application" --timestamp build/Arturo.dmg

xcrun notarytool submit build/Arturo.dmg \
  --key authkey.p8 --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" \
  --wait

xcrun stapler staple build/Arturo.dmg
xcrun stapler validate build/Arturo.dmg

# 4. Verify Gatekeeper and the architectures, rather than assuming.
spctl -vvv --assess --type exec --ignore-cache build/export/Arturo.app
lipo -archs build/export/Arturo.app/Contents/MacOS/Arturo
```

`ExportOptions.plist` for direct distribution:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>signingStyle</key>
    <string>manual</string>
</dict>
</plist>
```

### Traps worth knowing before the first attempt

- **Do not use `codesign --deep`.** It is deprecated for signing as of macOS 13
  and applies the same options to nested content, which is almost never right.
  Sign inside-out: nested code first, bundle last.
- **`CODE_SIGN_STYLE=Manual` is mandatory once an SPM package is involved.**
  Forcing a Developer ID identity while the package keeps automatic signing fails
  with `DesignSystem is automatically signed for development, but a conflicting
  code signing identity Developer ID Application has been manually specified`.
  Automatic signing expects Apple Development; manual applies the one identity to
  every target. Found the hard way on 2026-10-24.
- **`CFBundleShortVersionString` must reference `$(MARKETING_VERSION)`.** With
  `GENERATE_INFOPLIST_FILE: NO`, XcodeGen writes a literal `1.0` into the plist by
  default and `MARKETING_VERSION` drives nothing — the Release app reports the
  wrong version while the tag and the cask URL disagree with it.
- **`CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO` matters.** Otherwise Xcode injects
  `com.apple.security.get-task-allow` and notarization rejects the build.
- **`set-key-partition-list -S apple-tool:,apple:` is mandatory in CI.** Without
  it `codesign` cannot reach the private key in a headless keychain, and the
  failure looks like a signing error rather than a permissions error.
- **`lipo -archs` is a real gate, not a formality.** With `ONLY_ACTIVE_ARCH=YES`
  on an Apple Silicon runner, the release artifact silently contains `arm64`
  only.
- Notarization is slow, and it is not doing local work. The first release took
  **27 minutes end to end**, of which roughly 30 seconds was the archive, export,
  DMG, and signing. The remaining ~26 minutes was the notary queue: Apple scans
  the uploaded artifact and returns a ticket. `notarytool --wait` polls the
  service and prints `In Progress` repeatedly; that output is the poll, not
  progress on the build. Expect a slower first submission than later ones —
  Apple states the system learns to recognise your software over time. A long
  wait is not a hung build.
- `--wait` alone does not fail the run on rejection. `release.sh` greps the output
  for `status: Accepted` and exits non-zero otherwise, then prints the submission
  ID so `notarytool log` can retrieve the reason.
- Notarization is rate limited to 75 submissions per day. Notarize releases, not
  commits. [unverified — Apple documents that submissions get throttled and return
  a `THROTTLED` server error, but no published primary source states the figure.]

## GitHub Actions

The release workflow needs the keychain dance. Shape:

```yaml
- name: Import Developer ID certificate
  env:
    CERT_P12_BASE64: ${{ secrets.MACOS_CERT_P12_BASE64 }}
    CERT_P12_PASSWORD: ${{ secrets.MACOS_CERT_P12_PASSWORD }}
    KEYCHAIN_PASSWORD: ${{ secrets.MACOS_KEYCHAIN_PASSWORD }}
  run: |
    KEYCHAIN="$RUNNER_TEMP/build.keychain-db"
    echo "$CERT_P12_BASE64" | base64 --decode > "$RUNNER_TEMP/cert.p12"
    security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
    security set-keychain-settings -lut 21600 "$KEYCHAIN"
    security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
    security import "$RUNNER_TEMP/cert.p12" -k "$KEYCHAIN" \
      -P "$CERT_P12_PASSWORD" -T /usr/bin/codesign
    security set-key-partition-list -S apple-tool:,apple: -s \
      -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
    security list-keychains -d user -s "$KEYCHAIN" login.keychain-db
    rm -f "$RUNNER_TEMP/cert.p12"
```

Then build, notarize and staple as in the manual sequence, and attach the
stapled `.dmg` to the GitHub Release.

## Homebrew

Two phases. The first is available immediately; the second is earned.

### Phase 1 — your own tap (do this first)

There is no notability bar, no review, and no approval. A tap is any repo
containing a `Casks/` directory at its top level.

Create `github.com/davidegreenwald/homebrew-tap` with `Casks/arturo.rb`:

```ruby
cask "arturo" do
  version "1.0.0"
  sha256 "REPLACE_WITH_SHA256_OF_DMG"

  url "https://github.com/davidegreenwald/arturo/releases/download/v#{version}/Arturo-#{version}.dmg"
  name "Arturo"
  desc "Minimal full-screen slideshow viewer for a folder of photographs"
  homepage "https://github.com/davidegreenwald/arturo"

  depends_on :macos

  app "Arturo.app"

  zap trash: [
    "~/Library/Preferences/app.arturo.viewer.plist",
  ]
end
```

Users install with the **fully qualified** form:

```sh
brew install --cask davidegreenwald/tap/arturo
```

That form auto-taps and trusts only that cask. Since Homebrew 6.0.0, non-official
taps require explicit trust, so a two-step `brew tap` followed by a short-name
`brew install` also needs `brew trust --cask davidegreenwald/tap/arturo`. Documenting the
single fully-qualified command avoids the whole problem.

Compute the checksum with `shasum -a 256 Arturo-1.0.0.dmg` and paste it in. Do
not use `sha256 :no_check` on a versioned asset — Homebrew's own guidance is "we
use a checksum whenever possible", and users who set `--require-sha` will find
your cask fails.

Note the name collision: `arturo` is a *formula* in Homebrew (the Arturo
programming language, `arturo-lang.io`). Casks and formulae are separate
namespaces, so `--cask arturo` is free. But always document the `--cask` flag —
`brew install arturo` installs a programming language.

Your tap gets you installability, not discoverability: `brew search` only covers
`homebrew/core` and `homebrew/cask`. The README is the distribution channel.

### Phase 2 — `Homebrew/homebrew-cask` (earned)

A **self-submission** to the official cask repo requires, per Homebrew's Package
Acceptance Policy:

- **225 stars** (or 90 forks / 90 watchers) — a third-party submission needs 75.
- A repository **at least 30 days old**.
- A working `livecheck`, and a `zap` stanza for new submissions.
- A signed, notarized artifact that passes Homebrew's Gatekeeper checks.
- A homepage that explains the project.

Source: <https://docs.brew.sh/Package-Acceptance-Policy#notability>

So the sequence is: publish → sign and notarize → own tap → accumulate stars for
30+ days → submit the same cask upstream. The tap cask is the file you later
submit, so it is worth writing properly the first time.

## Verified vs unverified in this document

Read these before relying on them.

- **Verified locally:** Homebrew applies quarantine unconditionally
  (`cask/download.rb`), and `--no-quarantine` is gone. Homebrew 7.0.10.
  `arturo` is free as a cask and taken as a formula. `app.arturo.viewer` is a
  fresh identifier.
- **Verified on a real account (2026-10-24):** a Developer ID Application
  certificate exists for team `UZ6HKPU495`, issued by the G2 authority, valid
  until 2027-11-24 — consistent with Apple's one-year G2 validity rule. The
  certificate landed in the login keychain with its private key, and
  `security find-identity -v -p codesigning` lists it.
- **From Apple and Homebrew documentation, not executed here:** the notarization
  and stapling sequence, the credential flows, and the notability thresholds.
  These are quoted with source URLs above.
- **Build, signing, notarization, and stapling path executed 2026-10-24** on
  macOS 26.5 / Xcode 26.4.1, submission `cde81f27-7f9b-4f18-8b22-8e8c00309d1b`:
  archive → export (`method developer-id`) → DMG → DMG signature → notarize →
  staple. Result verified four ways: `stapler validate` passes; the notary
  history shows `status: Accepted`; `spctl` accepts the DMG with a quarantine
  flag set (`source=Notarized Developer ID`); and the app mounted from the DMG is
  independently accepted by `spctl`, reports version `1.0.0`, and is universal
  `x86_64 arm64`.
- **Not attempted:** no cask has been installed and nothing has been published.
  The first real *user* test — downloading the DMG from a public release URL and
  launching it — has not happened.
