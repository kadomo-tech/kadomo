# kadomo-theme-manager

One command switches every themed app on the Mac to one palette and
wallpaper, live, without restarting anything:

```sh
theme-set gruvbox             # or "Gruvbox"
theme-set catppuccin-latte   # everything flips to light, macOS included
theme-bg-next                # the theme's next wallpaper
```

Or pick one in Kadomo Menu under **Appearance › Themes** (Ctrl+Option+Shift+Space
goes straight there), and a wallpaper under **Appearance › Backgrounds**
(Ctrl+Option+Space). Every theme there styles every app, the menu included.

Built in: **tmac2k** (the original Kadomo look with its neon wallpapers, and the default),
Catppuccin, Catppuccin Latte (light), Gruvbox, Rosé Pine (Dawn, light), and
[Sora](https://soratheme.com/).

## Install

The top-level `./install.sh` includes it. On its own:

```sh
./install.sh                          # everything
./install.sh --only themes,btop   # themes is always installed; btop and desktop are optional
./install.sh --dry-run
./uninstall.sh                        # puts back everything it changed
```

It copies the commands, templates, and themes to
`~/.local/share/kadomo/theme-manager`, links the commands into `~/.local/bin`,
wires each app (below), and applies tmac2k, or reapplies the theme you
already had. Plain Bash 3.2 and the tools macOS ships; no Homebrew needed.

## Commands

Each is a small script in `bin/` with a `# kadomo:summary=` line on top and
`--help`.

| Command | Does |
| --- | --- |
| `theme-set <name>` | switch to a theme |
| `theme-set --external <folder> <name> [<label>]` | show a theme kept elsewhere (Kadomo Menu's Omarchy themes), in place, with the rules for someone else's theme ([below](#themes-from-other-providers)) |
| `theme-set --native` | back to the last of Kadomo's own themes (nothing when one is showing) |
| `theme-refresh` | apply the current theme again, keeping the wallpaper (after editing a template) |
| `theme-list` | every theme, built-in and yours, by display name (`--names` for folder names) |
| `theme-current` | the current theme's display name (`--name` for its folder name) |
| `theme-bg-next` | the current theme's next wallpaper, wrapping around |
| `theme-bg-set <image>` | any image as the wallpaper |
| `theme-pick`, `theme-bg-pick` | pick in the terminal: fzf with previews when installed, else a numbered menu |
| `theme-remove <name>` | delete one of your themes |
| `theme-color <key>` | a color of the current theme; `--all` for the whole palette, `--file` for any colors.toml |
| `theme-osc` | recolor the terminal you run it in through escape codes |
| `theme-starship` | the Starship prompt for zsh in the theme's colors: `status`, `enable`, `disable`, `match on\|off`, `set <theme>`, `icons nerd\|plain`, `preview`, `list`, `apply` ([below](#starship)) |
| `theme-vscode` | VS Code in the theme's colors: `status`, `enable`, `disable`, `apply` ([below](#vs-code)) |

## Where things live

| Path | |
| --- | --- |
| `~/.config/kadomo/themes/<name>/` | your themes, and files that overlay a built-in theme of the same name |
| `~/.config/kadomo/themed/*.tpl` | your templates; they win over the built-in ones |
| `~/.config/kadomo/backgrounds/<name>/` | more wallpapers for a theme |
| `~/.config/kadomo/hooks/theme-set.d/` | scripts run after each switch, with the theme name as `$1` (see `notify.sample`) |
| `~/.config/kadomo/theme.conf` | which apps follow the theme |
| `~/.config/kadomo/current/theme/` | the current theme, every generated config in one folder |
| `~/.config/kadomo/current/theme.name`, `background` | its name, and a link to the wallpaper showing |
| `~/.config/kadomo/current/theme.external`, `native.name` | the external theme showing (name, label, folder), and the last Kadomo theme |
| `~/.config/kadomo/starship/` | Kadomo's Starship config, its `init.zsh`, and your prompt settings ([below](#starship)) |
| `~/.local/state/kadomo/vscode.txt` | what Kadomo changed in VS Code, so `theme-vscode disable` and uninstall undo exactly that |
| `~/.config/kadomo/menu/commands/themes.toml` | the Appearance › Themes and Backgrounds lists in Kadomo Menu |
| `~/.local/state/kadomo/`, `~/.cache/kadomo/` | locks, and the pickers' thumbnails |

The current theme is in `~/.config/kadomo` rather than `~/.local/state`
because Kadomo Menu already reads `~/.config/kadomo/current/theme/kadomo-menu.toml`.

## Themes

A theme is a folder named in kebab-case; the display name comes from it
(`rose-pine` is "Rose Pine"; a word with a digit, like `tmac2k`, is kept as is).

- `colors.toml`: the palette, the single source of truth (below).
- `backgrounds/`: wallpapers, used in file name order, so `0-road.jpg`, `1-sea.jpg`.
- `preview.png`: the picker's thumbnail; the first wallpaper otherwise.
- Any generated file, written by hand (`ghostty.conf`, `btop.theme`, ...): it
  wins over the template.
- `neovim.lua`: a LazyVim spec that names a colorscheme plugin.
- `<file>.<section>.toml`: replaces one `[section]` of a generated TOML file,
  such as `kadomo-menu.colors.toml` for the launcher's `[colors]`.

A theme in `~/.config/kadomo/themes` with the name of a built-in one is laid
over it, so you can change one file of a built-in theme.

### colors.toml

```toml
mode = "dark"                 # or "light": sets macOS light/dark mode too
accent = "#7aa2f7"
selection = "#292e42"
muted = "#414868"
background = "#1a1b26"        # also dark_background, darker_background, lighter_background
foreground = "#a9b1d6"        # also dark_foreground, light_foreground, bright_foreground
red = "#f7768e"               # yellow orange green cyan blue magenta brown, and bright_ versions
hyprland_active_border = "rgba(bb9af7ff) rgba(7aa2f7ff) 45deg"   # optional window border gradient
inactive_border = "#24283b"   # optional
success = "#9ece6a"           # optional: the prompt after a command that worked (green by default)
error = "#f7768e"             # optional: after one that failed (red)
warning = "#e0af68"           # optional: Git changes (yellow)
```

`lib/palette.awk` (`theme-color --all`) fills in the rest: aliases (`bg`,
`fg`, `purple`, `cursor`, `selection_background`, ...), the ANSI slots
`color0` to `color15` (0 background, 1-6 the colors, 7 foreground, 8 muted,
9-14 the bright colors, 15 bright_foreground), and blends for missing keys.
For Vim and Neovim there are also `comment`, `shade` (cursor line, panels),
`dim_background` (inactive windows), and `diff_background`. A theme may set
any alias or slot itself; tmac2k sets `cursor`, `color0`, `color7`, `color8`,
and the four editor shades. Every value must be a hex color (or, for `mode`, dark
or light); anything else is dropped with a warning, so only hex digits ever
reach a generated config. A theme with only an `alacritty.toml` has its
palette read from that.

### Templates

`themed/<output>.tpl` renders to `<output>` in the current theme, once per
switch. The Vim and Neovim templates are the original tmac2k colorschemes
with their colors replaced by the palette, by role (keywords color 1, defines
2, types 3, functions 4, strings 5, constants 6), so tmac2k comes out exactly
as before and every other theme reads the same way. Both leave the
background to the terminal, so Ghostty's opacity and blur show through; set
`vim.g.kadomo_transparent = false` in Neovim or `let g:kadomo_transparent = 0`
in Vim (before the colorscheme loads) for the theme's solid background. The
older `tmac2k_transparent` works the same way. For each output, a file the theme ships wins, then your template,
then the built-in one.

| Placeholder | Gives |
| --- | --- |
| `{{ accent }}` | `#7aa2f7` |
| `{{ accent_strip }}`, `{{ accent_rgb }}`, `{{ accent_argb }}` | `7aa2f7`, `122,162,247`, `0xff7aa2f7` |
| `{{ mix background foreground 30% }}` | a blend (also `mix_strip`, `mix_rgb`, `mix_argb`; `0.3` works too) |
| `{{ toml_gradient hyprland_active_border accent }}` | `["#bb9af7", "#7aa2f7"]` |
| `{{ omniwm_borders hyprland_active_border accent }}` | OmniWM's `[borders.color]` table (the first color), plus `[borders.gradient]` when there are two |
| `{{ readable accent background 3 }}` | `accent`, or `accent` moved toward black or white just far enough for a WCAG contrast of 3 against `background` |
| `{{ gradient_start key fallback }}`, `{{ shell_gradient ... }}`, `{{ hypr_gradient ... }}` | the first color; colors and angle; Hyprland's form |
| `{{ theme }}`, `{{ theme_name }}`, `{{ mode }}` | `rose-pine`, `Rose Pine`, `light` |

## Apps

`theme.conf` lists the apps that follow the theme. Each reloader runs in
parallel after a switch, reads the current theme, and does nothing when its
app is not installed or not running.

| App | How it reads the theme | After a switch |
| --- | --- | --- |
| Ghostty | `config-file = ?"~/.config/kadomo/current/theme/ghostty.conf"` in its config | `SIGUSR2` reloads it (1.2 and later) |
| btop | `color_theme = "current"`: `~/.config/btop/themes/current.theme` links to the theme's `btop.theme` | `SIGUSR2` reloads it (1.3 and later) |
| OmniWM | `kadomo-omniwm theme` puts `omniwm.toml`'s color tables in `~/.config/omniwm/settings.toml`, in place of the border colors there (width, glow, and the rest stay yours; the colors from before Kadomo come back on uninstall) | OmniWM reloads settings.toml when it changes |
| Kadomo Menu | its theme is set to `kadomo`, which reads `kadomo-menu.toml` | it watches the file; set back to `kadomo` if its config named another theme |
| Neovim | the `kadomo` colorscheme: `~/.config/nvim/colors/kadomo.lua` links to the theme's `neovim-colors.lua`, and a block in `init.lua` (or `init.vim`) selects it | every running Neovim showing it loads it again |
| Neovim with LazyVim | `~/.config/nvim/lua/plugins/theme.lua` links to the theme's `neovim.lua`: `kadomo`, or a colorscheme plugin the theme names | the next time it starts |
| Vim | the `kadomo` colorscheme: `~/.vim/colors/kadomo.vim` links to the theme's `vim-colors.vim`, and a block in `~/.vimrc` selects it (a new vimrc also keeps Vim's defaults) | the next time it starts: the Vim that comes with macOS cannot be reached while it runs |
| VS Code | the **Kadomo** color theme, a local extension in `~/.vscode/extensions/kadomo.kadomo-theme` rendered from the theme; selected in `workbench.colorTheme`, with JetBrainsMono Nerd Font in the editor and terminal | the extension's colors are rewritten and VS Code reloads them in open windows ([below](#vs-code)) |
| macOS appearance | the theme's `mode` | System Events sets dark or light |
| Wallpaper | `current/background` | set on every display through NSWorkspace |
| htop | draws with the terminal's 16 colors | follows the terminal |
| Starship (zsh) | once on (`theme-starship enable`), zsh sets `STARSHIP_CONFIG` to `~/.config/kadomo/starship/starship.toml`, written from the theme's `starship-palette.toml` | the file is rewritten; Starship reads it at the next prompt |

macOS asks once to let the theme manager control System Events. Terminal.app
is never touched: it keeps its own profiles and colors.
The wallpaper changes on every Space: macOS sets the one each display is
showing, then the theme manager copies that picture to the others in macOS's
wallpaper store and restarts WallpaperAgent, so the desktop redraws once.
The first install keeps a copy of that store, and uninstall puts back the
picture each Space and display had before (a dynamic or aerial wallpaper
included) wherever Kadomo's is still showing; one you chose since stays.

`theme-osc` is not sent to every open terminal: colors set by escape codes
would stop Ghostty from taking later themes from its config.

## Starship

`theme-starship` puts the Starship prompt on zsh in the theme's colors. The
developer installer (`developer/`) installs Starship and runs
`theme-starship enable` for you; on its own:

```sh
theme-starship                 # status: not installed, installed, on, or needs attention (with the fix)
theme-starship enable          # turn it on for zsh
theme-starship preview --all   # sample prompts for every theme; nothing changes
theme-starship set gruvbox     # this prompt whatever the Kadomo theme (matching off)
theme-starship match on        # follow the Kadomo theme again (the default)
theme-starship icons plain     # no Nerd Font symbols
theme-starship disable         # take Kadomo's lines out again
```

**What enable changes.** Kadomo's files are in `~/.config/kadomo/starship/`:
`starship.toml` (the config, written by Kadomo; your own
`~/.config/starship.toml` is never touched), `init.zsh` (sets `STARSHIP_CONFIG` to
it and starts Starship once), `settings.conf` (`match`, `theme`, `icons`), and
`enabled.txt` (what enable changed). Your `.zshrc` (in `$ZDOTDIR`, as zsh sees it, when set)
gets one marked block that sources `init.zsh`, after a backup to
`.zshrc.kadomo-backup.<time>`:

```zsh
# >>> kadomo starship (added by theme-starship; theme-starship disable removes it)
[[ -r "$HOME/.config/kadomo/starship/init.zsh" ]] && source "$HOME/.config/kadomo/starship/init.zsh"
# <<< kadomo starship
```

Before it changes anything, enable looks through `.zshenv`, `.zprofile`, `.zshrc`, and
`.zlogin` for a `starship init` of yours, a `STARSHIP_CONFIG`, another
prompt (Powerlevel10k, an Oh My Zsh theme, Pure, Spaceship, Oh My Posh), and
for your own `starship.toml`. If it finds any, it says what and where, changes
nothing, and exits 3; `theme-starship enable --use-kadomo` goes ahead. With
your own `starship init` line, Kadomo leaves it in charge and only points it at
Kadomo's config, so Starship never starts twice (`init.zsh` also checks that it
is not already running). A `.zshrc` that is a symlink (a dotfiles repository) is
not edited: add the one line yourself (enable then counts it as on), or allow
`--edit-symlinked` to append the block to the file it points to. Enabling again only
refreshes the files.

**When it shows.** A new shell (a new tab, or `exec zsh`) picks up enable or
disable. Theme changes after that show at the next prompt in every open shell,
because Starship reads its config each time.

**Matching.** On by default: `theme-set` (and Kadomo Menu's Appearance › Themes)
rewrites `starship.toml` with the new theme's colors. `theme-starship set <theme>`
turns matching off and keeps that prompt through any theme change;
`match off` keeps whatever shows now. With `theme-pick`, the preview pane
shows each theme's prompt too while Starship is on.

**Safety.** The config is built next to the old one, checked (well-formed
lines, all nine colors, and, when Starship is installed, Starship rendering
it with no config warning), then moved over it in one step; anything that
fails keeps the previous config. A failure during `theme-set` is reported
(`theme: the Starship prompt kept its old colors; retry with theme-starship apply`)
while the other apps switch as usual. A theme from git cannot bring its own
`starship-palette.toml`: its prompt colors come from its `colors.toml`.

**Disable** takes the block out, unless you edited it (it then says so and
leaves it, harmless without `init.zsh`), removes `init.zsh` and `starship.toml`,
deletes a `.zshrc` it made that is now empty, and deletes its backup when the
`.zshrc` is back to exactly that. Your settings stay for next time. It never
uninstalls Starship; uninstalling the theme manager disables it the same way.

### The prompt

One layout for every theme, two lines (shown with `icons plain`):

```
~/code/kadomo on main [!?] via node v26.13.0 took 12s
❯
```

The folder (up to 3 levels, from the repository root), the Git branch and
state, Node.js, Java, Python, Rust, or Go when the folder is a project for it,
the time a command took over 2 s, and `❯`, or `✗` after a failure. User and host
only over SSH or as root; no cloud accounts, no custom commands. With
`icons plain` the symbols become text (`via node v26.13.0`).

The colors come from `themed/starship-palette.toml.tpl`, rendered for every
theme like any other template (so a new theme gets a prompt with nothing
else to do), and each is moved just far enough to read on the theme's
background (WCAG 4.5 for text, 3 for the rest, 2 for separators):

| Role | From | Used for |
| --- | --- | --- |
| `text` | `foreground` | user and host |
| `secondary` | `dark_foreground` | how long a command took |
| `directory` | `accent` | the folder |
| `branch` | `magenta` | the Git branch |
| `success` | `success` (`green`) | `❯` |
| `error` | `error` (`red`) | `✗`, read-only folders |
| `changes` | `warning` (`yellow`) | Git status and state |
| `runtime` | `cyan` | Node.js, Java, ... versions |
| `separator` | `comment` | the words on, via, took |

Every theme and its prompt colors (`theme-starship list`; the prompt themes
share the theme's id):

| Theme | text | secondary | directory | branch | success | error | changes | runtime | separator |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| tmac2k (dark) | `#d1d1d1` | `#707070` | `#ba5aff` | `#5ea2ff` | `#5ac8ff` | `#ff4f9a` | `#905aff` | `#5ac8ff` | `#555555` |
| catppuccin (dark) | `#cdd6f4` | `#a6adc8` | `#89b4fa` | `#f5c2e7` | `#a6e3a1` | `#f38ba8` | `#f9e2af` | `#94e2d5` | `#64687d` |
| catppuccin-latte (light) | `#4c4f69` | `#6c6f85` | `#1e66f5` | `#c764ad` | `#3d9829` | `#d20f39` | `#be7919` | `#179299` | `#a5a7b4` |
| gruvbox (dark) | `#ebdbb2` | `#a89984` | `#d79921` | `#b16286` | `#98971a` | `#d13a34` | `#d79921` | `#689d6a` | `#76705f` |
| rose-pine (Dawn, light) | `#575279` | `#797593` | `#c27571` | `#907aa9` | `#286983` | `#b4637a` | `#bb7e2a` | `#c27571` | `#b0aab5` |
| sora (dark) | `#c8d0e0` | `#9aa4b8` | `#80c8e0` | `#b0a0d8` | `#90c8a0` | `#c46c78` | `#d4b878` | `#78b8b0` | `#586478` |

tmac2k's six hues all run violet to cyan, so it sets `success` (its cyan),
`error` (a neon pink), and `warning` (violet) itself. A theme can also ship its own
`starship-palette.toml` with the nine `role = "#rrggbb"` lines.

## VS Code

`theme-vscode` puts Visual Studio Code in the theme's colors. The developer
installer (`developer/`) installs VS Code and runs `theme-vscode enable`; with
VS Code already installed, the theme manager's own install wires it as it does
every other app.

```sh
theme-vscode           # status: installed, following the theme, the color theme showing
theme-vscode enable    # VS Code follows the theme (adds vscode to theme.conf) and shows it now
theme-vscode apply     # show the current theme again
theme-vscode disable   # your color theme from before comes back; Kadomo's extension goes
```

**Which VS Code theme.** Each theme renders `themed/vscode-theme.json.tpl`
(ported from [Omarchy](https://github.com/basecamp/omarchy)'s, MIT) from its
palette, like any template. It is installed as a local extension, **Kadomo**,
in `~/.vscode/extensions/kadomo.kadomo-theme` and listed in VS Code's
`extensions.json`. Its version comes from the colors, and VS Code watches the
file, so a switch recolors open windows without a reload.

**Nothing from the Marketplace.** A VS Code extension is code that runs in
VS Code, so Kadomo never installs one for a theme. Omarchy's themes ship a
`vscode.json` naming a Marketplace theme (`enkia.tokyo-night` for Tokyo
Night); it is ignored, and VS Code shows the Kadomo theme drawn from the
theme's colors, like every other app.

**Fonts.** A color theme can't carry a font, so Kadomo sets them in
`settings.json`, the same for every theme: `editor.fontFamily` is
JetBrainsMono Nerd Font (the debug console and chat follow the editor) and
`terminal.integrated.fontFamily` its fixed-pitch Mono variant,
each falling back to Menlo. A font you pick after Kadomo set one stays yours.

**What changes.** Only `workbench.colorTheme` and those two fonts in
`~/Library/Application Support/Code/User/settings.json`. That file may have
comments and trailing commas, so those lines are edited as text and everything
else stays as written; a `settings.json` that is a symlink stays one. VS Code
Insiders, VSCodium, and Cursor are not touched.

**Disable and uninstall** put back the color theme and fonts you had before
Kadomo, unless you picked others since. They also remove the Kadomo extension, any
Marketplace theme an older Kadomo installed for a theme (VS Code uninstalls it,
or Kadomo takes it out of its registry when VS Code is gone already), and a
`settings.json` or folders Kadomo made that hold nothing else.

## Themes from git

Install a theme from a Git URL in Kadomo Menu (Appearance › Omarchy Themes ›
Install from Git), which clones over HTTPS only, with hooks, submodules, and
symlinks off; see [Omarchy themes](../kadomo-menu/docs/OMARCHY.md). There is
no command line installer.

User themes in `~/.config/kadomo/themes` are restricted by default, including
archives, Git worktrees, and symlinked folders. Only colors and images are
used: `colors.toml`, `alacritty.toml` (its palette, then it is dropped),
`btop.theme`, `kadomo-menu*.toml`, `preview.*`, and images in `backgrounds/`.
Lua, terminal configs, scripts, and file symlinks are skipped.

To allow executable configuration from a theme you wrote or reviewed, add
its absolute path as one line in `~/.config/kadomo/trusted-themes`, for example:

```sh
printf '%s\n' "$HOME/.config/kadomo/themes/my-theme" >> ~/.config/kadomo/trusted-themes
```

Trust applies to future changes in that folder too. Remove its line to revoke
trust, then apply the theme again; `theme-remove` removes the line with the
folder. Bundled themes are trusted; external-provider
themes remain restricted regardless of this list.

## Themes from other providers

Kadomo Menu keeps Omarchy themes in a library of its own and shows one with
`theme-set --external <folder> <name> <label>`. The folder is used where it
is, always as someone else's theme: only `colors.toml` (or the palette of an
`alacritty.toml`), `btop.theme`, `kadomo-menu*.toml`, `preview.*`, the
images in `backgrounds/` are used, and a `light.mode` file makes it light.
Every template renders from its palette as for any theme, so every app,
light/dark mode, and the wallpaper follow it. It is not listed among your
themes, cannot take the name of one, and Kadomo Menu keeps showing the
Omarchy theme on the launcher. `theme-current` prints its label;
`theme-refresh` and `theme-bg-next` work on it. `theme-set <name>` or
`theme-set --native` (your last Kadomo theme) switch back.

## How a switch works

`theme-set` takes a numbered ticket, then a lock (`shlock`), so quick
switches queue and the newest choice wins: an older one still waiting steps
aside. It stages the theme in `current/next-theme` (built-in files, then
yours), renders the templates there, swaps it into `current/theme` with two
renames, moves to the next wallpaper (theme-refresh keeps it), updates the
Kadomo Menu lists, and releases the lock. Then the reloaders run in parallel
(each stopped after 20 s if stuck), then the hooks, and the pickers'
thumbnails are refreshed in the background.

Wallpapers are shown from where they are installed rather than copied into
the current theme, so macOS always has a path that stays put. A theme with no
wallpapers gets one drawn from its background and accent colors
(`~/.local/state/kadomo/wallpapers/`, the 20 newest kept), so a switch always
changes the wallpaper.

## Making themes

Add a folder to `~/.config/kadomo/themes/` with a `colors.toml`, run
`theme-set <name>`, and adjust. To ship one with Kadomo, add it to `themes/`
and run `python3 tools/make-backgrounds.py <name>` for wallpapers drawn from
its palette (tmac2k's are your own images, so it is left out of the script).

## Tests

```sh
tests/test.sh
tests/starship-test.sh
```

Both run in a throwaway HOME, with every app reloader turned off (Starship's
tests use a stand-in `starship`), so nothing on your Mac changes.
`KADOMO_STARSHIP_SCHEMA=config-schema.json tests/starship-test.sh` also checks
every generated key against Starship's published schema.
