# kadomo-menu

A fast, keyboard-first launcher and command menu for macOS. Press a hotkey,
type or browse, press Enter. It is part of the [Kadomo](https://github.com/kadomo-tech)
desktop, and works on its own on any Mac.

```text
╭──────────────────────────────────────────╮
│  Go…                                     │
│ ▌ ⊞  Apps                            ›   │
│   🎨 Appearance                      ›   │
│   ⌨  Keybinds                        ›   │
│   ☰  Services                        ›   │
│   ⓘ  About                           ›   │
│   ⏻  System                          ›   │
╰──────────────────────────────────────────╯
```

- **Search and menus together.** Type to search apps, settings panes, system
  actions, themes, and your own commands at once, or walk the categories
  with the arrow keys.
- **Resident and instant.** One small background process keeps the panel and
  an in-memory index ready. Opening never touches the disk.
- **Themeable.** Colors, fonts, geometry, effects, and layout come from TOML
  themes with inheritance and live reload. Four presets ship.
- **Scriptable.** Add commands in TOML. Drive the running launcher with the
  `kadomo-menu` CLI.
- **Native.** Swift and AppKit, no dependencies, no web views, no telemetry.

## Install

Needs macOS 14 or later. No Xcode or compiler is needed.

```bash
./install.sh
```

The repo includes the prebuilt app in `release/`: one build that runs natively
on Apple silicon and Intel Macs, on macOS 14 and later. The installer checks it
against its SHA-256, installs `~/Applications/KadomoMenu.app`, links the
`kadomo-menu` command, installs the JetBrainsMono Nerd Font the default theme
uses (a pinned, checksum-verified Nerd Fonts release into `~/Library/Fonts`,
skipped when it is already there), and starts the launcher. A checklist opens first (Space
toggles, Enter reviews, q quits); `--yes` skips it, and `--only app,font,start` skips it
and installs just the items named. To install a different zip,
such as one copied from another Mac, run `./install.sh --zip PATH`.

To replace the bundled build after changing the code, run
`./build.sh --universal --package`, copy `dist/KadomoMenu-<version>-x86_64-arm64.zip`
into `release/`, and update `RELEASE_VERSION` and `RELEASE_SHA256` in
`install.sh`.

Developers who want to build from source can run `build.sh`, which needs Xcode
or the command line tools with Swift 6.2+. It builds a release binary, installs
`~/Applications/KadomoMenu.app`,
signs it (your Apple Development certificate if you have one, ad hoc
otherwise), and links the CLI to `~/.local/bin/kadomo-menu`. Add
`~/.local/bin` to `PATH` if it is not there. On first launch the app writes
a commented `~/.config/kadomo-menu/config.toml` and registers itself to start
at login (turn that off with `launch_at_login = false`).

Press **⌥Space** (Option-Space). If something else owns that shortcut, the
launcher shows a warning and you can pick another `hotkey` in config.toml.

## Run it on another Mac

kadomo-menu runs on macOS 14 Sonoma or later, on Apple silicon and Intel
(a 2018 Mac mini on macOS 14 or 15 works). There are two ways to get it
there.

### Option A: copy a prebuilt app (no Xcode on the other Mac)

On the Mac that has Xcode, build one app that contains both Apple silicon
and Intel code, and zip it:

```bash
./build.sh --universal --package
```

This writes `dist/KadomoMenu-<version>-x86_64-arm64.zip`. Copy the zip to
the other Mac (AirDrop, a USB stick, `scp`, …), then on that Mac:

```bash
mkdir -p ~/Applications ~/.local/bin
ditto -x -k ~/Downloads/KadomoMenu-*-x86_64-arm64.zip ~/Applications
xattr -dr com.apple.quarantine ~/Applications/KadomoMenu.app
ln -sf ~/Applications/KadomoMenu.app/Contents/MacOS/KadomoMenu ~/.local/bin/kadomo-menu
open ~/Applications/KadomoMenu.app
```

The `xattr` line is needed because the app is signed for your own use, not
notarized by Apple. Without it, macOS says the app "cannot be verified" and
won't open it; you can also allow it once under System Settings › Privacy &
Security › Open Anyway. Add `~/.local/bin` to `PATH` in `~/.zshrc` to use
the CLI there (`export PATH="$HOME/.local/bin:$PATH"`).

### Option B: build it on that Mac

The other Mac needs Xcode 26 or later (Swift 6.2+), which needs macOS 15.6
or later. On a 2018 Mac mini that means macOS 15 Sequoia.

```bash
git clone git@github.com:kadomo-tech/kadomo.git
cd kadomo/kadomo-menu
./build.sh --open
```

### Checking it on the other Mac

```bash
kadomo-menu status       # hotkey registered? theme, items, memory
kadomo-menu benchmark    # search, live panel, idle CPU and memory
```

Paste the `benchmark` output into [docs/BENCHMARKS.md](docs/BENCHMARKS.md)
as a new machine column. Each Mac keeps its own config in
`~/.config/kadomo-menu`; copy that folder over to bring your themes and
commands along.

## Uninstall

```bash
./uninstall.sh
```

`uninstall.sh` lists only what it finds on this Mac and removes it after a
review: it turns off launch at login and quits the app, then removes the app
bundle, the `kadomo-menu` command, the font files the installer added (a copy
you installed yourself stays), your config and themes, usage history,
preferences, caches, logs, the build cache, and the Accessibility and
Automation grants macOS recorded for the app. Pass `--yes` to remove everything
it finds without the checklist. The repo checkout is never touched.

## Using it

The home menu lists categories. Enter or → opens one; ← or Backspace goes
back. Typing searches everything (inside a category it searches that
category first, then everything). Tab shows more actions for the selected
row, such as Reveal in Finder or Quit for a running app.

| Key | Does |
| --- | --- |
| type | search |
| ↑ ↓ · ⌃P ⌃N | move |
| ⌘↑ ⌘↓ · PgUp PgDn | first, last, page |
| ↩ | run, or open the category |
| ⌘↩ | alternate action (the first action in the Tab list) |
| → | open category (only when the caret is at the end of the search) |
| ← | back (only when the search is empty) |
| ⌫ on an empty search | back |
| ⇥ · ⇧⇥ · ⌘K | actions for the selected row |
| ⌘D | add or remove a favorite (favorites sit at the top of home) |
| ⌘⌫ | clear the search |
| ⌘R | reload configuration |
| ⌘, | edit config.toml |
| esc | cancel confirm → close actions → clear search → back → close |

Prefixes scope a search: `@` apps, `!` system. All keys
and prefixes can be changed in config.toml. Keybinds in the menu lists the
current ones.

Ranking puts exact names first, then prefixes, word starts (`code` →
Visual Studio Code), initials (`vsc`), keywords and aliases (`vscode`,
`reboot`), substrings, and fuzzy matches. What you run often and what you
picked for the same query before move up, but never above a better kind of
match. History stays in `~/Library/Application Support/kadomo-menu/usage.json`.

## Configuration

`~/.config/kadomo-menu/config.toml` (or `$XDG_CONFIG_HOME/kadomo-menu`).
Everything is optional; the written file lists every key, commented out.
Saving applies changes at once. A file with a syntax error is ignored, and
the last good configuration stays in effect, with the error shown at the
bottom of the launcher.

```bash
kadomo-menu config check    # validate config, themes, and commands
kadomo-menu config path     # where everything lives
```

See [examples/config.toml](examples/config.toml).

### Your own commands

Put `[[command]]` tables in `~/.config/kadomo-menu/commands/*.toml` (or in
config.toml):

```toml
[[command]]
id = "open-kadomo"
title = "Open Kadomo"
category = "development"
keywords = ["dotfiles"]
exec = "/usr/bin/open"
args = ["-a", "Ghostty", "~/Code/kadomo"]
```

`exec` + `args` runs a program directly with an argument array: no shell,
no injection. `shell = "…"` exists for scripts you wrote yourself. Also
`url`, `open` (a file or folder), and `app`. Commands can define secondary
actions, ask for confirmation, stay open, and live in nested categories.
Full reference: [docs/COMMANDS.md](docs/COMMANDS.md).

### Themes

```bash
kadomo-menu theme list
kadomo-menu theme set kadomo-terminal
```

Or pick one under Appearance › Kadomo Themes: switching is live. Presets:
**Kadomo Dark** (default, JetBrainsMono Nerd Font), **Kadomo Minimal** (system font, blur, follows
light/dark), **Kadomo Terminal** (dense, monospaced, no icons), and
**Kadomo Light**. Make your own in `~/.config/kadomo-menu/themes/<name>.toml`
with `extends = "kadomo-dark"` and only the tokens you change. Appearance ›
Customize Current Theme writes a starter file. Reference:
[docs/THEMES.md](docs/THEMES.md).

### Omarchy themes

Appearance › Omarchy Themes browses Omarchy's official themes and the
community catalog, installs from Git or a folder, previews a theme while it
is selected, and applies it: to the launcher, and with the theme manager to
every app it styles (Ghostty, btop, Neovim, Vim, ...) and the wallpaper. It is a separate theme
library with its own storage; Kadomo's themes never depend on it, and
`[omarchy] enabled = false` turns it off. Back to Kadomo's theme with Use
Kadomo Theme or any Kadomo theme. Details, safety, and limits:
[docs/OMARCHY.md](docs/OMARCHY.md).

```bash
kadomo-menu omarchy official
kadomo-menu omarchy install tokyo-night
kadomo-menu omarchy install https://github.com/OldJobobo/omarchy-lumon-theme
```

## Kadomo integration

The same app runs standalone or inside Kadomo. With `[kadomo] mode = "auto"`
(the default) it also reads, when they exist:

- `~/.config/kadomo/current/theme/kadomo-menu.toml`: the desktop's current
  theme for the launcher. Select it with `theme = "kadomo"`; it changes
  live when Kadomo switches themes. When Kadomo lists its desktop themes under
  Appearance › Kadomo Themes, those are the only Kadomo themes offered: each styles every
  app, the launcher included, and Customize Current Theme and Open Themes
  Folder are left out.
- `~/.config/kadomo/menu/commands/*.toml`: commands and categories Kadomo
  registers (Rift window actions, reload commands, workflows).

Nothing else about Kadomo is assumed. Set `mode = "off"` to ignore both.

Window and workspace commands (Rift and others) plug in through command
files.

## CLI

```bash
kadomo-menu open [--category system] [--query wifi]
kadomo-menu toggle | close | reload | status | quit
kadomo-menu theme list | current | provider | set <name>
kadomo-menu omarchy list | official | community | install | import | check | apply | update | remove
kadomo-menu commands list [--json] [--categories] [--category <id>]
kadomo-menu commands run <id> [--yes]
kadomo-menu config check | path
kadomo-menu benchmark
kadomo-menu login on | off | status
```

The CLI talks to the running app over a Unix socket only you can open
(`~/Library/Application Support/kadomo-menu/menu.sock`). `open` and
`toggle` start the app when it is not running. Bind `kadomo-menu toggle`
in skhd or Hammerspoon if you prefer their key handling.

## Performance

Measured numbers, test conditions, and the method are in
[docs/BENCHMARKS.md](docs/BENCHMARKS.md). Run `kadomo-menu benchmark` on
your machine; it prints search latency over 10,000 synthetic items, timed
open/type/close cycles of the real panel, idle CPU, memory, and the latency
of your real hotkey presses so far.

## Permissions

None for the core: the hotkey uses `RegisterEventHotKey`, apps open through
`NSWorkspace`, and the active screen is found from window bounds, which need
no permission. Toggle Dark Mode and Restart / Shut Down / Log Out use Apple
Events, so macOS asks once for Automation the first time you run one. No
Accessibility, Screen Recording, or Input Monitoring. No network access.

## Development

```bash
swift build && swift test             # SwiftPM
tools/dev-build.sh [release|test]     # swiftc directly (works in sandboxes that block SwiftPM)
tools/selftest.sh                     # in-process end-to-end checks on a throwaway config
tools/check-cli.sh                    # the CLI over the real socket against a headless app
tools/snap.sh                         # offscreen PNGs of every theme and state → .build/shots
tools/omarchy-compat.sh               # every official Omarchy theme and the catalog, through the adapter
```

Architecture: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Known limitations

See [docs/BENCHMARKS.md](docs/BENCHMARKS.md#limitations) for measurement
limits. Product limits:

- **Lock Screen** turns the display off (`pmset displaysleepnow`); it locks
  when "Require password after screen saver begins or display is turned off"
  is set to Immediately. macOS has no public lock API.
- System Settings pane links use Apple's documented URL identifiers; Apple
  renames panes between releases, so one may open the top level instead.
- Fuzzy matching is byte-based on folded text. CJK and other scripts match
  exactly and by substring; fuzzy gaps inside multi-byte characters are not
  meaningful.
- No app icon yet: the app is an agent and never shows one in the Dock.
