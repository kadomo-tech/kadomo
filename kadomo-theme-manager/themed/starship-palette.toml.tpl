# {{ theme_name }}: Starship prompt colors, one per role. theme-starship puts
# them under [palettes.kadomo] of Kadomo's Starship config; only name = "#rrggbb"
# lines are used. Each is nudged, if needed, until it reads on the background.
text = "{{ readable foreground background 4.5 }}"
secondary = "{{ readable dark_foreground background 3 }}"
directory = "{{ readable accent background 3 }}"
branch = "{{ readable magenta background 3 }}"
success = "{{ readable success background 3 }}"
error = "{{ readable error background 3 }}"
changes = "{{ readable warning background 3 }}"
runtime = "{{ readable cyan background 3 }}"
separator = "{{ readable comment background 2 }}"
