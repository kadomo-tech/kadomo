#!/usr/bin/env bash
# Highlight the focused OmniWM workspace.
# Workspace id is derived from $NAME (e.g. "space.3" → "3").
# $FOCUSED_WORKSPACE is set by the omniwm_workspace_change trigger.

source "$CONFIG_DIR/colors.sh"

SID="${NAME#space.}"
FOCUSED="${FOCUSED_WORKSPACE:-$(omniwmctl query active-workspace 2>/dev/null | tr -d '\n ' | sed -n 's/.*"number":\([0-9]*\).*/\1/p')}"

if [ "$SID" = "$FOCUSED" ]; then
  sketchybar --set "$NAME" \
    background.drawing=on \
    background.color="$BLUE" \
    icon.color="$BG"
else
  sketchybar --set "$NAME" \
    background.drawing=off \
    icon.color="$FG"
fi
