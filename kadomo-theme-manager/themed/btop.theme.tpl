# {{ theme_name }}: btop colors, shown as ~/.config/btop/themes/current.theme.

# Empty main_bg keeps the terminal background, including Ghostty's opacity.
theme[main_bg]=""
theme[main_fg]="{{ foreground }}"
theme[title]="{{ bright_foreground }}"
theme[hi_fg]="{{ red }}"
theme[selected_bg]="{{ selection }}"
theme[selected_fg]="{{ foreground }}"
theme[inactive_fg]="{{ dark_foreground }}"
theme[graph_text]="{{ foreground }}"
theme[meter_bg]="{{ selection }}"
theme[proc_misc]="{{ cyan }}"

# Box outlines and dividers
theme[cpu_box]="{{ blue }}"
theme[mem_box]="{{ green }}"
theme[net_box]="{{ magenta }}"
theme[proc_box]="{{ yellow }}"
theme[div_line]="{{ selection }}"

# Gradients run cool to hot.
theme[temp_start]="{{ cyan }}"
theme[temp_mid]="{{ yellow }}"
theme[temp_end]="{{ red }}"

theme[cpu_start]="{{ cyan }}"
theme[cpu_mid]="{{ blue }}"
theme[cpu_end]="{{ red }}"

theme[free_start]="{{ blue }}"
theme[free_mid]="{{ yellow }}"
theme[free_end]="{{ green }}"

theme[cached_start]="{{ cyan }}"
theme[cached_mid]="{{ magenta }}"
theme[cached_end]="{{ blue }}"

theme[available_start]="{{ magenta }}"
theme[available_mid]="{{ blue }}"
theme[available_end]="{{ yellow }}"

theme[used_start]="{{ yellow }}"
theme[used_mid]="{{ green }}"
theme[used_end]="{{ red }}"

theme[download_start]="{{ blue }}"
theme[download_mid]="{{ magenta }}"
theme[download_end]="{{ cyan }}"

theme[upload_start]="{{ yellow }}"
theme[upload_mid]="{{ green }}"
theme[upload_end]="{{ red }}"

theme[process_start]="{{ cyan }}"
theme[process_mid]="{{ blue }}"
theme[process_end]="{{ red }}"
