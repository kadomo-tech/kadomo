#!/bin/zsh
# Renders the launcher offscreen for each theme and state into .build/shots.
#   tools/snap.sh                       all themes, all states
#   THEMES=kadomo-dark STATES=home,apps tools/snap.sh
# Uses a throwaway config dir, never your real ~/.config/kadomo-menu.
set -euo pipefail
here=${0:A:h:h}
bin=${BIN:-$here/.build/direct/debug/KadomoMenu}
out=$here/.build/shots
tmp=${TMPDIR:-/tmp}/kadomo-menu-snap
rm -rf "$out"; mkdir -p "$out" "$tmp"
export KADOMO_MENU_THEME_SET= KADOMO_MENU_CONFIG_DIR=$tmp/config KADOMO_MENU_STATE_DIR=$tmp/state KADOMO_MENU_SOCKET=$tmp/s.sock KADOMO_MENU_SNAPSHOT=$out
[[ -n ${THEMES:-} ]] && export KADOMO_MENU_SNAPSHOT_THEMES=$THEMES
[[ -n ${STATES:-} ]] && export KADOMO_MENU_SNAPSHOT_STATES=$STATES
KADOMO_MENU_GUI=1 "$bin"
