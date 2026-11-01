# {{ theme_name }}: Kadomo Menu colors. Used while the launcher's theme is "kadomo".
name = "Kadomo ({{ theme_name }})"
appearance = "{{ mode }}"

[colors]
background = "{{ background }}"
foreground = "{{ foreground }}"
muted = "{{ dark_foreground }}"
accent = "{{ accent }}"
selection_background = "{{ selection_background }}"
selection_foreground = "{{ bright_foreground }}"
border = {{ toml_gradient hyprland_active_border accent }}
separator = "{{ lighter_background }}"
placeholder = "{{ dark_foreground }}"
caret = "{{ cursor }}"
breadcrumb = "{{ accent }}"
hint = "{{ dark_foreground }}"
error = "{{ red }}"
warning = "{{ yellow }}"
