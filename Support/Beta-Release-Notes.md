# Moon 0.4.4 beta

Smoother inboxes. More reliable updates.

- Retry temporary update transport failures at most twice, with backoff and connectivity awareness. Certificate, signature, malformed-feed and installation errors are never retried automatically.
- Keep a successful no-new-update result from being overwritten by Sparkle’s normal end-of-cycle sentinel. Settings now shows the actual updater status.
- Ignore failures, commits and completions belonging to an older navigation after a new load has started. New navigations clear a previous error immediately.
- Avoid full-document sign-in scans when Gmail and other dynamic pages only change messages or non-form content. Dynamically added, removed or revealed input fields remain detectable.
- Preserve native WebKit image resolution, media playback, cache validation and TLS verification.
- What’s New contains this release only.

Apple silicon, macOS 26 or later. One signed DMG serves installation and in-app updates. This Moon beta is Apple Development signed and is not Apple-notarized. The optional ActivityWatch companion is distributed separately by its authors.
