# Release checklist

Everything here needs the repository owner. Nothing on this list can be done by
a contributor or by an agent, which is why it is a separate file.

Work top to bottom; each item unblocks the one below it.

## 1. Assets only you can supply

- [x] **Screenshots.** Two real captures from your own photography catalogue,
      taken 2026-10-25: `docs/screenshots/hero.jpg` (three columns, gutter
      visible) and `docs/screenshots/transport.jpg` (the transport pill). Both
      are live in `README.md` and licensed CC BY 4.0 with it. A Fill-versus-fit
      comparison was not captured and is optional. Do not substitute generated
      or stock imagery.
- [x] **The GitHub URL.** Filled in as `davidegreenwald/arturo` across
      `README.md`, `CONTRIBUTING.md`, and `docs/distribution.md`.
- [ ] **Confirm the name.** `arturo` is free as a Homebrew **cask**, but
      `arturo` is already a Homebrew **formula** (the Arturo programming
      language). Casks and formulae are separate namespaces, so this works — but
      every install instruction must say `--cask arturo`. Also note a pending
      class 9/42 software mark exists for `QUINN` (the name you rejected), not
      for `ARTURO`; the `ARTURO` marks found are paper goods and
      property-insurance analytics. This is not legal advice, and one search was
      from a secondary source because USPTO TSDR now requires an API key.

## 2. Repository

- [x] Push to the existing remote, `github.com/davidegreenwald/arturo`
      (already configured as `origin`). **Done**: `origin/main` is `c389809`, and
      the repository is public with the v1.0.0 release attached.
- [ ] Run the renamed project once locally before pushing:
      `make generate && make verify`, then `make install` and open a real folder.
      The identity rename is verified green here, but not yet exercised against
      your own photo library.
- [x] Confirm CI goes green on the first push. **Done**: three runs recorded,
      the latest on `c389809` completed success 2026-10-26T02:17Z.
      `.github/workflows/ci.yml` triggers on push and pull request against
      `macos-26`, and runs `make doctor` before the gate.
- [ ] Decide whether to keep the optional pre-commit hooks documented. They run
      a full build per commit and replace any global `core.hooksPath`.

## 3. Signing and notarization

Required before any binary download works — Homebrew applies quarantine to cask
downloads and the `--no-quarantine` escape hatch no longer exists, so an unsigned
build is blocked by Gatekeeper on first launch either way.

- [x] Apple Developer Program membership active — enrolled as an individual,
      team `UZ6HKPU495`.
- [x] **Developer ID Application** certificate created and exported as `.p12`
      (Account Holder role required). Not Developer ID Installer. Issued
      2026-10-24 from the G2 authority; **expires 2027-11-24** and must be
      renewed annually thereafter.
- [ ] App Store Connect **Team API key**: `.p8` plus Key ID and Issuer ID. The
      `.p8` downloads once only — store it durably.
- [x] Store the notary credential in the keychain so the `.p8` stays out of the
      repo: `xcrun notarytool store-credentials arturo-notary …` — done
      2026-10-24, using an Apple ID app-specific password rather than an API key
      (App Store Connect API access sits behind a separate approval request).
      Switching to a Team API key later means re-running the same command with
      `--key/--key-id/--issuer`, overwriting the profile. `release.sh` needs no
      change either way.
- [x] Team ID — `UZ6HKPU495`.
- [ ] Add the six secrets listed in `docs/distribution.md` to the repository.
      Only needed once the release moves to CI; a local `make release` uses the
      keychain profile instead and needs no secrets at all.
- [x] Perform one manual notarized build before automating it. **Done
      2026-10-24**: `make release` succeeded, submission accepted, ticket stapled,
      quarantined DMG accepted by Gatekeeper. 27 minutes end to end, of which
      about 30 seconds was local work.

No entitlements file is needed: Arturo is unsandboxed and reads a folder the user
picks, so it requires no file-access entitlement. Hardened Runtime is already
enabled in `project.yml`.

## 4. Distribution

- [x] Tag `v1.0.0` and publish a GitHub Release with the stapled `.dmg`.
      **Done 2026-10-25**: the annotated tag `v1.0.0` sits on the initial commit,
      and the release carries `Arturo-1.0.0.dmg`, notarized and accepted by
      Gatekeeper. The published checksum, `93b8ffd0…e709`, matches
      `shasum -a 256 build/Arturo-1.0.0.dmg`. A ZIP cannot be stapled; staple the
      `.app` inside it, or ship a DMG.
- [ ] Keep the release notes and `README.md` in step. The v1.0.0 notes are their
      own copy of the install, requirement, and privacy wording, so a README edit
      does not reach them. Read both before publishing; the notes can be edited in
      place (`gh release edit v1.0.0 --notes-file NOTES.md`) without cutting a new
      release.
- [ ] Create `github.com/davidegreenwald/homebrew-tap` with `Casks/arturo.rb` from
      `docs/distribution.md`, and replace the `sha256` with the real checksum of
      the released DMG.
- [ ] Document the install line as `brew install --cask davidegreenwald/tap/arturo` — the
      fully qualified form. A bare `brew install arturo` installs a programming
      language.
- [ ] Only later, and only if wanted: submit to `Homebrew/homebrew-cask`. A
      self-submission needs **225 stars** and a repo **at least 30 days old**,
      plus a working `livecheck` and a `zap` stanza. The same cask file carries
      over, so write it properly in the tap first.

## 5. Known gaps to decide on, not to fix blindly

- [ ] **No performance baselines and no signposts** exist. ADR-005 states this
      plainly. Adding `OSSignposter` spans around page advance and one XCTest
      baseline would close it.
- [ ] **UI test lane is not in the gate.** `make test-ui` is manual. Worth one
      run before release.
- [ ] **Trademark clearance.** No searches performed here constitute legal
      advice. If Arturo gets real distribution, a proper clearance search is
      cheap insurance.
- [ ] **No markdown check in the gate.** `make verify` never reads `README.md` or
      `docs/`, so stale version numbers, broken image paths, and claims that
      drifted from the code ship silently. Closing it means one link-and-claim
      check in `verify.sh`, or a separate lane.

Resolved by the macOS 26 floor: the app's minimum OS is the same generation as
the development machine and the CI runner, so the floor is runtime-tested. There
is no longer a compile-only deployment target to worry about.
