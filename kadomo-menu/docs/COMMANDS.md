# Commands and categories

Commands come from `[[command]]` tables in config.toml, in any
`~/.config/kadomo-menu/commands/*.toml`, in folders listed in
`command_directories`, and in Kadomo's `~/.config/kadomo/menu/commands/`.
Saving any of them applies the change. `kadomo-menu config check` validates.

## `[[command]]`

| Key | | |
| --- | --- | --- |
| `title` | required | what the row shows |
| `id` | recommended | stable id; the item becomes `cmd:<id>`. Defaults to a slug of the title. Usage history and favorites follow the id |
| `subtitle` / `description` | | shown by themes with subtitles; searched |
| `category` | default `commands` | a built-in id or your own path like `work/deploy` (missing levels are created) |
| `also_in` | | more categories that list it |
| `keywords`, `aliases` | | extra search words. An exact alias ranks just under an exact title |
| `icon` | | an SF Symbol name, or a path to a file whose icon to show |
| `glyph` | | a literal character (emoji, Nerd Font glyph) instead of an icon |
| `hint` | | text at the right edge |
| `confirm` | false | ask for a second Enter |
| `keep_open` | false | leave the launcher open after running |
| `order` | 0 | sort position in its category (ties sort by title) |

Exactly one action:

| Key | Runs |
| --- | --- |
| `exec`, `args` | the program with this argument array. No shell parses anything. A bare name is found in PATH plus `/opt/homebrew/bin`, `/usr/local/bin`, `~/.local/bin`, `~/.cargo/bin`. A leading `~/` in `exec` or any argument expands to your home folder; nothing else expands |
| `shell`, `shell_path` | the script via `/bin/zsh -c` (or `shell_path`). For commands you wrote; never paste untrusted text here |
| `url` | opens the URL (`https:`, `raycast:`, `x-apple.systempreferences:`, …) |
| `open` | opens a file or folder in its default app |
| `app` | an app by path, bundle id, or name |

Commands run in your home folder with stdout discarded. A non-zero exit
shows the status and the last line of stderr in the launcher (or a short
message near the top of the screen if the launcher already closed).

## `[[command.action]]`

Secondary actions, listed with Tab. The first one also runs with ⌘↩.
Each takes `title`, one action key from the table above, and optional
`icon` and `confirm`.

## `[[category]]`

| Key | |
| --- | --- |
| `id` | required. A path with `/` nests it: `development/projects` |
| `title` | defaults to the last path part, title-cased |
| `parent` | defaults to the path's parent, or home |
| `subtitle`, `icon`, `keywords`, `order` | as for commands |

Empty categories are hidden.

## Built-in ids

Categories: `apps`, `windows`, `workspaces`, `system`, `settings`,
`appearance`, `appearance/themes`, `development`, `commands`, `keybinds`,
`about`. Items: `app:<bundle id>`, `sys:lock`, `sys:sleep`, `sys:restart`,
`set:<pane id>`, `theme:<id>`, … — `kadomo-menu commands list` prints all of
them. Use ids in `favorites`, `hidden`, and `[aliases]`.

## Example

[examples/commands/development.toml](../examples/commands/development.toml)
