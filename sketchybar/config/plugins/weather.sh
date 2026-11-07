#!/usr/bin/env bash
# Temperature from wttr.in for the current location (IP-based). Hidden offline.
# Without wttr.in's condition: it comes as an emoji, in color.
source "$CONFIG_DIR/colors.sh"

OUT="$(curl -s --max-time 5 'https://wttr.in/?format=%t' 2>/dev/null | tr -d '\n' | sed 's/+//')"
if [ -n "$OUT" ] && [[ "$OUT" != *"Unknown"* ]] && [[ "$OUT" != *"Sorry"* ]]; then
  sketchybar --set "$NAME" drawing=on label="$OUT" label.color="$FG"
else
  sketchybar --set "$NAME" drawing=off
fi
