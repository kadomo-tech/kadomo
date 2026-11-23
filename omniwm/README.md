# OmniWM

[OmniWM](https://github.com/BarutSRB/OmniWM) is Kadomo's window manager. It
does niri-style scrolling columns and dwindle tiling, and it draws its own
border around the focused window. It needs macOS 26 or later on Apple silicon,
and version 0.8 or later, whose own menu bar is why Kadomo no longer installs
SketchyBar. A copy Kadomo installed is upgraded to 0.8 automatically; one you
installed yourself is left for you to upgrade (its own updater, or
`brew upgrade --cask omniwm` if you used Homebrew).

```sh
./install.sh     # or: ./install.sh --dry-run
./install.sh --only omniwm   # everything but the Omarchy logo and the volume icon
./uninstall.sh
```

| What | Where |
| --- | --- |
| OmniWM | `/Applications/OmniWM.app`, from Homebrew (`brew install --cask omniwm`) unless it is already on the Mac |
| `kadomo-omniwm` | `~/.local/bin`: start, stop, status, theme, restore-borders, menu. A command that runs and exits; nothing of Kadomo's runs in the background |
| Workspace keys | Ctrl+Option+Left / Right for previous / next workspace, in `~/.config/omniwm/settings.toml` |
| Kadomo Menu | Services › OmniWM: Start, Stop, Match Theme Colors, Edit Settings, and OmniWM's keys in Keybinds (`~/.config/kadomo/menu/commands/omniwm.toml`) |
| Omarchy logo | In OmniWM's menu bar, in place of the Apple logo (`~/.config/omniwm/shell/widgets/apple-menu`) |
| Volume icon | In OmniWM's menu bar, the speaker icon without the percentage (`~/.config/omniwm/shell/widgets/volume`) |

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

## The Omarchy logo

OmniWM's menu bar starts with the Apple logo, its built-in `apple-menu`
widget. Kadomo puts the Omarchy logo there instead, the glyph Omarchy's own bar
shows, in the bar's text color; clicking it still opens the Apple menu.
`shell/apple-menu/init.luau` is the widget, and the installer copies it to
`~/.config/omniwm/shell/widgets/apple-menu/`, where a widget takes the place
of OmniWM's own of the same name. OmniWM picks it up without a restart, and
OmniWM itself is not changed.

It is on by default. To keep the Apple logo, turn off Kadomo Core › Omarchy
logo under Advanced in the top-level installer, or run `./install.sh --only
omniwm` here. The uninstaller takes it away again, and the Apple logo comes
back. An `apple-menu` widget of your own there is never replaced or removed:
the widget's first line, `-- Kadomo:`, is how Kadomo knows its own.

Because it takes the place of OmniWM's widget, a change OmniWM makes to its own
`apple-menu` in a later release does not show while Kadomo's is there.

## The volume icon

OmniWM's `volume` widget shows a speaker icon and the volume as a percentage.
Kadomo's, `shell/volume/init.luau`, shows the speaker icon alone: its waves
still give a rough idea of how loud it is, and clicking it (the output panel)
and scrolling over it (louder, quieter) work as before. The installer copies it
to `~/.config/omniwm/shell/widgets/volume/`, the same way as the logo. OmniWM
lets only its own widgets `require` its helpers, so the parts of its bar skin
and audio code the widget needs are copied into it (GPL-2.0, like OmniWM), and
it looks like the rest of the bar. A change OmniWM makes to its own `volume`
widget in a later release does not show while Kadomo's is there.

It is on by default. To keep the percentage, turn off Kadomo Core › Volume icon
only under Advanced in the top-level installer, or leave `volume` out of
`./install.sh --only` here. The uninstaller takes it away again, and a `volume`
widget of your own is never replaced or removed.

## Keybinds

Kadomo Menu › Keybinds lists OmniWM's hotkeys. Kadomo leaves the defaults as
they are and adds two that OmniWM leaves unassigned: Ctrl+Option+Left and Right
for the previous and next workspace. OmniWM writes `settings.toml` on its first
start, so `kadomo-omniwm workspace-keys` sets them after that. It sets each one
once, and only if that hotkey is unassigned and no other hotkey uses the key, so
your own choices stay. `~/Library/Application Support/kadomo/omniwm-workspace-keys.txt`
records what it set, and uninstalling takes those off unless you have changed them.

If you change a hotkey in OmniWM's Settings › Hotkeys, edit `KEYBINDS` in
`bin/kadomo-omniwm` to match.

## AeroSpace from an older Kadomo

Kadomo used to ship AeroSpace with Scrolling as a second window manager.
`remove-aerospace.sh` removes what it installed: Kadomo's build of the app,
`kadomo-aerospace` and `kadomo-workspace-layout`, the `~/.local/bin/aerospace`
link, the login agents, the scrolling settings, the menu entries, and the
saved choices. A regular AeroSpace you installed yourself stays, but is quit.
The top-level `install.sh` and `uninstall.sh` and this folder's `install.sh`
run it; `dotfiles/uninstall.sh --retired` removes AeroSpace's config and
JankyBorders.

## SketchyBar from an older Kadomo

Kadomo used to ship SketchyBar as its status bar. OmniWM 0.8 and later draw
their own menu bar, so Kadomo no longer installs SketchyBar, and
`remove-sketchybar.sh` removes what an older Kadomo installed for it: its
config, Kadomo Menu entries, the fonts it registered, and what it installed
from Homebrew; the macOS menu bar and OmniWM's IPC and top gap go back to how
they were. A SketchyBar you installed yourself stays, but is stopped if
Kadomo had been running it. The top-level `install.sh` and `uninstall.sh` and
this folder's `install.sh` run it.

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
