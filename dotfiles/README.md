# dotfiles

Config files, one folder per tool. `../install.sh` copies each one to where its
tool reads it, backing up any different file it replaces.

| File | Installed to |
| --- | --- |
| `aerospace/aerospace.toml` | `~/.config/aerospace/aerospace.toml` |

To add a config, put it in a folder here and add a line to `FILES` in
`install.sh`.
