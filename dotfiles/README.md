# dotfiles

Config files, one folder per tool.

| File | Installed to |
| --- | --- |
| `aerospace/aerospace.toml` | `~/.config/aerospace/aerospace.toml` |
| `ghostty/config.ghostty` | `~/.config/ghostty/config.ghostty` |
| `ghostty/themes/tmac2k` | `~/.config/ghostty/themes/tmac2k` |

`install.sh` copies each file into place, backing up any different file it
replaces, and records what it did in
`~/Library/Application Support/kadomo/dotfiles-installed.txt`. `uninstall.sh`
reads that record, removes the copies, and restores the backups. Both take
`--dry-run`. The top-level `install.sh` and `uninstall.sh` run them for you.

To add a config, put it in a folder here and add a line to `FILES` in
`files.sh`.

Ghostty also reads `~/Library/Application Support/com.mitchellh.ghostty/config.ghostty`
after the file above, so a setting there (such as its own `theme`) wins. Ghostty
cannot be told to reload from the command line; press Cmd+Shift+, in it.
