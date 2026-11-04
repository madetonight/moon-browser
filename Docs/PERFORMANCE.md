# Moon 0.4.3 performance pass

## Changes

- A tab retains an unchanged installation of page scripts. WebKit still runs
  those scripts for each new document. Settings, site styles, extension scripts,
  darkening, translation, content-controller changes and changed script objects
  invalidate the installation. Object identity is checked as well as the script
  plan, so the same source in a different content world cannot reuse the cache.
- The first ready frame appears immediately, removing the former 120 ms native
  opacity animation. A sleeping tab's low-resolution preview clears on first
  paint rather than waiting for a 450 ms commit timer. Finished navigation remains
  a fallback for pages that do not produce a first-paint notification.
- Pending recovery work is invalidated by a newer navigation or discarded view.
  Recovery does not restart a navigation while WebKit is still loading it.
- Incremental rendering stays enabled. Website media uses native WebKit decoding,
  playback and networking; cache validation and TLS verification are preserved.
  See Apple's [incremental-rendering API](https://developer.apple.com/documentation/webkit/wkwebviewconfiguration/suppressesincrementalrendering).
- The sidebar dock contains Extensions, Bookmarks, Downloads, Translate and Orbit.
  Right-swiping the sidebar brings in the New Space card. Existing profiles and
  spaces remain available through their other controls.

## Navigation measurements

Three alternating runs per version compared installed 0.4.2 with the signed
0.4.3 candidate on an Apple M1 Pro Mac with 16 GiB RAM and macOS 27.2, using separate disposable browser profiles and
normal WebKit scheduling. Each run navigated twelve times through a local
HTTP/1.1 fixture containing 500 paragraphs and a 3840 × 2160 PNG. The first
navigation was excluded from warm medians, giving 33 warm samples per version.
Video playback was measured separately from navigation to avoid hidden-media
preload scheduling delaying the page's load event.

| Median, warm local fixture | 0.4.2 | 0.4.3 |
| --- | ---: | ---: |
| Native command to request arrival at local server | 16.065 ms | 12.152 ms |
| WebKit response start | 2 ms | 2 ms |
| DOM content loaded | 17 ms | 18 ms |
| First contentful paint | 28 ms | 28 ms |
| Page load event | 27 ms | 28 ms |

Native-command timing includes the local test socket and app dispatch. WebKit
Navigation/Paint Timing begins inside the engine and excludes Moon's native
opacity animation. The observations support reduced setup/presentation delay;
they do not establish a general percentage improvement for remote websites.
First-navigation request times varied substantially: 272–465 ms for 0.4.2 and
173–469 ms for 0.4.3. DNS, server response, network conditions and website work
remain separate contributors to loading speed.

## Media quality verification

Every measured document retained the generated image's 3840 × 2160 natural
resolution. The signed candidate played a generated 3840 × 2160 H.264 stream,
with video-frame callbacks reporting the same decoded frame dimensions.

The test windows were covered/backgrounded for automated timing. Their frame
presentation was therefore subject to normal WebKit throttling. The standard
total/dropped-frame counters returned zero and were marked unavailable, rather
than interpreted as zero dropped frames. These runs do not certify foreground
frame rate, HDR color accuracy, a particular DRM service, or a site's maximum
streaming tier. Live screen capture was unavailable during the attempted visual
playback check. Available stream quality still depends on the source, service,
codec and hardware.

## Validation

A separate 38-tab workload used documents with 1,800 table rows and a DOM timer
scheduled every 250 ms. With all 38 loaded, the process family averaged
1,444.53 MB physical footprint, 2,009.24 MB summed RSS, and 0.38% settled CPU.
After explicitly sleeping 37 tabs, it averaged 187.69 MB physical footprint,
250.31 MB summed RSS, and 0.06% CPU. CPU 100% means one core. RSS can double-count
shared pages. This is one controlled workload run, not a measurement of 38
arbitrary websites or active streams, and it is not directly comparable with
the older macOS 26 workload report.

The complete local suite passed: 503 checks passed and one existing WebKit check
was skipped. New native checks cover stable script installation, content-world
mutation, setting/style invalidation, immediate first paint, cancellation of an
obsolete recovery, and completed/short/cancelled space-creation swipes.

The repeatable controller is `Scripts/benchmark-navigation.py`. It generates its
media under the temporary directory, uses a disposable named profile, and closes
its own process and server. Personal tabs, logins and browser records are excluded.
