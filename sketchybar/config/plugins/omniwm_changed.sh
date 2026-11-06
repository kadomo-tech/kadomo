#!/usr/bin/env bash
# Run by `omniwmctl watch` on each workspace change, with the event's JSON on stdin.
source "$CONFIG_DIR/colors.sh"

FOCUSED="$(tr -d '\n ' | sed -n 's/.*"number":\([0-9]*\).*/\1/p')"
[ -n "$FOCUSED" ] && sketchybar --trigger omniwm_workspace_change FOCUSED_WORKSPACE="$FOCUSED"
