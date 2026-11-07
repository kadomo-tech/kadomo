#!/usr/bin/env bash
# Stand-up / sit-down state for the interval timer (~/.hermes/standup_timer.sh).
# The timer alternates 30 minutes seated, then 30 minutes standing. The state is
# derived from the age of the running timer process, so the timer needs no state
# file and does NOT have to be restarted when this widget changes.
#
# Phase 0 (first 30 min, and every other block after) = sitting.
# Phase 1 = standing.
source "$CONFIG_DIR/colors.sh"

PIDFILE="$HOME/.hermes/.standup_timer.pid"
PERIOD=1800

PID="$(cat "$PIDFILE" 2>/dev/null)"
if [ -z "$PID" ] || ! kill -0 "$PID" 2>/dev/null; then
  sketchybar --set "$NAME" drawing=off
  exit 0
fi

# ps etime is [[dd-]hh:]mm:ss; convert to seconds.
ELAPSED="$(ps -p "$PID" -o etime= 2>/dev/null | awk -F'[-:]' '
  { gsub(/ /,"") }
  NF==4 { print $1*86400+$2*3600+$3*60+$4; next }
  NF==3 { print $1*3600+$2*60+$3; next }
  NF==2 { print $1*60+$2 }')"
[ -n "$ELAPSED" ] || { sketchybar --set "$NAME" drawing=off; exit 0; }

if [ $(( (ELAPSED / PERIOD) % 2 )) -eq 0 ]; then
  ICON="󰽈"   # md-chair_rolling — seated
else
  ICON="󰙍"   # md-human_male — standing
fi

# Restate the full style on every run so a leftover debug style cannot stick.
sketchybar --set "$NAME" drawing=on \
  icon="$ICON" icon.color="$FG" icon.font="JetBrainsMono Nerd Font:Regular:15.0" \
  label.drawing=off label="" background.drawing=off
