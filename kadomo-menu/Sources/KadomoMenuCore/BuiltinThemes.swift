/// The shipped presets, written in the same TOML users write, so the built-ins
/// exercise the same parser, validation, and inheritance as custom themes.
public enum BuiltinThemes {
    public static let defaultID = "kadomo-dark"

    public static let all: [String: String] = [
        "kadomo-dark": kadomoDark,
        "kadomo-minimal": kadomoMinimal,
        "kadomo-terminal": kadomoTerminal,
        "kadomo-light": kadomoLight,
    ]

    public static var sources: [String: ThemeSource] {
        all.reduce(into: [:]) { out, pair in
            out[pair.key] = ThemeSource(id: pair.key, text: pair.value, file: "builtin:\(pair.key).toml", builtin: true)
        }
    }

    public static let kadomoDark = """
    name = "Kadomo Dark"
    appearance = "dark"
    layout = "center"

    [colors]
    background = "#000000"
    foreground = "#e8e8ea"
    muted = "#8b8b90"
    accent = "#62c1ff"
    selection_background = "#29292c"
    selection_foreground = "#62c1ff"
    border = ["#b26cf3", "#5ea8f5"]
    separator = "#ffffff14"
    shadow = "#0000008c"
    placeholder = "#7c7c82"
    caret = "#62c1ff"
    breadcrumb = "#c08cf7"
    hint = "#6f6f75"
    error = "#ff6b81"
    warning = "#ffc759"

    [font]
    family = "JetBrainsMono Nerd Font"   # install.sh installs it; falls back to SF Mono
    size = 15
    weight = "regular"
    search_size = 16
    subtitle_size = 11
    hint_size = 12
    selected_weight = "regular"

    [geometry]
    width = 295
    max_rows = 10
    row_height = 48
    row_spacing = 4
    padding = 18
    search_height = 44
    gap = 10
    corner_radius = 16
    row_corner_radius = 8
    border_width = 2
    icon_size = 18
    row_inset = 20

    [effects]
    background_opacity = 0.97
    material = "none"
    selection_style = "fill"
    show_subtitles = false
    show_chevrons = true
    placeholder = "Go…"
    """

    public static let kadomoMinimal = """
    name = "Kadomo Minimal"
    extends = "kadomo-dark"
    appearance = "auto"
    layout = "top"

    [colors]
    background = "#1c1c1e"
    foreground = "#f2f2f7"
    muted = "#98989d"
    accent = "#0a84ff"
    selection_background = "#0b5fd6"
    selection_foreground = "#ffffff"
    border = "#ffffff1f"
    placeholder = "#8e8e93"
    caret = "#0a84ff"
    breadcrumb = "#98989d"
    hint = "#8e8e93"

    [colors.light]
    background = "#f6f6f6"
    foreground = "#1d1d1f"
    muted = "#6e6e73"
    accent = "#007aff"
    selection_background = "#0b5fd6"
    selection_foreground = "#ffffff"
    border = "#0000001a"
    separator = "#0000000f"
    shadow = "#00000040"
    placeholder = "#8e8e93"
    caret = "#007aff"
    breadcrumb = "#6e6e73"
    hint = "#8e8e93"

    [font]
    family = "system"
    size = 14
    search_size = 20
    search_weight = "light"
    subtitle_size = 11
    hint_size = 11
    selected_weight = "medium"

    [geometry]
    width = 640
    max_rows = 8
    row_height = 36
    row_spacing = 2
    padding = 10
    search_height = 44
    gap = 6
    corner_radius = 12
    row_corner_radius = 6
    border_width = 1
    icon_size = 20
    top_offset = 0.18
    row_inset = 10

    [effects]
    background_opacity = 0.80
    material = "popover"
    show_subtitles = true
    show_chevrons = false
    show_separator = true
    icon_style = "auto"
    placeholder = "Search"
    """

    public static let kadomoTerminal = """
    name = "Kadomo Terminal"
    extends = "kadomo-dark"
    appearance = "dark"
    layout = "compact"

    [colors]
    background = "#0b0e0b"
    foreground = "#c8d3c5"
    muted = "#6b7a68"
    accent = "#8ae234"
    selection_background = "#8ae234"
    selection_foreground = "#0b0e0b"
    border = "#3a4a36"
    separator = "#3a4a36"
    placeholder = "#4f5c4c"
    caret = "#8ae234"
    breadcrumb = "#8ae234"
    hint = "#6b7a68"

    [font]
    family = "monospace"
    size = 13
    search_size = 13
    hint_size = 11
    subtitle_size = 11
    selected_weight = "bold"

    [geometry]
    width = 520
    max_rows = 16
    row_height = 22
    row_spacing = 0
    padding = 6
    search_height = 26
    gap = 4
    corner_radius = 0
    row_corner_radius = 0
    border_width = 1
    icon_size = 0
    top_offset = 0.25
    row_inset = 8

    [effects]
    background_opacity = 1.0
    shadow_radius = 0
    animation_duration = 0
    selection_style = "fill"
    show_icons = false
    show_chevrons = false
    show_separator = true
    show_footer = true
    placeholder = "> "
    icon_style = "none"
    """

    public static let kadomoLight = """
    name = "Kadomo Light"
    extends = "kadomo-dark"
    appearance = "light"

    [colors]
    background = "#fbfbfd"
    foreground = "#1d1d22"
    muted = "#6c6c74"
    accent = "#2f6fe4"
    selection_background = "#ebe7fb"
    selection_foreground = "#5b3cc4"
    border = ["#b26cf3", "#5ea8f5"]
    separator = "#0000000f"
    shadow = "#00000033"
    placeholder = "#9a9aa2"
    caret = "#5b3cc4"
    breadcrumb = "#7d4fd9"
    hint = "#8a8a92"
    """
}
