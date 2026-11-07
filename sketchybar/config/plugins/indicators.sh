#!/usr/bin/env bash
# State indicators, Omarchy-bar style: shown only while the state is on.
# Stay awake (caffeinate) and Do Not Disturb (an active Focus assertion).
source "$CONFIG_DIR/colors.sh"

if pgrep -x caffeinate >/dev/null 2>&1; then
  sketchybar --set indicator_awake drawing=on icon="󰅶" icon.color="$FG"
else
  sketchybar --set indicator_awake drawing=off
fi

DND_DB="$HOME/Library/DoNotDisturb/DB/Assertions.json"
if [ -f "$DND_DB" ] && plutil -convert json -o - "$DND_DB" 2>/dev/null \
     | python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if any(r.get("storeAssertionRecords") for r in d.get("data",[])) else 1)' 2>/dev/null; then
  sketchybar --set indicator_dnd drawing=on icon="󰂛" icon.color="$FG"
else
  sketchybar --set indicator_dnd drawing=off
fi
