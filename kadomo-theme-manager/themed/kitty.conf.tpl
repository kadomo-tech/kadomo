# {{ theme_name }}: kitty colors, included from your kitty.conf.

background {{ background }}
foreground {{ foreground }}
cursor {{ cursor }}
cursor_text_color background
selection_background {{ selection_background }}
selection_foreground {{ selection_foreground }}
url_color {{ cyan }}

# Tab bar, shown with more than one tab.
tab_bar_background {{ background }}
active_tab_background {{ selection }}
active_tab_foreground {{ bright_foreground }}
inactive_tab_background {{ background }}
inactive_tab_foreground {{ dark_foreground }}

# Window borders, with more than one window in a tab.
active_border_color {{ accent }}
inactive_border_color {{ inactive_border }}

# Normal colors (0-7)
color0 {{ color0 }}
color1 {{ color1 }}
color2 {{ color2 }}
color3 {{ color3 }}
color4 {{ color4 }}
color5 {{ color5 }}
color6 {{ color6 }}
color7 {{ color7 }}

# Bright colors (8-15)
color8 {{ color8 }}
color9 {{ color9 }}
color10 {{ color10 }}
color11 {{ color11 }}
color12 {{ color12 }}
color13 {{ color13 }}
color14 {{ color14 }}
color15 {{ color15 }}
