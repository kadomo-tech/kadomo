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
| `category` | default: Home | a built-in id or your own path like `work/deploy` (missing levels are created) |
| `also_in` | | more categories that list it |
| `keywords`, `aliases` | | extra search words. An exact alias ranks just under an exact title |
| `icon` | | an SF Symbol name, or a path to a file whose icon to show |
| `glyph` | | a literal character (emoji, Nerd Font glyph) instead of an icon |
| `hint` | the shortcut, if it has one | text at the right edge |
| `hotkey` | | a system-wide shortcut, like `"option+shift+m"`, that runs the command without opening the launcher. Not with `confirm`. A shortcut that's taken shows a warning in the launcher and in `kadomo-menu status` |
| `confirm` | false | ask for a second Enter |
| `keep_open` | false | leave the launcher open after running |
| `order` | 0 | sort position in its category (ties sort by title) |
| `running_app` | | a bundle id: while that app runs, the row shows ● and "running" |

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

## `[[keybind]]`

Read-only rows in Keybinds, from commands files (not config.toml). Opening
Keybinds widens the launcher into two columns, `KEY → what it does`.

| Key | | |
| --- | --- | --- |
| `key` | required | the keys as you want them shown, like `CTRL OPT + R` |
| `title` | required | what the keys do |
| `subtitle` | | a note after the title, in the muted color |
| `id` | | the item becomes `key:<id>`. Defaults to a slug of key and title |
| `order` | 100 + its place in the file | sort position, below 998. The launcher's own keys come last, under a Kadomo Menu heading (998), starting with "Open Kadomo Menu" (999) |
| `keywords`, `icon` | | as for commands; the key is searchable too |

A `[[keybind]]` with only `heading` (and `order`, `id`) is a section label,
like `heading = "Workspaces"`. It is drawn small in the accent color, the
selection steps over it, and a search never shows it. The Keybinds list uses
shorter rows than other lists and shows up to `keybind_rows` of them (a theme
setting), as many as fit on the screen; the rest scroll.


| Key | |
| --- | --- |
| `id` | required. A path with `/` nests it: `development/projects` |
| `title` | defaults to the last path part, title-cased |
| `parent` | defaults to the path's parent, or home |
| `subtitle`, `icon`, `keywords`, `order` | as for commands |
| `running_app` | as for commands: the category row shows ● and "running" while that app runs |

Empty categories are hidden.

## Built-in ids

Categories: `apps`, `appearance`, `appearance/themes` (Kadomo Themes),
`appearance/omarchy` (Omarchy Themes, with `/installed`, `/official`,
`/community`, `/git`), `keybinds`,
`services`, `system`, `settings` (inside System),
`about`. Items: `app:<bundle id>`, `sys:lock`, `sys:sleep`, `sys:restart`,
`set:<pane id>`, `theme:<id>`, … — `kadomo-menu commands list` prints all of
them. Use ids in `favorites`, `hidden`, and `[aliases]`.

## Example

[examples/commands/development.toml](../examples/commands/development.toml)
