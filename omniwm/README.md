# OmniWM

[OmniWM](https://github.com/BarutSRB/OmniWM) is Kadomo's window manager. It
does niri-style scrolling columns and dwindle tiling, and it draws its own
border around the focused window. It needs macOS 26 or later on Apple silicon.

```sh
./install.sh     # or: ./install.sh --dry-run
./uninstall.sh
```

| What | Where |
| --- | --- |
| OmniWM | `/Applications/OmniWM.app`, from Homebrew (`brew install --cask omniwm`) unless it is already on the Mac |
| `kadomo-omniwm` | `~/.local/bin`: start, stop, status, theme, restore-borders, menu. A command that runs and exits; nothing of Kadomo's runs in the background |
| Kadomo Menu | Services › OmniWM: Start, Stop, Match Theme Borders, Edit Settings, and OmniWM's keys in Keybinds (`~/.config/kadomo/menu/commands/omniwm.toml`) |

macOS asks once to allow OmniWM under Privacy & Security › Accessibility and
Input Monitoring. OmniWM also needs "Displays have separate Spaces" on
(System Settings › Desktop & Dock); the installer tells you if it is off.

## Starting at login

OmniWM starts itself at login: turn that on once in OmniWM's settings (its
menu bar icon › Settings). macOS may ask you to allow it under System
Settings › General › Login Items. The installer reminds you. Older Kadomo
installs started it with a login agent
(`~/Library/LaunchAgents/tech.kadomo.omniwm-login.plist`); the installer and
uninstaller remove it.

## Keybinds

Kadomo Menu › Keybinds lists OmniWM's default hotkeys, which Kadomo leaves
as they are. If you change one in OmniWM's Settings › Hotkeys, edit
`KEYBINDS` in `bin/kadomo-omniwm` to match.

## AeroSpace from an older Kadomo

Kadomo used to ship AeroSpace with Scrolling as a second window manager.
`remove-aerospace.sh` removes what it installed: Kadomo's build of the app,
`kadomo-aerospace` and `kadomo-workspace-layout`, the `~/.local/bin/aerospace`
link, the login agents, the scrolling settings, the menu entries, and the
saved choices. A regular AeroSpace you installed yourself stays, but is quit.
The top-level `install.sh` and `uninstall.sh` and this folder's `install.sh`
run it; `dotfiles/uninstall.sh --retired` removes AeroSpace's config and
JankyBorders.

## Border colors from the theme

The theme manager renders `~/.config/kadomo/current/theme/omniwm.toml` from
`themed/omniwm.toml.tpl`. A theme's `hyprland_active_border` gradient (or
its accent) becomes OmniWM's `[borders.color]` (the first color) and, when
there are two colors, a `[borders.gradient]` from top left to bottom right.
On every switch, `theme-set` runs `kadomo-omniwm theme`. That command
replaces only those color tables in `~/.config/omniwm/settings.toml`
(`[borders.color]`, `[borders.darkColor]`, `[borders.gradient...]`) and
writes the file atomically, and OmniWM reloads it. The border width, glow,
and everything else stay as you set them. A fragment holding anything but
border colors is refused.

The colors settings.toml had before Kadomo first changed them are kept in
`~/Library/Application Support/kadomo/omniwm-borders-before.toml`.
Uninstalling OmniWM's part of Kadomo, or the theme manager, puts them back.
