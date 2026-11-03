# Moon Browser

A native WebKit browser for macOS 26 and later, with a minimal interface, a
personal welcome page, optional Liquid Glass and local Ollama AI.

Moon includes sidebar, icon rail and horizontal tabs; groups,
pins, spaces and profiles; multiple windows and splits; native settings and data
pages; translation; reader and Markdown; content blocking including YouTube;
media/call handling; extension APIs and installation; imports; and Mac menus,
keyboard shortcuts, notifications, printing, sharing and read-only AppleScript.

Source inclusion is distinct from runtime validation. Some integrations need
an OS permission, Apple's browser entitlement, helper pairing, or a published
signed release. Chrome compatibility depends on each extension's API needs.

## Download

[Moon 0.3.4 beta for Apple silicon](https://github.com/madetonight/moon-browser/releases/tag/v0.3.4-beta) requires macOS 26 or later. Open the DMG and drag Moon to Applications. The beta uses Apple Development signing and is not notarized by Apple. Install this connected version manually once; subsequent signed releases can be offered in Settings → About → Check now.

## Build and validate

Requires Xcode with the macOS 26 SDK or newer. SwiftPM resolves the pinned Sparkle 2.10.1 framework; no web runtime is bundled.

```sh
MOON_ALLOW_SIGNING=1 ./build.sh release
MOON_ALLOW_SIGNING=1 ./test.sh
```

The local app is `build/Moon.app`. Normal launches use your sandboxed profile.
Signing requires the explicit flag above. Without it, the build leaves the existing
app unchanged and never requests the developer key. Verified signed Sparkle helpers
are reused for the same dependency bytes and certificate, reducing repeated prompts.
Explicit native fixtures use `MOON_TEST_DIRECTORY` and separate WebKit/defaults
stores. The test runner never uses the normal library.

## Moon differences

- Moon's new-tab welcome, bookmarks and shortcuts remain; the address field
  floats over a page with ⌘L. No permanent address toolbar.
- Appearance → Liquid Glass adds an optional translucent frame, off by default
  and following Reduce Transparency. Source light, dark and system modes remain.
- AI is off until enabled. Only Ollama on this Mac is available; no cloud
  provider is selectable or allowed to make requests.
- Existing Moon `Library.json` is preserved. Compatible tabs, windows, spaces,
  pins, bookmarks and history migrate once into the new files when absent.
  Older credential and extension records are retained for explicit conversion.
- Moon retains bounded extension downloads/extraction and all-frame draft protection.
- App Sandbox restricts files to Downloads, the container and user-selected resources.
- Signed updates use Sparkle's sandbox installer. Release builds enable checks and installations through
  Moon's signed feed. Development builds keep checks disabled unless explicitly enabled. Search's update service and signing
  identity are never used. See [release setup](Docs/RELEASING.md).
- The Levels-style beta release path uses the existing Apple Development
  certificate and Sparkle key without requiring notarization. Preview it with
  `Scripts/prepare-beta-update.sh --plan`; publication and one initial connected
  install are required when bootstrapping an older build.

See [release verification](Docs/RELEASE-VALIDATION.md) and [release setup](Docs/RELEASING.md). Earlier performance figures describe an earlier implementation and do not benchmark this release.

## License and attribution

MIT. The native application source is derived from Search, copyright © 2026
Office Commun, pinned at `27bd91eb74ca5adaea7824f8708137a71514e146`.
See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and the complete upstream
[license](Support/Search-1.0.7-LICENSE). Moon's original core and additions remain
under this repository's MIT license.

Release artifacts contain the application and license notices, with a separate source archive. Local profiles, browsing data, signing keys and development backups are excluded.
