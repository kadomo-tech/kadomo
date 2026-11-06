#!/usr/bin/env bash
# Feeds OmniWM's workspace changes to the bar; sketchybarrc starts one. The watch
# exits when it cannot connect (OmniWM not running yet, or its IPC turned off), so
# it is tried again for as long as the bar runs.
source "$CONFIG_DIR/colors.sh"

# -a: pgrep leaves out its own ancestors otherwise, and the bar is one of them.
while pgrep -axq sketchybar; do
  omniwmctl watch active-workspace --exec "$CONFIG_DIR/plugins/omniwm_changed.sh"
  sleep 5
done
