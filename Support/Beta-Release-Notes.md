# Moon 0.4.0 beta

Personal interface colors, consistent sidebar titles and smoother hover feedback.

- The new Pearl Current app icon blends white, icy blue and cobalt with subtle glass depth.
- Settings → Appearance → Colors adds separate light and dark palettes for background, foreground surfaces and text, an optional accent, and a reset to Moon defaults. Website colors are unchanged.
- Sidebar highlights, title brightness, close buttons and text-edge masks now ease in over 160 ms and ease out over 140 ms.
- Interrupted fades continue from their visible opacity, and unrelated title/theme updates do not restart them. Tab titles, close targets and selection stay immediate.
- Sidebar tabs always show their page or custom title, including the selected tab. The address-display option now applies to horizontal tabs; connection warnings retain a separate indicator.
- The decorative native highlight ignores pointer input at both framework levels, preserving row tracking and immediate close-button targets.
- Reduce Motion keeps hover changes instant.
- Native high-resolution icon compression keeps the installed app around 11 MB while preserving the small icon representations.
- Moon's current browser features remain included.

Apple silicon; macOS 26 or later. This beta is Apple Development signed and **not Apple-notarized**. Sparkle authenticates updates; it does not confer Gatekeeper trust.

Connected Moon builds can use Settings → About → Check now. Older builds with updates disabled need a one-time manual installation. Source and MIT attribution notices accompany this release.
