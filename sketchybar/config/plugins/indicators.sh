#!/usr/bin/env bash
# State indicator, Omarchy-bar style: shown only while the state is on.
# Do Not Disturb (an active Focus assertion).
source "$CONFIG_DIR/colors.sh"

DND_DB="$HOME/Library/DoNotDisturb/DB/Assertions.json"
if [ -f "$DND_DB" ] && plutil -convert json -o - "$DND_DB" 2>/dev/null \
     | python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if any(r.get("storeAssertionRecords") for r in d.get("data",[])) else 1)' 2>/dev/null; then
  sketchybar --set indicator_dnd drawing=on icon="󰂛" icon.color="$FG"
else
  sketchybar --set indicator_dnd drawing=off
fi
