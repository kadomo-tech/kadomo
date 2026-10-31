# kadomo-menu architecture

A resident, keyboard-first launcher for macOS. One small agent process (no Dock
icon) owns a pre-built panel and an in-memory index; a hotkey or the CLI only
toggles visibility. Nothing is scanned, parsed, or loaded from disk on a warm
open.

## Stack

- Swift 6.4, AppKit, SwiftPM. No Xcode project, no third-party dependencies.
- `KadomoMenuCore`: platform-free library (no AppKit). TOML parser, config and
  theme schema, command model, search/ranking, keyboard state machine, usage
  model, IPC message types, benchmark helpers. All unit-tested.
- `KadomoMenu`: the AppKit executable. Lifecycle, panel, providers (apps,
  system, settings, user commands), executor, hotkey, file
  watching, socket server. The same binary is the CLI: invoked as
  `kadomo-menu` (symlink) it talks to the running app over a Unix socket.

Linux/Wayland later means a new frontend target over the same Core.

## Modules and boundaries

| Concern | Where |
| --- | --- |
| Lifecycle (login item, hotkey, panel visibility, focus) | `App/AppDelegate`, `App/Launcher`, `Platform/HotKey`, `Platform/LoginItem` |
| Presentation | `UI/*` (panel, root view, row drawing, toast) |
| Search engine | `Core/Search` (`SearchIndex`) |
| Command registry | `Core/Catalog` (immutable snapshot) + `App/Registry` (sources) |
| Execution | `Platform/Executor` (off main thread, never a shell unless asked) |
| Platform adapters | `Platform/*Provider` |
| Theme engine | `Core/Theme` (schema, inheritance, validation) + `UI/Style` (NSColor/NSFont) |
| Configuration | `Core/Config` + `App/ConfigStore` (watch, reload, last-valid fallback) |
| Diagnostics | `Platform/Log`, `Core/Bench`, `kadomo-menu status|benchmark` |

## Data flow

```text
providers (apps, running apps, system, settings, themes, user commands)
   └─ Registry: per-source item lists ──(background)──> Catalog snapshot (items + tree + SearchIndex)
                                                            │ swapped on main
hotkey/CLI ─> Launcher.show() ─> LauncherModel(state machine) ─> rows ─> panel redraw
keyDown ─> KeyMap ─> LauncherModel.handle(event) ─> Effect(run/dismiss/reload)
Effect.run ─> Executor (async) ─> failure ─> toast + `status`
```

FSEvents on the config dir (and Kadomo's theme/commands dirs) and on the
application folders trigger targeted reloads. There is no polling.

## Keyboard state machine

State: `path` (category stack), `query`, `selection`, `mode` (`list`,
`actions(item)`, `confirm(item, action)`).

| Key | list mode | actions mode | confirm mode |
| --- | --- | --- | --- |
| typing | edit query, select first result | — (field disabled) | — |
| Up/Down, Ctrl-P/N | move selection (wraps) | move | — |
| Cmd-Up/Down, PgUp/PgDn | first/last, page | same | — |
| Enter | category: push; action: run (or confirm) | run action | run |
| Cmd-Enter | alternate (first secondary) action | — | — |
| Right | enter category if query empty or caret at end; else caret | — | — |
| Left | pop if query empty; else caret | close actions | cancel |
| Tab / Cmd-K | open actions | close actions | — |
| Backspace on empty query | pop category | — | — |
| Cmd-Backspace | clear query | — | — |
| Cmd-D | toggle favorite | — | — |
| Escape | confirm→cancel, actions→close, query→clear, path→pop, root→close | close | cancel |

Typing inside a category searches that subtree; with no hits there, the whole
registry is searched. Query prefixes (`>` commands, `@` apps, `!` system by
default) scope a search from anywhere. All bindings are remappable in
`[keys]`.

## Ranking

Deterministic tiers, best match per item wins, then a bounded usage boost
(≤ 99) so that a better tier is never buried by history:

exact title 1000 · exact alias 980 · title prefix 860–890 · alias prefix 850 ·
word prefix 790–800 · acronym 780 · all words prefixed 760 · exact keyword
720 · keyword prefix 680 · substring 560–600 · each word somewhere 550 ·
subtitle 350–450 · fuzzy 100–450.

Boost = frecency (log count × recency decay, ≤ 50) + learned query pick (≤ 30)
+ favorite (20). Ties break on shorter title, then title, then id. A 64-bit
byte mask per entry rejects most non-matches before any string work.

## Theme schema

TOML, every token optional, `extends = "<theme>"` for inheritance (cycle-safe).
Sections: `[colors]` (+ `[colors.light]` for `appearance = "auto"`), `[font]`,
`[geometry]`, `[effects]`, plus `layout = "center" | "top" | "compact"`.
A theme that fails validation is rejected whole and the last valid theme stays
on screen; the error shows in the panel banner and `kadomo-menu status`.

## Performance strategy

- Panel, views, fonts, colors built once per theme change, reused on every open.
- Index snapshot built off the main thread; search runs synchronously on main
  because it is sub-millisecond for normal registries (measured).
- Icons decoded lazily per visible row into a bounded cache, prewarmed in the
  background after indexing.
- Measured by `kadomo-menu benchmark`: search P50/P95/P99 on a synthetic
  10,000-item registry, panel show→drawn and query→drawn inside the running
  app, idle CPU and memory of the running process.

## Risks

- True hotkey→photons latency cannot be measured from inside the process; we
  measure hotkey handler → frame committed and document the gap.
- Lock screen, restart, and dark-mode toggling have no permission-free public
  API; they use `pmset` and Apple Events and may prompt once for Automation.
- Window/workspace control requires an external window manager (yabai,
  AeroSpace, or Kadomo's Rift integration via command files).
