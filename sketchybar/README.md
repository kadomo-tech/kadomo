# SketchyBar

The status bar from [omarchy4mac](https://github.com/dividendsolo/omarchy4mac)
(`sketchybar/`, MIT, see `LICENSE.omarchy4mac`), adapted for Kadomo: OmniWM's
workspaces instead of AeroSpace's, Kadomo Menu instead of Hammerspoon's, and
the colors of the current Kadomo theme. It's styled after Omarchy's bar: solid,
in one monospace font, with icons in the theme's foreground color.

```sh
./install.sh     # or: ./install.sh --dry-run
./uninstall.sh
```

| What | Where |
| --- | --- |
| SketchyBar, switchaudio-osx | Homebrew, unless already installed. SketchyBar comes from the `felixkratz/formulae` tap |
| JetBrainsMono Nerd Font, sketchybar-app-font | Homebrew, unless already installed, then registered with macOS (`fonts.js`), as Font Book does. A file in `~/Library/Fonts` isn't always enough: macOS can leave it out of its list of fonts, and the bar then shows `[?]` for icons |
| The bar's config | `config/` is copied to `~/.config/sketchybar`. A different folder there is backed up first |
| The macOS menu bar | Set to hide, because the bar takes its place. It still drops down when the pointer reaches the top of the screen, so the bar is drawn above it (`topmost=on`) to keep its clicks. That also covers the app menus (File, Edit, and so on) |
| Kadomo Menu | Services › SketchyBar: Start, Stop, Restart, through `brew services`. Stop also keeps the bar off at login until you start it again. Services › Menu Bar: Show or Hide (⌥⇧M), Show, Hide. Both in `~/.config/kadomo/menu/commands/sketchybar.toml` |
| OmniWM's `settings.toml` | `ipcEnabled = true`, which the workspace items need, and a top gap of at least 32 under `[gaps.outer]`, so windows stay below the bar |

`~/Library/Application Support/kadomo/sketchybar-installed.txt` records all of
this, including how each setting was before, and `uninstall.sh` reads it to put
everything back.

## The items

| Item | Shows | Click | Plugin |
| --- | --- | --- | --- |
| Logo | | Kadomo Menu | |
| Menu bar | Highlighted while the macOS menu bar shows | Shows it, or puts it back; so does ⌥⇧M. See [The macOS menu bar](#the-macos-menu-bar) | `menu_bar.sh` |
| Workspaces 1–9 | The focused one is a dot, the others dim numbers | Goes to that workspace | `omniwm.sh` |
| Front app | The focused app's icon and name | | `front_app.sh`, `icon_map.sh` |
| Clock | Day and time, 24-hour or 12-hour | Switch 24-hour and 12-hour; right click: Date & Time settings | `clock.sh` |
| Weather | The temperature from wttr.in, located by IP address | Opens wttr.in | `weather.sh` |
| Do Not Disturb | Only while on | | `indicators.sh` |
| Updates | Outdated Homebrew packages, hidden at zero | Upgrades them in Ghostty | `updates.sh` |
| Stand-up timer | Only while `~/.hermes/standup_timer.sh` runs | | `standup.sh` |
| Bluetooth, Wi-Fi, volume | Their state, as an icon | Their settings | `bluetooth.sh`, `wifi.sh`, `volume.sh` |
| Battery | An icon and the percentage, red below 20% | Its settings | `battery.sh` |

Everything from the clock on sits on the right, on every display, which keeps it
clear of the notch.

`weather.sh` asks wttr.in every 30 minutes.
To turn any item off, remove it from `~/.config/sketchybar/sketchybarrc`.

## The macOS menu bar

The bar covers the app menus. To reach them, click the menu bar item, next to
the logo: the menu bar shows, and the bar moves down below it. So do OmniWM's
windows, through a temporary rise in the top gap in `settings.toml`. Click again
to put everything back; a top gap you changed in the meantime stays. Kadomo Menu
does the same under Services › Menu Bar.

Option-Shift-M does it from anywhere. Kadomo Menu holds that key, so it has to be
running; to use another, change `hotkey` in the `kadomo-menu-bar-toggle` command in
`sketchybar.sh`.

## See-through

Double click an empty part of the bar and its background goes to 50% opacity;
text and icons stay solid. Each double click after that goes to the next of 25%,
10%, 100%, and 50% again. A reload or a theme switch makes it solid again.
SketchyBar reports no clicks on the
empty bar, so two invisible items catch them: `empty_left` and `empty_right`, of
fixed widths, on either side of the notch. On a wide display, the empty space
beyond them does nothing.

## Workspaces

`sketchybarrc` starts `plugins/omniwm_watch.sh`, which runs
`omniwmctl watch active-workspace` for as long as the bar runs, and tries again
when OmniWM isn't up yet. On a Mac without OmniWM, the workspace items are left
out and nothing is started.

## Colors

`kadomo-theme-manager/themed/sketchybar-colors.sh.tpl` renders
`~/.config/kadomo/current/theme/sketchybar-colors.sh` on every `theme-set`, which
then runs `sketchybar --reload`. `config/colors.sh` sources that file, and falls
back to Tokyo Night when there is no theme yet.

## Tests

```sh
tests/test.sh
```

They run in a throwaway HOME with stand-ins for Homebrew and the system
commands. Nothing is installed.
