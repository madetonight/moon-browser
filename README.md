# Moon

A native, open-source WebKit browser for macOS 26 and later.

Moon is an independent Swift 6 codebase inspired by
[Search](https://github.com/driceroland/Search). It uses SwiftUI, focused AppKit
bridges, and Apple's system WebKit. Sidebar tabs and multiple windows are the
default. There are no runtime package dependencies, accounts, or analytics. Selectively adapted
Search motion is credited in [third-party notices](THIRD_PARTY_NOTICES.md).

The current UI uses flat neutral chrome, compact pinned sites and system typography.
The welcome screen and Cmd-L share a centered Search-inspired search interface, with
local suggestions, arrow-key selection and restrained motion. Light, Dark and System
appearances are available in Browser Actions and Settings. [Design direction](Docs/UI-DIRECTION.md) and
[development skills](Docs/DEVELOPMENT-SKILLS.md) document the Search reference,
AutoSkills selection and Taste Skill workflow.

**Early development:** this is a runnable foundation, not a completed
Search-equivalent browser. See [the feature checklist](Docs/FEATURES.md) for
implemented behavior, limitations, and remaining work.

## Build

Requires macOS 26+, full Xcode 26 or later, and its Swift toolchain.

```sh
./build.sh release
open build/Moon.app
```

`./build.sh debug` makes a development build. The script uses a separate build
directory at `/private/tmp/MoonBuild` and ad-hoc signs the app. This signature is
for local testing; distributed builds still need Developer ID signing and
notarization. Moon uses only public WebKit APIs.

## What works in the foundation

- Multiple native windows, sidebar/horizontal tabs, pins, tab switching and reopening.
- Lazy session restoration, private tabs, and spaces with optionally separate sign-ins.
- On-demand address/search editor with local suggestions and eight search engine choices.
- History and bookmarks, searchable panels, bookmark HTML import/export.
- Two-page split view; native page navigation, gestures, zoom, Find and Web Inspector support.
- Basic network content blocking with site exceptions; element hiding and a text-focused reader.
- Picture in Picture for main-frame videos that support WebKit presentation mode.
- Downloads with a native destination panel; Share, printing and PDF export.
- Explicit password save/fill through an app-specific Keychain service, gated by system authentication.
- Unpacked WebExtensions through WebKit, with permission prompts and action popovers.
- Native Settings, appearance, URL/file handling and a default-browser request.

Private tabs use a nonpersistent WebKit store and are excluded from history,
saved sessions and recently closed tabs. Password operations and extensions are
disabled there. Files explicitly downloaded by the user are still ordinary files.
The current prototype does not promise disk-forensic anonymity.

## Keyboard

| Action | Shortcut |
| --- | --- |
| Location / new tab / new window | ⌘L / ⌘T / ⌘N |
| Private tab / close tab / close window | ⇧⌘N / ⌘W / ⇧⌘W |
| Search tabs / next / previous | ⌘K / ⌃Tab / ⌃⇧Tab |
| Jump to tab / reopen / duplicate | ⌘1–9 / ⇧⌘T / ⇧⌘D |
| Back / forward / reload | ⌘[ / ⌘] / ⌘R |
| Find / bookmark / show bookmarks | ⌘F / ⌘D / ⇧⌘B |
| Reader / Picture in Picture / element picker | ⇧⌘R / ⇧⌘P / ⇧⌘H |
| History / downloads / passwords | ⌘Y / ⇧⌘J / ⌥⌘L |
| Split / tab layout / sidebar | ⌥⌘N / ⇧⌘S / ⌃⌘S |
| Settings | ⌘, |

## Data

`~/Library/Application Support/Moon/Library.json` holds the library and normal
sessions. Website data belongs to WebKit. Installed extension folders live under
`~/Library/Application Support/Moon/Extensions/`. Passwords use the Keychain
service `org.moonbrowser.Moon.Passwords`, not the JSON library. There is no sync
or telemetry service. Search suggestions are local; pressing Return sends the
submitted query to the selected search engine.

## Test

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
./test.sh
```

`test.sh` runs core tests, builds the app, and launches an isolated WebKit smoke
test. GUI tests need an active macOS login session. Results are written to a
temporary directory printed by the script. See [validation](Docs/VALIDATION.md)
for the current evidence and remaining manual checks.

## Contributing

Start with a concrete issue and a small change. Keep browser data and private
state isolated; validate navigation policy, origin checks, and all file/credential
operations. New dependencies are considered on their merits. Architecture and
design are Moon's own; Search's repository conventions are not inherited.

MIT licensed. No Search code or branding has been copied into this initial implementation.
