# Moon 0.3.5 beta verification

A focused sidebar-motion and installed-size update for macOS 26+ / Apple silicon.

- Reviewed the supplied hover recording. The old highlight eased in for 70 ms
  but cleared instantly on exit; 0.3.5 uses a 100 ms ease-in/ease-out in both
  directions. Animation stays inside the decorative background. Titles, close
  hit targets and selection keep their immediate hover transactions. Reduce
  Motion disables the highlight transition.
- All 15 SidebarPressTests passed, including rapid interrupted crossings, close
  targeting, press-to-select and editing behavior. Five release-publisher tests
  passed. Full GitHub Build Moon checks run independently on the source commit;
  no pending result is represented as a completed full-suite pass.
- High-resolution ICNS representations use native high-quality JPEG 2000
  payloads; small PNG representations and the original source artwork are
  preserved. The icon file shrinks from 1,640,113 to approximately 264,982 bytes.
  The 1024px native render comparison measured 53.52 dB overall PSNR and 72.71 dB
  alpha PSNR. This is high-fidelity compression, not a claim of lossless pixels.
- Native icon decoding and package checks are separate from the release Swift
  compile. Installed app contents target approximately 11 MB, not the DMG size.
- Release packaging verifies signatures, version/build, archive length and URL,
  minimum macOS and altered-byte rejection. The installer and update ZIP use
  the same signed candidate; publication checks each uploaded file's digest
  before updating the signed feed.

Shipping this version means publication to GitHub. The user's running Moon
installation is not replaced or restarted by this pass. Verification uses
isolated tests and a separate candidate; browser profiles and preview files do
not enter source or release archives.

The beta remains Apple Development signed and not Apple-notarized. App Sandbox,
hardened runtime and library validation remain enabled. A future in-app upgrade
is distinct from this release's feed/archive authentication checks.
