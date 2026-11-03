# Moon 0.3.4 beta verification

Requires Apple silicon and macOS 26 or later. This release includes the original
approved Fluid Dusk gradient icon, Moon branding and creator credits, the
three-step onboarding, smaller production packaging and queued idle-tab snapshots.

## Automated checks

The local release run exercised 452 XCTest cases (one platform skip) and 21
Swift Testing cases. One branding assertion still expected the old upstream app
name in an import-permission message; the expectation was updated to Moon and
the complete BrowserDiscoveryTests suite was rerun. No browser behavior was
changed for that test correction. GitHub's Build Moon run on the source commit
provides a fresh full-suite check before release publication.

Five offline release-publisher checks cover asset ordering, altered-blob
rejection, upload-digest mismatch, repository restrictions and path restrictions.
The idle-snapshot queue has a regression check for batch completion, repeated
event suppression and preserving a playing page.

## Packaging and live validation

Release preparation verifies the application signature, signed feed and archive,
version/build, length, update URL and minimum macOS, with tampered-byte rejection.
The DMG and updater ZIP must contain the exact same signed application. Fluid
Dusk is exported through the native icon-size pipeline, preserving its glass edge.
Live About, Dock artwork and update-check behavior are reviewed separately from
compilation. The release manifest pins artifact lengths and SHA-256 digests.

The candidate remains Apple Development signed, sandboxed and hardened, with
library validation enabled. It is not Apple-notarized. Only verified cached
Sparkle helpers are reused, and private signing keys stay on the developer Mac.

The 9 MB installed-size target remains unmet. An earlier controlled 38-document
run of the same idle-tab implementation on an M1 Pro / 16 GiB Mac recorded
approximately 1.28 GB physical footprint with all pages loaded and 174 MB after
37 inactive pages slept. This is not a benchmark of arbitrary websites, video,
or sustained user interaction, and is not a new measurement of this release.

A complete 0.3.2-to-0.3.3 in-app upgrade was verified previously. A new release's
signed feed and an offered version alone do not prove installation/relaunch.
Apple Passwords helper pairing, restricted browser entitlements, every third-party
extension and protected streaming services require separate verification.

Browser profiles, browsing data, signing keys, local backups, unused preview
drafts and generated test artifacts are excluded from source and release assets.
