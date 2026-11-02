# Moon 0.3.2 beta verification

Requires Apple silicon and macOS 26 or later. This release preserves the tested native executable and packages the latest gradient icon and sidebar hover refinement.

- All 15 focused SidebarPressTests passed on the current executable, including rapid hover switching, closing, selection and drag interactions.
- Five offline release-publisher checks passed: upload order, altered-blob rejection, upload digest mismatch, repository restrictions and path restrictions.
- The installer and update ZIP contain the same application. Release packaging verifies the application code signature, the signed feed and archive signature, version, length, download URL and minimum macOS, plus a tampered-byte rejection.
- The current beta uses Apple Development signing, App Sandbox and hardened-runtime library validation. It is not Apple-notarized.

Publication and an authenticated feed do not alone prove a complete old-to-new installed-app upgrade. A later higher build is needed to exercise installation and relaunch. Apple Passwords helper pairing, restricted browser entitlements, every third-party extension and protected streaming services require their own verification.

Browser profiles, browsing data, signing keys, local backups, preview drafts and generated test artifacts are excluded from the source archive and public source tree.
