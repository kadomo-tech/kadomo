#!/usr/bin/env bash
# The macOS menu bar, on demand. Showing it moves the bar, and OmniWM's windows
# below the bar, down by the menu bar's height. Hiding it puts all of it back.
#   menu_bar.sh [toggle]   flip it: a click on the item
#   menu_bar.sh show|hide  Kadomo Menu's entries, which run this with no CONFIG_DIR
#   menu_bar.sh sync       match the bar to the menu bar, which a reload resets
CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}"
source "$CONFIG_DIR/colors.sh"

SETTINGS="${XDG_CONFIG_HOME:-$HOME/.config}/omniwm/settings.toml"
# "<gap before> <gap while showing>", while the gap is raised. Not in CONFIG_DIR:
# install.sh would take a changed folder for one you edited.
GAP_FILE="${KADOMO_STATE_DIR:-$HOME/Library/Application Support/kadomo}/sketchybar-menu-bar-gap"

autohide() { # get | true | false
  case "$1" in
    get) osascript -e 'tell application "System Events" to get autohide menu bar of dock preferences' 2>/dev/null ;;
    *) osascript -e "tell application \"System Events\" to set autohide menu bar of dock preferences to $1" >/dev/null 2>&1 ;;
  esac
}

# Differs by Mac: taller with a notch. What the screens reserve at the top, at
# least the height of a menu bar without one.
menu_bar_height() {
  osascript -l JavaScript -e '
    ObjC.import("AppKit");
    const screens = ObjC.unwrap($.NSScreen.screens);
    Math.max(24, ...screens.map(s => s.frame.size.height - s.visibleFrame.origin.y - s.visibleFrame.size.height));
  ' 2>/dev/null || echo 24
}

# settings.toml itself, following a link to where it really is.
settings_target() {
  local path="$SETTINGS" link
  while [ -L "$path" ]; do
    link="$(readlink "$path")"
    case "$link" in /*) path="$link" ;; *) path="$(dirname "$path")/$link" ;; esac
  done
  printf '%s' "$path"
}

gap_get() {
  awk '$0 == "[gaps.outer]" { on = 1; next } /^\[/ { on = 0 } on && $1 == "top" && $2 == "=" { print $3; exit }' "$(settings_target)"
}

# Written atomically; OmniWM sees the new file and reloads it.
gap_set() {
  local target tmp
  target="$(settings_target)"
  tmp="$(dirname "$target")/.settings.toml.kadomo.$$"
  awk -v v="$1" '
    $0 == "[gaps.outer]" { on = 1; print; next }
    /^\[/ { on = 0 }
    on && $1 == "top" && $2 == "=" { print "top = " v; next }
    { print }' "$target" >"$tmp" && mv -f "$tmp" "$target"
}

gap_raise() {
  local before raised
  [ -f "$(settings_target)" ] && [ ! -f "$GAP_FILE" ] || return 0
  before="$(gap_get)"
  [ -n "$before" ] || return 0
  raised="$(awk -v g="$before" -v h="$1" 'BEGIN { printf "%.1f", g + h }')"
  mkdir -p "$(dirname "$GAP_FILE")"
  echo "$before $raised" >"$GAP_FILE"
  gap_set "$raised"
}

# A gap you changed while the menu bar was showing stays.
gap_restore() {
  local before raised
  [ -f "$GAP_FILE" ] || return 0
  read -r before raised <"$GAP_FILE"
  if [ -f "$(settings_target)" ] && [ "$(gap_get)" = "$raised" ]; then gap_set "$before"; fi
  rm -f "$GAP_FILE"
}

apply() { # <autohide: true | false>
  if [ "$1" = true ]; then
    sketchybar --bar y_offset=0 --set menu_bar icon="󰍜" icon.color="$FG"
    gap_restore
  else
    local height
    height="$(menu_bar_height)"
    sketchybar --bar y_offset="$height" --set menu_bar icon="󰍝" icon.color="$ACCENT"
    gap_raise "$height"
  fi
}

hidden="$(autohide get)"
# Without System Events there is no telling, and no way to change it.
[ -n "$hidden" ] || exit 0

case "${1:-toggle}" in
  sync) apply "$hidden" ;;
  show) autohide false && apply false ;;
  hide) autohide true && apply true ;;
  toggle)
    if [ "$hidden" = true ]; then next=false; else next=true; fi
    autohide "$next" && apply "$next"
    ;;
esac
