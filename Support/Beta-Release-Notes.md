# Moon 0.4.3 beta

Less waiting. More of the page.

- Avoid repeated page-script setup when the site's scripts and options are unchanged. Changes to script objects, content worlds, privacy-related options and site styles still trigger a fresh installation.
- Show a ready first frame immediately, and remove a sleeping tab's preview when the page actually paints.
- Cancel obsolete recovery work when you navigate elsewhere. Slow navigations are allowed to finish without being restarted by the recovery timer.
- Simplify the sidebar dock to Extensions, Bookmarks, Downloads, Translate and Orbit. Profile and space buttons are removed from the dock; existing profiles and spaces are preserved.
- Swipe right on the sidebar to open the New Space card. Short or cancelled swipes leave your current space alone. Creating the space still requires confirmation in the card.
- Preserve native WebKit image decoding, video playback, cache validation and connection handling. No image downscaling, forced low-bitrate streaming, custom proxy or certificate bypass is introduced.
- What's New contains this release only.

Apple silicon, macOS 26 or later. One signed DMG serves installation and in-app updates. This Moon beta is Apple Development signed and is not Apple-notarized. The optional ActivityWatch companion is distributed separately by its authors.
