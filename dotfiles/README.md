# dotfiles

Config files, one folder per tool.

| File | Installed to |
| --- | --- |
| `ghostty/config.ghostty` | `~/.config/ghostty/config.ghostty` |
| `kitty/kitty.conf` | `~/.config/kitty/kitty.conf` |
| `editors/kadomo.vim` | `~/.vim/plugin/kadomo.vim` |
| `editors/kadomo.lua` | `~/.config/nvim/plugin/kadomo.lua` |

Colors are not in these files. Ghostty and kitty read
them from the current Kadomo theme in `~/.config/kadomo/current/theme/`,
which [kadomo-theme-manager](../kadomo-theme-manager/README.md) installs and
switches (`theme-set gruvbox`). It also themes btop and Kadomo Menu. tmac2k, the theme these dotfiles used to carry, is its default.

`install.sh` copies each file into place, backing up any different file it
replaces, and records what it did in
`~/Library/Application Support/kadomo/dotfiles-installed.txt`. `uninstall.sh`
reads that record, removes the copies, and restores the backups. Both take
`--dry-run`. The top-level `install.sh` and `uninstall.sh` run them for you.

Older installs also placed an AeroSpace config and JankyBorders (from Homebrew,
recorded in `packages-installed.txt`) with its `bordersrc`. Kadomo uses OmniWM
now, which draws its own border, so `install.sh` first runs
`uninstall.sh --retired`: it removes the files this folder no longer ships
(keeping a copy of one you edited) and stops and uninstalls a JankyBorders
Kadomo installed (plus its Homebrew tap, if Kadomo added it and nothing else
uses it). One you installed yourself stays.

To add a config, put it in a folder here and add a line to `FILES` in
`files.sh`.

Ghostty also reads `~/Library/Application Support/com.mitchellh.ghostty/config.ghostty`
after the file above, so a setting there (such as its own `theme`) wins. After
installing or uninstalling, a running Ghostty 1.2 or later is told to reload
(with `SIGUSR2`); an older one quits on that signal, so it gets a reminder to
press Cmd+Shift+, instead.

## kitty and htop

`kitty.conf` includes the current theme's colors along with Ghostty's font,
size, opacity, and blur. A running kitty is told to reload (with `SIGUSR1`).
Without the theme manager, the include finds no file and kitty keeps its own
colors; Ghostty does the same (its `config-file` line is optional).

htop has no themes with custom colors: it draws with the terminal's 16 colors,
so in Ghostty or kitty it follows the current theme.

## Vim and Neovim

`editors/` holds Kadomo's editor settings: line numbers in every window.
They go in each editor's `plugin` folder, which it loads at startup after your
own `~/.vimrc` or `init.lua` (LazyVim too), so your config files are left as
they are. They take effect the next time the editor starts.
