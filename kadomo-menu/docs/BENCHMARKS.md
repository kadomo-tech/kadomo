# Benchmarks

Measured 2026-10-29 on an Apple M3 (8 cores, 24 GB), macOS 27.0.1, Xcode
27.1 / Swift 6.4, release build (`-O -wmo`). Not yet measured on Intel; a
2018 Mac mini is the intended low-end reference.

## How to reproduce

```bash
./build.sh --open
kadomo-menu benchmark                 # search + live panel + idle CPU/memory
kadomo-menu benchmark --search-only   # no running app needed
kadomo-menu status                    # includes real hotkey → drawn latency so far
tools/dev-build.sh release && KADOMO_MENU_GUI=1 KADOMO_MENU_PROFILE=1 \
  KADOMO_MENU_CONFIG_DIR=/tmp/km KADOMO_MENU_STATE_DIR=/tmp/km \
  .build/direct/release/KadomoMenu    # per-operation profile, offscreen
```

`benchmark` opens and closes the real panel 100 times (it flashes on
screen), timing each step from the call to the committed frame
(`displayIfNeeded` + `CATransaction.flush`). The app also records every real
hotkey press from the Carbon callback to the committed frame; `status`
reports P50/P95/P99 of the last 500.

## Search (synthetic registry)

10,040 items (10,000 across 40 categories, with keywords, subtitles, and
Unicode titles), 20 queries from one letter to multi-word, CJK, accented,
fuzzy, and no-match, × 50 rounds, with usage history on every 37th item.

| | P50 | P95 | P99 | Target |
| --- | --- | --- | --- | --- |
| Index search | 0.53 ms | 1.10 ms | 1.13 ms | ≤ 10 ms P95 |
| Full model path (scoping, prefixes, boosts, rows) | 0.58 ms | 1.68 ms | 1.76 ms | |
| Index build (background) | 156 ms once | | | |

## Real catalog, per operation (offscreen profile)

209 items (97 apps on this Mac plus built-ins). Drawing renders into an
offscreen bitmap, which costs more than an on-screen layer update, so these
numbers are pessimistic for drawing.

| Operation | P50 | P95 | P99 |
| --- | --- | --- | --- |
| Launcher start → searchable (built-ins) | 21–27 ms | | |
| … apps indexed (background) | 88–101 ms | | |
| App scan, 97 apps (background) | 18.1 ms | 19.8 ms | |
| Catalog build, 209 items (background) | 2.6 ms | 2.7 ms | |
| Open: reset + rows + layout | 0.017 ms | 0.018 ms | 0.024 ms |
| Open: full draw | 1.92 ms | 2.01 ms | 2.22 ms |
| Query → model + rows + layout | 0.23 ms | 0.29 ms | 0.32 ms |
| Query → full draw | 2.87 ms | 3.32 ms | 5.22 ms |
| Selection move → redraw | 1.99 ms | 2.36 ms | 2.79 ms |
| Active-screen lookup (CGWindowList) | 0.038 ms | 0.054 ms | 0.23 ms |
| One app icon decode (background) | 0.43 ms | 0.59 ms | 0.95 ms |
| Theme switch | 0.81 ms | 0.94 ms | 2.5 ms |
| Cached Omarchy theme switch (appearance → style; 2026-10-31) | 0.029 ms | 0.032 ms | 0.10 ms |
| Config reload, catalog inline | 4.1 ms | 4.4 ms | |
| Memory after start + app scan | 10.7 MB footprint | | |

## The three most expensive operations

1. **Drawing the result rows** (2–3 ms per full redraw). Text layout of
   ~10 rows dominates. Already done: one draw pass per row with no
   subviews, shared paragraph styles, no per-draw color formatting, title
   measuring only when a subtitle needs placing, and selection changes
   redraw just the two affected rows on screen. The remaining cost is
   CoreText itself.
2. **Scanning applications** (18 ms for 97 apps). Runs once at startup and
   after FSEvents reports a change in an app folder, always off the main
   thread. Never on open.
3. **Index build** (2.6 ms real, 156 ms for 10,000 items). Off the main
   thread, swapped in atomically; searches never wait for it.

Nothing on the open or typing path touches the disk, the network, or another
process. The only per-open system call is the window-list lookup for the
active screen (0.04 ms).

## Still to measure on a real desktop

These need the app running in a normal login session with a window server.
The development sandbox used for this build could not run the AppKit event
loop or bind the CLI socket, so they are not reported yet. Run
`kadomo-menu benchmark` and add the output here.

| Metric | Target | Measured |
| --- | --- | --- |
| Hotkey → interactive, warm P50 / P95 | ≤ 35 / ≤ 75 ms | pending |
| Query → updated results on screen P95 | ≤ 20 ms | pending (offscreen: 3.3 ms) |
| Cold start → interactive P95 | ≤ 500 ms | pending (in-process start: ~25 ms + dyld/AppKit launch) |
| Idle CPU | ≈ 0 | pending (no timers or polling exist) |
| Idle memory | < 50 MB | pending (10.7 MB before any window is shown) |
| 2018 Intel Mac mini | | pending |

## Limitations

- The hotkey latency starts at the Carbon callback, not the key press;
  the system's event delivery before that is not visible to the app.
- "Drawn" means the frame was committed to the window server, not that
  pixels reached the display (add one display refresh, ≤ 16.7 ms at 60 Hz).
- The offscreen profile does not drain autorelease pools between iterations,
  so its final memory figure (60 MB) reflects retained bitmaps, not the app.
