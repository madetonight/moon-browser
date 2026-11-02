# Security

Moon is a native WebKit browser under active development. The security changes
for version 0.3 are tracked in the retained Codex Security hardening report.
There is not yet a public security-reporting address. Do not post credentials,
private browsing records, or exploit details containing user data in public issues.

## Required boundaries

- Keep WebKit's normal TLS validation, including local HTTPS. Never accept an
  unverified server certificate or offer a browser-level trust bypass.
- Run the app process in App Sandbox and keep hardened-runtime library validation.
  Grant outgoing networking, Downloads and explicitly selected files/folders;
  do not grant arbitrary home-folder access, inbound networking, debugger access,
  or library-validation exceptions.
- Require explicit user actions for privileged operations and validate origin.
  Keep page tools and native bridges in an isolated WebKit content world.
- Keep private tabs on nonpersistent website stores and outside
  history/session/download records and persistent local-file bookmarks. Exclude
  extensions by default; private access requires explicit per-extension opt-in. A file
  explicitly saved by the user remains on disk after private browsing ends.
- Store Moon-managed passwords in Keychain. Fail closed when authentication for
  Show/Copy/bulk deletion is unavailable or denied. Native user-selected filling
  and saving have separate explicit-action paths; do not describe them as a
  universal per-access biometric gate.
- Ask before opening another app's URL scheme. Never run a downloaded file
  automatically. Preserve macOS download quarantine.
- Verify extension package identity, integrity, extraction bounds and permissions.
  Extensions are trusted only within the user's granted capabilities, not as
  inherently safe code. Private-tab access must respect the user's explicit
  per-extension choice.
- Use the pinned Sparkle framework's sandbox-compatible installer. Require signed
  feeds and archive signatures before extraction; never fall back to unsigned
  feeds after a timeout. Keep release-note JavaScript and system profiling off.
  Never export the update signing key or substitute a shell-based self-updater.

## Distribution and remaining limits

App Sandbox restricts the browser's authority; it does not eliminate WebKit
vulnerabilities or make allowed downloads/extensions harmless. Install macOS
security updates promptly because Moon uses the system WebKit. Some inherited
Search features use guarded private WebKit APIs and need compatibility testing
with each macOS update.

The local build is distinct from a Developer ID signed, notarized public release.
Apple Passwords integration requiring signing/entitlements and a published
old-to-new update remain separate validation gates. External native extension
helpers and automatic imports from other browsers may be restricted by sandbox;
never add broad filesystem exceptions to silently restore those paths.
