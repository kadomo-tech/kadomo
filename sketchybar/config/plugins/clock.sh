#!/usr/bin/env bash
# Day and time. A click flips between 24-hour and 12-hour time; a right click
# opens Date & Time settings.
source "$CONFIG_DIR/colors.sh"

# Present while 12-hour, so a reload keeps the choice. Not in CONFIG_DIR:
# install.sh would take a changed folder for one you edited.
TWELVE_FILE="${KADOMO_STATE_DIR:-$HOME/Library/Application Support/kadomo}/sketchybar-clock-12h"

if [ "$SENDER" = "mouse.clicked" ]; then
  if [ "$BUTTON" = right ]; then
    open "x-apple.systempreferences:com.apple.Date-Time-Settings.extension"
    exit 0
  fi
  if [ -e "$TWELVE_FILE" ]; then
    rm -f "$TWELVE_FILE"
  else
    mkdir -p "${TWELVE_FILE%/*}" && touch "$TWELVE_FILE"
  fi
fi

if [ -e "$TWELVE_FILE" ]; then
  # %l pads the hour with a space; drop it.
  label="$(date '+%A %l:%M %p' | tr -s ' ')"
else
  label="$(date '+%A %H:%M')"
fi
sketchybar --set "$NAME" label="$label"
