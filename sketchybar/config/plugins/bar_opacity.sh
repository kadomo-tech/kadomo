#!/usr/bin/env bash
# A double click on an empty part of the bar: its background goes to the next
# opacity, 50%, 25%, 10%, 100%, and round again. A reload puts the theme's own back.
source "$CONFIG_DIR/colors.sh"

[ "${BUTTON:-left}" = left ] || exit 0

# SketchyBar has no double click event: each click runs this once, so the first
# leaves the time for the second to find. Milliseconds, which macOS's date lacks.
LAST="${TMPDIR:-/tmp}/sketchybar-last-click"
WINDOW_MS=400
now="$(perl -MTime::HiRes=time -e 'printf "%d", time * 1000')"
last="$(cat "$LAST" 2>/dev/null || echo 0)"
if [ $((now - last)) -gt "$WINDOW_MS" ]; then
  echo "$now" >"$LAST"
  exit 0
fi
rm -f "$LAST"

color="$(sketchybar --query bar | sed -n 's/.*"color": *"\(0x[^"]*\)".*/\1/p' | head -1)"
case "$color" in
  0x80*) alpha=40 ;;
  0x40*) alpha=1a ;;
  0x1a*) alpha=ff ;;
  *) alpha=80 ;;
esac
sketchybar --bar color="0x$alpha${BG_TRANS#0x??}"
