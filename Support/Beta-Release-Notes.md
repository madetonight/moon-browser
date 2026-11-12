# Moon 0.4.12 beta

A smoother sidebar, right on cue.

- Move the live sidebar as one native surface instead of animating its controls through the browser’s view hierarchy.
- Shorten the hover delay and preserve smooth reversal when the pointer changes direction.
- Reuse mouse events’ window information to avoid repeated window lookups during movement.
- Stop the resize handle flashing over the page during sidebar reveals. Resizing remains available.
- Show a downloaded update as ready and bring its installation dialog back into view instead of leaving a downloading message behind.
- Keep copied license resources writable so the signed updater can remove quarantine during installation.

Apple silicon, macOS 26 or later. One signed DMG serves installation and in-app updates. This Moon beta is Apple Development signed and is not Apple-notarized. The optional ActivityWatch companion is distributed separately by its authors.
