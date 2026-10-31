/// Files written on first launch so the configuration is discoverable.
/// Every setting is commented out: the defaults live in code.
enum DefaultFiles {
    static let config = """
    # Kadomo Menu configuration. Changes apply as soon as you save.
    # Check it from a terminal with: kadomo-menu config check

    # theme = "kadomo-dark"        # kadomo-dark, kadomo-minimal, kadomo-terminal, kadomo-light,
    #                              # any themes/<name>.toml, or "kadomo" to follow the Kadomo desktop theme
    # hotkey = "option+space"
    # launch_at_login = true
    # display = "active"           # active (frontmost window's screen), mouse, primary
    # close_on_blur = true
    # escape_navigates_back = true # false: Escape always closes
    # backspace_navigates_back = true
    # hover_selects = false
    # show_favorites = true
    # show_recent = 0              # 0-5 recently used items on the home menu
    # favorites = ["app:com.apple.Safari"]
    # hidden = ["sys:screensaver"] # item ids to leave out
    # window_manager = "auto"      # auto, yabai, aerospace, off
    # debug_log = false

    # [search]
    # max_results = 40
    # subtitles = true             # match words in descriptions too

    # [search.prefixes]            # start a search with these to scope it
    # ">" = "commands"
    # "@" = "apps"
    # "!" = "system"

    # [keys]                       # each value is a chord or a list of chords
    # down = ["down", "ctrl+n", "ctrl+j"]
    # up = ["up", "ctrl+p", "ctrl+k"]
    # actions = ["tab", "cmd+k"]
    # alternate = "cmd+enter"
    # favorite = "cmd+d"

    # [aliases]                    # extra search terms → item id (see `kadomo-menu commands list`)
    # ff = "app:org.mozilla.firefox"

    # [apps]
    # extra_directories = ["~/Applications/Setapp"]
    # exclude = ["com.apple.Chess"]

    # [kadomo]                     # optional integration with the Kadomo desktop
    # mode = "auto"                # auto: use the files below when they exist; off: ignore them
    # theme_file = "~/.config/kadomo/current/theme/kadomo-menu.toml"
    # commands_directory = "~/.config/kadomo/menu/commands"

    # Commands can live here or in commands/*.toml. See commands/README.md.
    # [[command]]
    # title = "Edit Dotfiles"
    # category = "development"
    # exec = "/usr/bin/open"
    # args = ["-a", "Zed", "~/dotfiles"]

    """

    static let commandsReadme = """
    # Commands

    Every `*.toml` file in this folder can add commands and categories.
    Changes apply as soon as you save. Check with `kadomo-menu config check`.

    ```toml
    [[category]]
    id = "development/projects"      # nested under Development
    title = "Projects"
    icon = "folder"                  # an SF Symbol name

    [[command]]
    id = "open-kadomo"               # stable id; becomes cmd:open-kadomo
    title = "Open Kadomo"
    subtitle = "Project in Ghostty"
    category = "development/projects"
    keywords = ["repo", "dotfiles"]
    aliases = ["kd"]
    exec = "/usr/bin/open"           # runs directly, no shell
    args = ["-a", "Ghostty", "~/Code/kadomo"]

    [[command.action]]               # secondary actions, shown with Tab
    title = "Reveal in Finder"
    open = "~/Code/kadomo"
    ```

    Exactly one of these runs the command:

    | Key | Runs |
    | --- | --- |
    | `exec` + `args` | an executable with an argument array (no shell). A bare name is looked up in PATH plus Homebrew. |
    | `shell` | a script through `/bin/zsh -c` (or `shell_path`). Only use with text you wrote. |
    | `url` | a URL, like `raycast://` or `https://` |
    | `open` | a file or folder with its default app |
    | `app` | an app by path, bundle id, or name |

    Optional: `confirm = true` asks before running, `keep_open = true` leaves the
    launcher open, `hint` shows text at the right edge, `also_in = ["system"]`
    lists the command in more categories, `order` sorts within the category.

    Built-in category ids: apps, windows, workspaces, system, settings,
    appearance, development, commands, keybinds, about.
    """

    static let exampleCommands = """
    # Example commands. Edit or delete this file; changes apply on save.

    [[command]]
    id = "example-home"
    title = "Open Home Folder"
    keywords = ["finder", "files"]
    open = "~"

    [[command]]
    id = "example-say"
    title = "Say Hello"
    subtitle = "Runs /usr/bin/say with an argument array"
    exec = "/usr/bin/say"
    args = ["Hello from Kadomo Menu"]

    [[command]]
    id = "example-uptime"
    title = "Copy Uptime"
    subtitle = "A shell command you wrote yourself"
    shell = "uptime | pbcopy"
    """

    static let themesReadme = """
    # Themes

    Put `<name>.toml` here and set `theme = "<name>"` in config.toml, or pick it
    under Appearance › Themes. Edits apply on save; a theme with errors is
    rejected and the last good one stays on screen.

    Start from a built-in and override what you like:

    ```toml
    name = "My Theme"
    extends = "kadomo-dark"   # kadomo-dark, kadomo-minimal, kadomo-terminal, kadomo-light
    appearance = "dark"       # dark, light, auto (uses [colors.light] in light mode)
    layout = "center"         # center, top, compact

    [colors]
    accent = "#ff79c6"
    border = ["#b26cf3", "#5ea8f5"]   # a color, or two or more for a gradient

    [font]
    family = "JetBrainsMono Nerd Font" # or monospace, system, rounded
    size = 16

    [geometry]
    width = 640
    row_height = 44

    [effects]
    material = "none"         # none, hud, popover, menu, sidebar, under-window
    selection_style = "fill"  # fill, bar, outline
    ```

    Every token is listed in the project's docs/THEMES.md.
    """
}
