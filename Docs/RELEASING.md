# Moon releases and in-app updates

Before each feature release, update `Support/Info.plist`, replace the single
current `WhatsNew.notes` entry in `Sources/Moon/WhatsNew.swift`, and update
`Support/Beta-Release-Notes.md`. Run `python3 Scripts/check-release-notes.py`.
Both release-preparation paths and source CI enforce the one-current-version
rule so Settings never ships stale release notes or a historical list.

Moon embeds the exact Sparkle 2.10.1 package and uses its installer XPC service
inside App Sandbox. Automatic checks run hourly when a real signed feed is enabled;
automatic download/install-on-quit follows the existing Settings switch. Check Now
uses Sparkle's native update UI. Failed or unconfigured checks never mean “latest”.

The feed is configured as
`https://raw.githubusercontent.com/madetonight/moon-browser/main/appcast.xml`.
Release preparation enables `MoonUpdateFeedReady` in the candidate. Development
builds leave it false. Preparation creates one DMG for installation and updates,
a signed feed and local verification checksums; it does not publish.

The publish workflow accepts `.github/releases/current.json` on main. It retrieves
the pre-signed artifact blobs, checks every length and SHA-256, uploads a draft
GitHub release and publishes it only when all assets match. It then updates the
signed appcast. Apple and Sparkle private signing keys stay on the developer Mac.
The workflow uses only the temporary repository-scoped GitHub Actions token.
Existing installers cannot be overwritten with different bytes. Exactly one DMG
is attached to the newest release; appcast.xml is stored in the repository, and
source is available through GitHub. Only after the DMG and feed are verified does
the publisher remove extra assets and older releases. Newer or unrecognized
releases, mismatching installer bytes or a changed branch stop cleanup.

Swift tests run only for app/source/test/build inputs. Release scripts and
manifests run the separate offline release checks; publishing a feed or changing
release metadata does not repeat a full Mac build. Historical failed runs remain
as an audit trail; current source and release jobs are the relevant status.

## Signing keys

`Support/UpdatePublicKey.txt` is the public Ed25519 key. The matching private key
is in this Mac's Keychain under account `org.moonbrowser.Moon`; it must never be
exported or committed. This key is separate from Apple code signing.

To verify only the public key after dependency resolution:

```sh
/private/tmp/Moon107Build/artifacts/sparkle/Sparkle/bin/generate_keys \
  --account org.moonbrowser.Moon -p
```

Local builds automatically use an installed Apple Development identity, or the explicit `MOON_SIGNING_IDENTITY`. Ad-hoc signing is refused because hardened-runtime library validation rejects an ad-hoc embedded framework. No library-validation exception is used. Local signatures are not notarized public distribution. A personal Apple
Development identity can sign development builds, but it is not Developer ID
Application signing. An Apple Development–signed, non-notarized beta can use
signed Sparkle updates, as Levels does. Developer ID is needed for the separate
notarized distribution path below; it is not a prerequisite for beta updates.

Private-key use requires explicit `MOON_ALLOW_SIGNING=1`. Without it the build and
release scripts stop before signing and preserve the existing app. For a matching
dependency digest and certificate, a public-signature-verified helper cache avoids
signing every Sparkle helper again. The outer app still needs a new signature when
rebuilt. Keychain access rules are never changed by these scripts.

## Prepare a Levels-style beta

This is the current intended path. It uses Moon's existing Apple Development
certificate, its separate Ed25519 update key and free GitHub hosting. Moon keeps
hardened-runtime library validation enabled because its embedded helpers are
signed with the same certificate. Unlike the older Levels beta pipeline, no
runtime protection needs to be disabled.

```sh
Scripts/prepare-beta-update.sh --plan
# Only when ready to authorize the new app signature and update signing:
MOON_ALLOW_SIGNING=1 Scripts/prepare-beta-update.sh
```

The plan is read-only and does not contact Keychain. Preparation builds
build/MoonReleaseCandidate.app with the configured feed enabled, leaving the
normal build/Moon.app unchanged. It reuses verified signed helpers where possible,
verifies the candidate, creates the one DMG, generates the signed appcast with
embedded notes and only the newest version, verifies signatures and
version/length/URL/minimum macOS, and creates local checksums in dist-release.*. It neither
uploads files nor changes Keychain permissions.

Publish the exact DMG to the matching GitHub beta release first. Then publish
appcast.xml at the configured feed address. Extra release attachments and older
releases are retired after both are verified. Do not attach the feed, source
archive, standalone readme or local checksums as additional downloads.
Moon uses the existing raw GitHub HTTPS URL rather than requiring GitHub Pages;
both serve the same signed appcast architecture. Never edit generated signed XML.

Older builds with `MoonUpdateFeedReady=false` need one manual installation of a
connected beta. Publishing a feed cannot enable an updater in an old disconnected
build. Published 0.3.2 and 0.3.3 betas include the connected updater; a real
0.3.2-to-0.3.3 download, installation and relaunch was verified. For a new release,
verify the exact signed archive/feed and check the offered version separately
from any claim about that release's complete installed upgrade.

This beta is not Apple-notarized. Sparkle authenticates updates but does not confer
Gatekeeper trust. macOS may require per-app approval for a first internet download.
Apple Passwords helper signing/entitlement requirements are a separate integration.

## Prepare a notarized release

The owner needs an Apple Developer Program account, a Developer ID Application
certificate, and an existing notarytool Keychain profile. Apple authentication,
agreement and payment steps must be completed by the owner. No passwords belong
in source or chat.

```sh
MOON_SIGNING_IDENTITY='Developer ID Application: YOUR NAME (TEAMID)' \
MOON_ALLOW_SIGNING=1 \
MOON_RELEASE_TEAM='YOURTEAMID' \
MOON_NOTARY_PROFILE='Moon Notary' \
MOON_DOWNLOAD_URL_PREFIX='https://github.com/madetonight/moon-browser/releases/download/v0.3.1/' \
Scripts/prepare-release.sh
```

The script builds a sandboxed release candidate, signs nested helpers from the
inside out, notarizes and staples, verifies code signatures/Gatekeeper, verifies
the update public key, produces a signed archive and signed appcast, and retains
checksums in a new local `dist-release.*` folder. It never publishes.

Review the artifact, archive URL, version/build, minimum macOS, feed signature,
archive signature and checksums. Publish the archive and appcast together only
with explicit repository/publication authorization. Verify the feed is reachable
and test an installed old-to-new upgrade with the normal sandboxed app before
claiming automatic updates are live. A release candidate's ready flag alone is
not evidence of publication or a working installed-app upgrade.

## Security verification

`Scripts/test-update-signatures.py` exercises valid archive/feed signatures and
unsigned/tampered rejection using the pinned Sparkle tools and existing Keychain
key. It does not export keys, publish files, or prove an installed-app upgrade.
`Scripts/verify-update.swift --self-test` exercises the independent public-key
archive verifier with an ephemeral synthetic key and requires no Keychain access.
See the retained Codex Security hardening report for app-level runtime
checks and remaining validation boundaries.
