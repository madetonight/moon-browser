# Orbit

Orbit is Moon's native activity summary and workspace. Open the stars button
beside Translate at the bottom of the sidebar, then choose **See more**.
Moon website tracking and the local engine connection both start off.

## Coverage

| Capability | Where it lives | Setup |
| --- | --- | --- |
| Moon website totals, top sites, today / 7 / 30 days | Native summary and Moon activity | Enable Moon tracking |
| Mac application totals, away-time exclusion | Native overview | Connect ActivityWatch; start window and away watchers |
| Full activity and device selection | All activity workspace | Official local engine |
| Timeline swimlanes, filters, trends, time spiral | Workspace | Recorded activity |
| Category sets, priorities, rules | Categories workspace | Configure your rules |
| Work reports, billable hours, stopwatch, reports | Workspace | Configure in ActivityWatch |
| Raw buckets/events, query explorer, import/export | Data & imports and Query explorer | Local engine |
| Alerts, search, graphs, privacy filters | Workspace | Relevant engine configuration |
| Optional AI analysis | Workspace | ActivityWatch's own service configuration and consent |
| Browser/editor/media plugins | Official compatible watchers | Install and configure separately |
| Optional multi-device sync | Official aw-sync module | Configure the same sync folder on each device |
| Watcher management and start at login | ActivityWatch menu bar companion | Explicit user choice |

The full workspace is served by ActivityWatch rather than a separately maintained
copy. ActivityWatch 0.14 or later is recommended. Its companion is installed
separately and is not included in Moon's app or installer. Accessibility permission
for window titles, plugins, notifications, services, and sync remain user choices.
Sync does not propagate settings or deletions.

Moon's custom web watcher is available in raw data and queries. ActivityWatch
0.14's standard browser application allowlist does not include Moon, so its
standard browser charts may omit those buckets. The native Moon activity view
provides Moon website totals independently. This integration does not claim to
have configured or tested every external watcher, device, AI service, or sync
destination.

## Privacy and boundaries

The native tracker records only profile ID, website name, hour and active seconds,
retained locally for 30 days. Private and internal pages are excluded. Idle time,
sleep and uncertain transitions are not credited. Clearing a profile clears its
native Orbit records.

If both tracking and the local engine connection are enabled, Moon sends sanitized
website origins and domain-only titles to its profile-specific web bucket. Page
paths, searches, credentials, full page titles and page contents are not sent.
ActivityWatch has its own retention and deletion controls for its database;
clearing native Orbit records does not erase the separate engine's records.

Native requests go only to `http://127.0.0.1:5600`, with bounded responses and
same-origin redirects. Optional native API keys are stored in Keychain and never
in URLs or injected scripts. The advanced workspace has its own nonpersistent
WebKit store, no Moon website sessions or extension bridges, and blocks remote
HTTP/WebSocket resources. Its sign-in uses ActivityWatch's own authentication.
External user-clicked links open separately.

Validation includes endpoint/secret-stripping and ledger regression tests, and a
real ActivityWatch 0.14 server protocol check using synthetic, in-memory data.
These checks do not certify third-party plugins or remote services.
