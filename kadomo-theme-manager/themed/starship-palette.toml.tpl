# {{ theme_name }}: Starship prompt colors for the M365Princess-style
# chevron chain (solid color blocks, merged by powerline arrows).
# theme-starship puts them under [palettes.kadomo] of Kadomo's Starship
# config; only name = "#rrggbb" lines are used. Each block is one of the
# theme's own hues; its text color is nudged toward black or white,
# whichever it takes, until it reads on that block (WCAG 4.5), so the chain
# stays legible on light and dark themes alike.
seg_user = "{{ accent }}"
seg_user_fg = "{{ readable foreground accent 4.5 }}"
seg_dir = "{{ bright_blue }}"
seg_dir_fg = "{{ readable foreground bright_blue 4.5 }}"
seg_git = "{{ bright_orange }}"
seg_git_fg = "{{ readable foreground bright_orange 4.5 }}"
seg_runtime = "{{ bright_cyan }}"
seg_runtime_fg = "{{ readable foreground bright_cyan 4.5 }}"
seg_duration = "{{ comment }}"
seg_duration_fg = "{{ readable foreground comment 4.5 }}"
success = "{{ readable success background 3 }}"
error = "{{ readable error background 3 }}"
