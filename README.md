# kadomo-alpha
Early version of Kadomo

## Install

```sh
./install.sh          # every component, each with its own prompts
./install.sh --yes    # every component with its defaults, no prompts
```

| Component | What it installs |
| --- | --- |
| `dotfiles/` | configs copied to where each tool reads them; files they replace are backed up |
| `kadomo-menu/` | the launcher app, the `kadomo-menu` command, and its font |

Each component also has its own `install.sh` and `uninstall.sh`.

## Uninstall

```sh
./uninstall.sh        # asks before removing each component
./uninstall.sh --yes  # removes everything, no prompts
```

This removes everything `install.sh` put in place and restores the configs the
dotfiles replaced. A config you edited after installing is kept as
`<name>.bak.<timestamp>`. The kadomo-menu uninstaller also deletes its config,
usage history, and preferences. This checkout is left alone.
