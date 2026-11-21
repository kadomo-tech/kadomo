# {{ theme_name }}: OmniWM's focus border, and the text on its workspace bar in
# the theme's bar_text (its cyan unless it names another).
# kadomo-omniwm puts the border tables in ~/.config/omniwm/settings.toml and
# the text color in the default profile of ~/.config/omniwm/shell/shell.toml,
# in place of the colors there; theme-set runs it. Border width and glow stay
# as you set them in OmniWM.
{{ omniwm_borders hyprland_active_border accent }}

{{ omniwm_color workspaceBar.textColor bar_text }}
