# AeroSpace Kadomo

Kadomo's default window manager: Kadomo's build of
[AeroSpace](https://github.com/nikitabobko/AeroSpace) from
[`kadomo-tech/kadomo-aerospace`](https://github.com/kadomo-tech/kadomo-aerospace),
with [JankyBorders](https://github.com/FelixKratz/JankyBorders) around its windows
in the Kadomo theme's colors.

## What the fork adds

- Four layouts per workspace: **Tiles**, **Accordion**, **Dwindle** (each new
  window splits the focused one in two) and **Scrolling** (columns side by
  side; the view scrolls to the focused column).
- **Workspace Layout** in AeroSpace's own menu bar menu, and the
  `aerospace workspace-layout tiles|accordion|dwindle|scrolling` command. The
  layout is remembered per workspace and survives restarts.
- The menu bar shows the focused workspace's number and its apps' icons.

The fork's [`kadomo/README.md`](https://github.com/kadomo-tech/kadomo-aerospace/blob/feat/aerospace-layouts-and-borders/kadomo/README.md)
records its upstream base and every addition.

## Keys

| Keys | Action |
| --- | --- |
| ⌥ ← → ↑ ↓ | Focus the window to the left / right / up / down |
| ⌃⌥ ← → | Scrolling: previous / next column (nothing in the other layouts) |
| ⌥⇧ ← → ↑ ↓ | Move the window |
| ⌥ 1…9 / ⌥⇧ 1…9 | Go to / send the window to workspace 1–9 |
| ⌥ - / ⌥ = | Smaller / bigger |
| ⌥⇧ B | Even out sizes (Scrolling: columns back to half the screen) |
| ⌥⇧ T / A / D / S | Tiles / Accordion / Dwindle / Scrolling |
| ⌥⇧ F, ⌥ F | Float or tile the window, fullscreen |

Kadomo Menu lists them under Keybinds. They are in `aerospace.toml`.

**Mission Control.** macOS uses ⌃← and ⌃→ to switch Spaces, so Kadomo
leaves them alone; focus is on ⌥ and the arrows. ⌥← and ⌥→ normally jump a word in
text fields: while AeroSpace runs it takes those keys, in every app. To keep
word jumps, change the four `alt-left/right/up/down` lines in `aerospace.toml`
(for example to `ctrl-alt-shift-left`), and then reload the config from
AeroSpace's menu.

## What install.sh does

- **The app.** It downloads the build that `release.txt` pins (version, URL,
  SHA-256), checks the checksum, the bundle id `tech.kadomo.aerospace`, the
  version, and that `Contents/Helpers/aerospace` is from the same build. Only
  then does it replace `/Applications/AeroSpace Kadomo.app`. If any step
  fails, the app that was there stays and keeps running.
- **The command.** `~/.local/bin/aerospace` links to the app's command. One
  of yours there is set aside.
- **Configs.** It installs `~/.config/aerospace/aerospace.toml` and
  `~/.config/borders/bordersrc`. A different file of yours, and
  `~/.aerospace.toml` (AeroSpace refuses to start with two configs), is set
  aside as `<name>.before-kadomo` and comes back on uninstall. Your edits to
  Kadomo's own file are kept as `<name>.kadomo-edited` when it is written
  again.
- **JankyBorders** comes from Homebrew (`felixkratz/formulae/borders`),
  unless `borders` is already there.
- **Kadomo Menu** gets Services › AeroSpace, and the keys under Keybinds.
- **The window manager.** `kadomo-wm use aerospace` quits OmniWM if it runs
  (OmniWM stays installed), starts AeroSpace, and remembers the choice. At
  login, the agent `tech.kadomo.window-manager` starts the one picked.
  AeroSpace's own `start-at-login` stays off. If AeroSpace does not start,
  the manager that ran before runs again. `--install-only` installs without
  changing the choice.

macOS asks once to allow **AeroSpace Kadomo** in System Settings › Privacy &
Security › Accessibility. Each new build is new to macOS, so it may ask again
after an update.

`KADOMO_AEROSPACE_ZIP=/path/to/build.zip ./install.sh` installs a local build
(for development; no checksum).

## Borders in the theme's colors

`theme-set` renders `~/.config/kadomo/current/theme/borders.conf` from
`kadomo-theme-manager/themed/borders.conf.tpl` and runs
`kadomo-borders theme`. That rewrites only the `active_color` and
`inactive_color` lines of `bordersrc`, and hands the same colors to the
running `borders`. Width and style stay as you set them.

- **Focused window:** the theme's `hyprland_active_border`, else its `accent`.
- **Other windows:** `hyprland_inactive_border`, else `color8` (the theme's
  "bright black", a neutral gray).
- **Alpha** is kept (`0xAARRGGBB`). JankyBorders draws two-color diagonal
  gradients: a gradient of more colors keeps its first and last, and its
  angle picks the diagonal.

`borders = off` in `~/.config/kadomo/theme.conf` keeps JankyBorders out of the
theme for good. Without `borders` installed, theme changes skip it and never
install it.

With OmniWM picked, JankyBorders stays installed but does not run: OmniWM
draws its own border.

## The older AeroSpace builds

An older Kadomo shipped AeroSpace `0.21.3-kadomo.1` and `.2`.
`remove-legacy.sh` removes what those installed. It never touches this build
(`0.21.3-kadomo.3` and later, recorded in `aerospace-kadomo-installed.txt`),
even though both use the same app and command names. The top-level installer
runs it first.

## Building and releasing the app

Building the fork is a release step, never part of installing:

1. In the fork, build the release app with its command inside:
   `Contents/Helpers/aerospace`. Version it `<upstream>-kadomo.<n>`, with n of
   3 or more.
2. Sign and notarize it with the Kadomo Developer ID.
3. Zip it with `ditto -c -k --keepParent "AeroSpace Kadomo.app" AeroSpace-Kadomo-v<version>.zip`,
   and publish it on the fork's release `v<version>`.
4. Put the version, URL and `shasum -a 256` of the zip in `release.txt`.

`tests/test.sh` checks install, reinstall, switching window managers, a failed
start, login, failed and good updates, the legacy remover, theme colors for
every bundled theme, and uninstall. It runs in a throwaway HOME, with
stand-ins for brew, open and the rest.
