# SketchyBar

The status bar from [omarchy4mac](https://github.com/dividendsolo/omarchy4mac)
(`sketchybar/`, MIT, see `LICENSE.omarchy4mac`), adapted for Kadomo: OmniWM's
workspaces instead of AeroSpace's, Kadomo Menu instead of Hammerspoon's, and
the colors of the current Kadomo theme.

```sh
./install.sh     # or: ./install.sh --dry-run
./uninstall.sh
```

| What | Where |
| --- | --- |
| SketchyBar, media-control, switchaudio-osx, bun | Homebrew, unless already installed. SketchyBar comes from the `felixkratz/formulae` tap |
| Hack Nerd Font, sketchybar-app-font | Homebrew, unless already installed, then registered with macOS (`fonts.js`), as Font Book does. A file in `~/Library/Fonts` isn't always enough: macOS can leave it out of its list of fonts, and the bar then shows `[?]` for icons |
| The bar's config | `config/` is copied to `~/.config/sketchybar`. A different folder there is backed up first |
| The macOS menu bar | Set to hide, because the bar takes its place. It shows when the pointer reaches the top of the screen |
| OmniWM's `settings.toml` | `ipcEnabled = true`, which the workspace items need, and a top gap of at least 32 under `[gaps.outer]`, so windows stay below the bar |

`~/Library/Application Support/kadomo/sketchybar-installed.txt` records all of
this, including how each setting was before, and `uninstall.sh` reads it to put
everything back.

## The items

| Item | Shows | Click | Plugin |
| --- | --- | --- | --- |
| Logo | | Kadomo Menu | |
| Workspaces 1–5 | The focused one is highlighted | Goes to that workspace | `omniwm.sh` |
| Front app | The focused app's icon and name | | `front_app.sh`, `icon_map.sh` |
| Music | What's playing in any player, from macOS Now Playing | Play or pause; next | `media.sh` |
| Indicators | Only while on: `caffeinate`, Do Not Disturb | | `indicators.sh` |
| Clock | Day and time | Date & Time settings | `clock.sh` |
| Weather | From wttr.in, located by IP address | Opens wttr.in | `weather.sh` |
| Updates | Outdated Homebrew packages, hidden at zero | Upgrades them in Ghostty | `updates.sh` |
| Theme | The current Kadomo theme | Switches to a random theme | `clock.sh`, `theme_random.sh` |
| Stand-up timer | Only while `~/.hermes/standup_timer.sh` runs | | `standup.sh` |
| Agents | Claude Code's 5-hour and weekly limits, else today's spend | `ccusage daily` in Ghostty | `agents.sh`, `agent_usage_claude.py` |
| Bluetooth, Wi-Fi, volume, battery | Their state | Their settings | `bluetooth.sh`, `wifi.sh`, `volume.sh`, `battery.sh` |

`displays.sh` keeps the centre items clear of the notch: on a built-in display
with a notch, the clock and theme move to the right, and the weather, updates,
and indicators show on external displays only.

`agent_usage_claude.py` reads Claude Code's login from the macOS Keychain and
sends its token to Anthropic's usage endpoint, at most every 15 minutes, and
nowhere else. When the limits are unknown, `agents.sh` runs `bunx ccusage`,
which downloads that package from npm. `weather.sh` asks wttr.in every 30 minutes.
To turn any item off, remove it from `~/.config/sketchybar/sketchybarrc`.

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
