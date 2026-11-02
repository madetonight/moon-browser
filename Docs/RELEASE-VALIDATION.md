# Moon 0.3.3 beta verification

Requires Apple silicon and macOS 26 or later. This release packages the tested translator menu beside the sidebar icon, together with the existing gradient icon and sidebar hover refinement.

- Five focused WebsiteTranslationTests passed, covering exact original restoration, protected fields, translation availability and folded-sidebar command guards.
- Live UI review confirmed all nine default languages beside the bottom-left icon, Escape dismissal and View-menu reopening with a folded sidebar.
- Three popup sizing tests passed with explicit zero-width and reserved scrollbar fixtures.
- Five offline release-publisher checks passed: upload order, altered-blob rejection, upload digest mismatch, repository restrictions and path restrictions.
- The installer and update ZIP contain the same application. Release packaging verifies the application code signature, the signed feed and archive signature, version, length, download URL and minimum macOS, plus a tampered-byte rejection.
- The current beta uses Apple Development signing, App Sandbox and hardened-runtime library validation. It is not Apple-notarized.

Publication and an authenticated feed do not alone prove a complete old-to-new installed-app upgrade. A later higher build is needed to exercise installation and relaunch. Apple Passwords helper pairing, restricted browser entitlements, every third-party extension and protected streaming services require their own verification.

Browser profiles, browsing data, signing keys, local backups, preview drafts and generated test artifacts are excluded from the source archive and public source tree.
