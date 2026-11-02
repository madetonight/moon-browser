# Moon 0.3.2 beta

The current Moon design, with signed in-app updates and a drag-to-Applications installer.

- Minimal native sidebar, multiple windows, light/dark modes and optional Liquid Glass.
- Full-gradient Moon icon and a subtle 70 ms hover highlight. Tab titles and close controls stay responsive during quick pointer movements.
- Built-in website translation and Downloads beside Bookmarks in the sidebar.
- Native WebKit browsing adapted from Search 1.0.7, with the Moon welcome page and local Ollama integration.
- App Sandbox, hardened-runtime library validation, signed update feeds and archive verification remain enabled.
- Signed update checks run hourly; automatic download/install-on-quit follows Settings → About.

Apple silicon; macOS 26 or later. This beta is Apple Development signed and **not Apple-notarized**. macOS may require its first-launch approval. Sparkle authenticates updates; it does not confer Gatekeeper trust.

Install this connected beta manually once if your older Moon build says updates are not published. Later signed releases can arrive through the in-app updater. A complete old-to-new installation is verified separately from feed and archive authentication.

Moon includes MIT-licensed code from Search. Source and license notices accompany this release. Chrome extension compatibility depends on the APIs each extension uses; restricted Apple Passwords integrations require separate setup.
