#!/bin/bash
# Kadomo used to ship AeroSpace with Scrolling as a second window manager. It
# now uses OmniWM only, and this removes what an older Kadomo put on the Mac
# for AeroSpace: Kadomo's build of the app (and the Accessibility grant macOS
# recorded for it), kadomo-aerospace and kadomo-workspace-layout, the
# ~/.local/bin/aerospace link, the login agents, the scrolling settings, the
# Kadomo Menu entries, and the saved choices and workspace layouts. A
# ~/.local/bin/aerospace it set aside is put back, and so is a regular
# AeroSpace that a much older Kadomo build replaced. A regular AeroSpace you
# installed yourself stays installed, but is quit, so it does not fight OmniWM.
# (The AeroSpace and JankyBorders configs are the dotfiles' to remove:
# dotfiles/uninstall.sh --retired.)
#
# omniwm/install.sh and the top-level install.sh and uninstall.sh run it.
# With nothing to remove, it says "no aerospace installed".
#
# Usage: ./remove-aerospace.sh [--dry-run]
#
# Runs on the Bash 3.2 that ships with macOS.
set -euo pipefail

DRY_RUN=0
case "${1:-}" in
    "") ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help) sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
esac

run() { if ((DRY_RUN)); then echo "    would run: $*"; else "$@"; fi; }

APP="/Applications/AeroSpace Kadomo.app"
APP_ID="tech.kadomo.aerospace"
APP_CLI="$APP/Contents/Helpers/aerospace"
REGULAR_APP="/Applications/AeroSpace.app"
REGULAR_ID="bobko.aerospace"
CLI_BIN="$HOME/.local/bin/aerospace"
SWITCH_BIN="$HOME/.local/bin/kadomo-aerospace"
LAYOUT_BIN="$HOME/.local/bin/kadomo-workspace-layout"
KADOMO_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}/kadomo"
LAYOUTS_DIR="$KADOMO_STATE_HOME/aerospace-layouts"
CHOICE_FILE="$KADOMO_STATE_HOME/aerospace-build"
# Which window manager ran, omniwm or aerospace: there is no choice any more.
WM_CHOICE_FILE="$KADOMO_STATE_HOME/window-manager"
MENU_FILE="${KADOMO_CONFIG:-$HOME/.config/kadomo}/menu/commands/aerospace.toml"
SCROLLING_CONFIG="${KADOMO_CONFIG:-$HOME/.config/kadomo}/aerospace/scrolling.toml"
AGENT_LABELS="tech.kadomo.aerospace-login tech.kadomo.aerospace-scrolling"
AGENTS_DIR="$HOME/Library/LaunchAgents"
# One <key>|<value> line per fact: cli-backup, version, and from the oldest
# builds (which replaced the regular app) cask and backup.
STATE_DIR="${KADOMO_STATE_DIR:-$HOME/Library/Application Support/kadomo}"
MANIFEST="$STATE_DIR/aerospace-installed.txt"
BACKUP_DIR="$STATE_DIR/aerospace-backup"

forget() {
    [[ -f "$MANIFEST" ]] || return 0
    awk -F'|' -v k="$1" '$1 != k' "$MANIFEST" >"$MANIFEST.tmp"
    mv "$MANIFEST.tmp" "$MANIFEST"
}
recorded() {
    [[ -f "$MANIFEST" ]] || return 0
    awk -F'|' -v k="$1" '$1 == k { print $2; exit }' "$MANIFEST"
}
find_brew() {
    local path
    for path in "$(command -v brew 2>/dev/null)" /opt/homebrew/bin/brew /usr/local/bin/brew; do
        [[ -n "$path" && -x "$path" ]] && { printf '%s' "$path"; return 0; }
    done
    return 1
}
app_version() { /usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$1/Contents/Info.plist" 2>/dev/null || true; }
kadomo_build_installed() { [[ "$(app_version "$APP")" == *-kadomo.* ]]; }
# An older Kadomo build (0.21.3-kadomo.1 or .2) in the regular app's place.
legacy_build_installed() { [[ "$(app_version "$REGULAR_APP")" == *-kadomo.* ]]; }
ours_script() { [[ -f "$1" ]] && grep -q "$2" "$1"; }
# ~/.local/bin/aerospace is Kadomo's: the link to its CLI, or the file older builds put there.
ours_cli() {
    if [[ -L "$CLI_BIN" ]]; then [[ "$(readlink "$CLI_BIN")" == "$APP_CLI" ]]; return; fi
    [[ -x "$CLI_BIN" && "$("$CLI_BIN" --version 2>/dev/null | head -1)" == *-kadomo.* ]]
}
agent_plists() { local label; for label in $AGENT_LABELS; do printf '%s\n' "$AGENTS_DIR/$label.plist"; done; }

anything=0
[[ -s "$MANIFEST" ]] && anything=1
kadomo_build_installed && anything=1
legacy_build_installed && anything=1
ours_cli && anything=1
ours_script "$SWITCH_BIN" 'kadomo-aerospace' && anything=1
ours_script "$LAYOUT_BIN" 'kadomo-workspace-layout' && anything=1
while IFS= read -r plist; do [[ -e "$plist" ]] && anything=1; done < <(agent_plists)
for path in "$SCROLLING_CONFIG" "$MENU_FILE" "$CHOICE_FILE" "$LAYOUTS_DIR" "$WM_CHOICE_FILE"; do [[ -e "$path" ]] && anything=1; done
((anything)) || { echo "  =  no aerospace installed"; exit 0; }

echo "  Kadomo no longer includes AeroSpace; removing what an older Kadomo installed for it"

# Stopped first, so nothing is removed while it runs: the login agents (so
# nothing starts AeroSpace again), then any AeroSpace and the JankyBorders it started.
for label in $AGENT_LABELS; do
    if launchctl print "gui/$(id -u)/$label" >/dev/null 2>&1; then
        echo "  ■  stopping the login agent ($label)"
        run launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
    fi
done
if pgrep -xq AeroSpace 2>/dev/null; then
    echo "  ■  quitting AeroSpace"
    for id in "$APP_ID" "$REGULAR_ID"; do run osascript -e "tell application id \"$id\" to quit" >/dev/null 2>&1 || true; done
    if ((DRY_RUN == 0)); then
        for ((i=0; i<20; i++)); do pgrep -xq AeroSpace 2>/dev/null || break; sleep 0.25; done
        pkill -x AeroSpace 2>/dev/null || true
    fi
fi
if pgrep -xq borders 2>/dev/null; then
    echo "  ■  stopping borders (AeroSpace started it)"
    run pkill -x borders || true
fi

while IFS= read -r plist; do
    [[ -e "$plist" ]] || continue
    echo "  -  ${plist/#$HOME/~}"
    run rm -f -- "$plist"
done < <(agent_plists)
if [[ -e "$SCROLLING_CONFIG" ]]; then
    echo "  -  ${SCROLLING_CONFIG/#$HOME/~} (the scrolling settings)"
    run rm -f -- "$SCROLLING_CONFIG"
    run rmdir "$(dirname "$SCROLLING_CONFIG")" 2>/dev/null || true
fi
if kadomo_build_installed; then
    echo "  -  $APP ($(app_version "$APP"))"
    run rm -rf -- "$APP"
    run tccutil reset Accessibility "$APP_ID" >/dev/null 2>&1 || true
fi

# The oldest Kadomo builds took the regular app's place: put back the app they
# set aside, or the Homebrew cask they uninstalled.
if legacy_build_installed; then
    echo "  -  $REGULAR_APP ($(app_version "$REGULAR_APP"), an older Kadomo build in the regular app's place)"
    run rm -rf -- "$REGULAR_APP"
    run tccutil reset Accessibility "$REGULAR_ID" >/dev/null 2>&1 || true
fi
backup="$(recorded backup)"
if [[ -n "$backup" && -e "$backup" && ! -e "$REGULAR_APP" ]]; then
    echo "  ↩  $REGULAR_APP (put back)"
    run mv "$backup" "$REGULAR_APP"
    ((DRY_RUN)) || forget backup
fi
cask="$(recorded cask)"
if [[ -n "$cask" ]]; then
    if brew="$(find_brew)"; then
        echo "  +  the regular AeroSpace (brew install --cask $cask), which an older Kadomo build replaced"
        if run "$brew" install --cask "$cask"; then
            ((DRY_RUN)) || forget cask
        else
            echo "  !  brew install --cask $cask failed; run it yourself to get the regular AeroSpace back" >&2
        fi
    else
        echo "  !  Homebrew not found; get the regular AeroSpace back with: brew install --cask $cask" >&2
    fi
fi

# The link points into the app just removed, so test it by its target.
if [[ -L "$CLI_BIN" && "$(readlink "$CLI_BIN")" == "$APP_CLI" ]] || { [[ -f "$CLI_BIN" && ! -L "$CLI_BIN" ]] && ours_cli; }; then
    echo "  -  ${CLI_BIN/#$HOME/~}"
    run rm -f -- "$CLI_BIN"
fi
cli_backup="$(recorded cli-backup)"
if [[ -n "$cli_backup" && ( -e "$cli_backup" || -L "$cli_backup" ) && ! -e "$CLI_BIN" && ! -L "$CLI_BIN" ]]; then
    echo "  ↩  ${CLI_BIN/#$HOME/~} (put back)"
    run mv "$cli_backup" "$CLI_BIN"
fi
for bin in "$SWITCH_BIN" "$LAYOUT_BIN"; do
    if ours_script "$bin" "${bin##*/}"; then
        echo "  -  ${bin/#$HOME/~}"
        run rm -f -- "$bin"
    fi
done
if [[ -e "$MENU_FILE" ]]; then
    echo "  -  ${MENU_FILE/#$HOME/~} (the Kadomo Menu entries)"
    run rm -f -- "$MENU_FILE"
fi
if [[ -e "$CHOICE_FILE" || -e "$WM_CHOICE_FILE" || -d "$LAYOUTS_DIR" ]]; then
    echo "  -  the saved window manager choice and workspace layouts (${KADOMO_STATE_HOME/#$HOME/~})"
    run rm -rf -- "$CHOICE_FILE" "$WM_CHOICE_FILE" "$LAYOUTS_DIR"
    run rmdir "$KADOMO_STATE_HOME" 2>/dev/null || true
fi

# A cask that could not be put back stays recorded, so the next run tries again.
if ((DRY_RUN == 0)) && [[ -z "$(recorded cask)" ]]; then
    rm -f -- "$MANIFEST"
    rmdir "$BACKUP_DIR" 2>/dev/null || true
    rmdir "$STATE_DIR" 2>/dev/null || true
fi
exit 0
