#!/usr/bin/env bash
# The focused OmniWM workspace is a dot; the others are dim numbers.
# Workspace id is derived from $NAME (e.g. "space.3" → "3").
# $FOCUSED_WORKSPACE is set by the omniwm_workspace_change trigger.

source "$CONFIG_DIR/colors.sh"

SID="${NAME#space.}"
FOCUSED="${FOCUSED_WORKSPACE:-$(omniwmctl query active-workspace 2>/dev/null | tr -d '\n ' | sed -n 's/.*"number":\([0-9]*\).*/\1/p')}"

if [ "$SID" = "$FOCUSED" ]; then
  sketchybar --set "$NAME" \
    icon="󰝥" \
    icon.color="$FG"
else
  sketchybar --set "$NAME" \
    icon="$SID" \
    icon.color="$COMMENT"
fi
