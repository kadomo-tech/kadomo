#!/bin/bash
# Installs OmniWM, Kadomo's window manager (niri-style scrolling and dwindle
# tiling, with its own focus border), and starts it:
#   /Applications/OmniWM.app                  from Homebrew (brew install --cask omniwm),
#                                             unless it is on the Mac already
#   ~/.local/bin/kadomo-omniwm                a command, not a background process: puts the
#                                             Kadomo theme's colors on OmniWM's border when
#                                             the theme changes, and writes the menu entries
#   ~/.config/kadomo/menu/commands/omniwm.toml
#                                             Kadomo Menu › Services › OmniWM (start, stop,
#                                             match theme borders, edit settings) and
#                                             OmniWM's keys under Keybinds
#   ~/.config/omniwm/settings.toml            Ctrl+Option+Left / Right for previous / next
#                                             workspace, when those are free
# Nothing of Kadomo's runs at login: OmniWM starts itself, once you turn that on
# in its settings. What an older Kadomo installed for AeroSpace, and its OmniWM
# login agent, are removed (remove-aerospace.sh). macOS asks once to allow
# OmniWM in Privacy & Security › Accessibility (and Input Monitoring).
# OmniWM needs macOS 26 or later on Apple silicon.
#
# Usage: ./install.sh [--dry-run]
#
# Runs on the Bash 3.2 that ships with macOS. Undo it with ./uninstall.sh.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OMNIWM_SOURCE_BIN="$HERE/bin"
source "$HERE/omniwm.sh"
DRY_RUN=0

case "${1:-}" in
    "") ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help) sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
esac

run() { if ((DRY_RUN)); then echo "    would run: $*"; else "$@"; fi; }

((EUID != 0)) || { echo "  !  run this as your own user, not with sudo" >&2; exit 1; }
omniwm_supported || { echo "  !  OmniWM $(omniwm_requirement)" >&2; exit 1; }

find_brew() {
    local path
    for path in "$(command -v brew 2>/dev/null)" /opt/homebrew/bin/brew /usr/local/bin/brew; do
        [[ -n "$path" && -x "$path" ]] && { printf '%s' "$path"; return 0; }
    done
    return 1
}

todo=()

if app="$(omniwm_app)"; then
    echo "  =  OmniWM (already installed, ${app/#$HOME/~})"
else
    brew="$(find_brew)" || { echo "  !  OmniWM needs Homebrew (https://brew.sh)" >&2; exit 1; }
    echo "  +  OmniWM (brew install --cask $OMNIWM_CASK)"
    run "$brew" install --cask "$OMNIWM_CASK"
    ((DRY_RUN)) || omniwm_record cask "$OMNIWM_CASK"
fi

echo "  +  ${OMNIWM_BIN/#$HOME/~}"
run mkdir -p "$(dirname "$OMNIWM_BIN")"
run install -m 755 "$HERE/bin/kadomo-omniwm" "$OMNIWM_BIN"

# The login agent older installs used: OmniWM starts itself at login now.
if [[ -e "$OMNIWM_AGENT_PLIST" ]]; then
    if launchctl print "gui/$(id -u)/$OMNIWM_AGENT_LABEL" >/dev/null 2>&1; then
        run launchctl bootout "gui/$(id -u)/$OMNIWM_AGENT_LABEL" 2>/dev/null || true
    fi
    echo "  -  ${OMNIWM_AGENT_PLIST/#$HOME/~} (OmniWM starts itself at login now)"
    run rm -f -- "$OMNIWM_AGENT_PLIST"
fi

# Before OmniWM starts: an AeroSpace from an older Kadomo would fight it.
remove_args=()
((DRY_RUN == 0)) || remove_args=(--dry-run)
"$HERE/remove-aerospace.sh" ${remove_args[@]+"${remove_args[@]}"} \
    || echo "  !  could not remove everything an older Kadomo installed for AeroSpace" >&2

# Writes the menu and starts OmniWM.
if ((DRY_RUN)); then
    echo "  ▶  would start OmniWM"
    echo "    would run: ${OMNIWM_BIN/#$HOME/~} start"
    echo "    would run: ${OMNIWM_BIN/#$HOME/~} workspace-keys"
else
    echo "  ▶  starting OmniWM (allow it in Privacy & Security › Accessibility if macOS asks)"
    "$OMNIWM_BIN" start || echo "  !  could not start OmniWM; open it from Applications" >&2
    # OmniWM writes settings.toml on its first start; then the border gets the theme's
    # colors and the workspace keys go in.
    for ((i=0; i<40; i++)); do [[ -f "$OMNIWM_SETTINGS" ]] && break; sleep 0.25; done
    if [[ -f "$OMNIWM_SETTINGS" ]]; then
        "$OMNIWM_BIN" theme || echo "  !  could not put the theme's colors on OmniWM's border" >&2
        "$OMNIWM_BIN" workspace-keys || echo "  !  could not set OmniWM's next and previous workspace keys" >&2
    fi
    pgrep -xq OmniWM 2>/dev/null \
        || todo+=("Allow OmniWM in System Settings › Privacy & Security › Accessibility and Input Monitoring, then start it from Kadomo Menu › Services › OmniWM.")
fi
todo+=("To have OmniWM start at login, turn that on in OmniWM's settings (its menu bar icon › Settings). macOS may ask you to allow it in System Settings › General › Login Items.")
if [[ "$(defaults read com.apple.spaces spans-displays 2>/dev/null || true)" == 1 ]]; then
    todo+=("Turn on \"Displays have separate Spaces\" in System Settings › Desktop & Dock (OmniWM needs it), then log out and back in.")
fi

if ((${#todo[@]})); then
    printf '\n  Still needs you:\n'
    for ((i=0; i<${#todo[@]}; i++)); do
        printf '%s\n' "${todo[i]}" | fold -s -w 76 | sed "s/ *$//; 1s/^/  $((i+1)). /; 1!s/^/     /"
    done
fi
((DRY_RUN)) && echo "Dry run: nothing was changed."
exit 0
