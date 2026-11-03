## Moon 0.4.0 beta — personal interface colors

49 focused checks passed: five palette validation/persistence, per-appearance,
accent/reset/cache and settings-discovery checks, plus all 44 preceding sidebar,
rendered-hover, settings and address-security checks. Custom colors are stored in
local preferences as opaque sRGB hex values; invalid data falls back to defaults.
Separate light/dark banks affect browser chrome only, with no website CSS
injection or page reload. Reset restores the existing palette and optional accent
defaults to off. Color values and runtime profiles are not build inputs.

The rendered hover fixture slows only its test animation by 10x and samples by
elapsed time, so a busy hosted runner cannot sleep through the full production
fade before taking its first frame. The fixture still requires intermediate
rendered pixels on entry and exit and verifies both endpoints. If the host's
system Reduce Motion is on, this intermediate-frame check explicitly skips:
instant transitions are the required behavior in that environment. The separate
reduced-motion check always covers that path. CI tests the release configuration
used locally and shipped to users; the rendered fixture passed on this Mac.

## Moon 0.3.9 beta — complete hover visuals and sidebar titles

44 focused checks passed: sidebar press/close/title behavior, native highlight
behavior, rendered intermediate fade frames, address-security labels and settings.
The title snapshot regression verifies that the legacy address preference cannot
replace sidebar page titles. The rendered fade regression covers the row's
otherwise disabled-animation transaction. A final hosted-render probe confirmed
partial values on both entry and exit after excluding the native decoration from
SwiftUI hit testing. Entry/exit are 160/140 ms, scoped to visual changes. The
selected Apple row was verified in the running local app as its page title.
Production build and strict signature verification passed; Pearl Current retained.
Release archives are prepared from the app bundle and a source-code allowlist,
with runtime browser data and private import backups excluded.

## Moon 0.3.7 beta — Pearl Current and responsive hover

Pearl Current is the selected icon. Sidebar hover uses an isolated native layer
with an 85 ms arrival and 65 ms departure, retargeting from presentation opacity.
Unrelated view updates do not restart fades; detached rows clear animation and
Reduce Motion changes immediately. No timers or per-frame SwiftUI state updates.
Selected sidebar labels retain the configured domain/title on hover; existing
address-display preferences and security warnings remain respected.
Selection and the fixed close target remain immediate. Production build and all
18 focused checks passed (15 sidebar press/rapid-crossing tests and three native
highlight tests). Five release-publisher checks passed. These checks do not claim
a subjective physical-pointer review. Exact signature, package, live publication
and installation evidence is retained separately in dist/Moon-0.3.7-beta.
The beta uses Apple Development signing and is not notarized.

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
