# {{ theme_name }}: JankyBorders' colors around the focused and the other windows.
# kadomo-borders puts them in ~/.config/borders/bordersrc and on the running
# borders; the border width and style stay as you set them there.
# Focused: the theme's hyprland_active_border, else its accent. Others: its
# hyprland_inactive_border, else color8 (the theme's "bright black", a neutral gray).
active_color={{ borders_color hyprland_active_border accent }}
inactive_color={{ borders_color hyprland_inactive_border color8 }}
