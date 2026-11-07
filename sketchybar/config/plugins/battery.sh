#!/usr/bin/env bash
source "$CONFIG_DIR/colors.sh"

PERCENTAGE="$(pmset -g batt | grep -Eo '[0-9]+%' | head -1 | tr -d '%')"
CHARGING="$(pmset -g batt | grep -c 'AC Power')"

[ -z "$PERCENTAGE" ] && exit 0

if [ "$CHARGING" -gt 0 ]; then
  ICON="󰂄"
  COLOR="$FG"
else
  case "$PERCENTAGE" in
    100|9[0-9]) ICON="󰁹"; COLOR="$FG" ;;
    [7-8][0-9]) ICON="󰂀"; COLOR="$FG" ;;
    [4-6][0-9]) ICON="󰁾"; COLOR="$FG" ;;
    [2-3][0-9]) ICON="󰁼"; COLOR="$FG" ;;
    *)          ICON="󰂃"; COLOR="$RED" ;;
  esac
fi

sketchybar --set "$NAME" \
  icon="$ICON" \
  icon.color="$COLOR"
