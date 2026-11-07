#!/usr/bin/env bash
# Update badge: how many Homebrew packages are outdated. Hidden at zero.
source "$CONFIG_DIR/colors.sh"

# A failed brew run (lock held, offline) keeps the last count instead of hiding it.
OUTDATED="$(brew outdated --quiet 2>/dev/null)" || exit 0
COUNT="$(printf '%s' "$OUTDATED" | grep -c .)"
if [ "${COUNT:-0}" -gt 0 ]; then
  sketchybar --set "$NAME" drawing=on icon="󰚰" icon.color="$FG" label="$COUNT" label.color="$FG"
else
  sketchybar --set "$NAME" drawing=off
fi
