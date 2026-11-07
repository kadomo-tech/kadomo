#!/bin/bash
# Removes what install.sh put in place: kadomo-omniwm and the Kadomo Menu
# entries, and the OmniWM login agent older installs left. (What they
# installed for AeroSpace is remove-aerospace.sh's.) OmniWM's border goes back to
# the colors it had before Kadomo's theme, and the workspace keys Kadomo set come
# off unless you have changed them. OmniWM itself is quit and
# uninstalled only when Kadomo installed it; one you installed yourself stays,
# and so does its settings.toml.
#
# An older login agent and an OmniWM Kadomo installed are stopped before
# anything is removed.
#
# Usage: ./uninstall.sh [--dry-run | --stop]
#   --stop   only stop an older login agent and an OmniWM Kadomo installed; remove nothing
#
# Runs on the Bash 3.2 that ships with macOS.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/omniwm.sh"
DRY_RUN=0
STOP_ONLY=0

case "${1:-}" in
    "") ;;
    --dry-run) DRY_RUN=1 ;;
    --stop) STOP_ONLY=1 ;;
    -h|--help) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
esac

run() { if ((DRY_RUN)); then echo "    would run: $*"; else "$@"; fi; }

if [[ ! -s "$OMNIWM_MANIFEST" && ! -e "$OMNIWM_BIN" && ! -e "$OMNIWM_AGENT_PLIST" && ! -e "$OMNIWM_MENU_FILE" \
      && ! -s "$OMNIWM_BORDERS_BEFORE" && ! -e "$OMNIWM_WORKSPACE_KEYS" ]]; then
    echo "  =  no omniwm installed"
    exit 0
fi

find_brew() {
    local path
    for path in "$(command -v brew 2>/dev/null)" /opt/homebrew/bin/brew /usr/local/bin/brew; do
        [[ -n "$path" && -x "$path" ]] && { printf '%s' "$path"; return 0; }
    done
    return 1
}

cask="$(omniwm_recorded cask)"

# Stopped first, so nothing is removed while it runs: the login agent, then an
# OmniWM Kadomo installed (one you installed yourself keeps running).
if launchctl print "gui/$(id -u)/$OMNIWM_AGENT_LABEL" >/dev/null 2>&1; then
    echo "  ■  stopping the login agent ($OMNIWM_AGENT_LABEL)"
    run launchctl bootout "gui/$(id -u)/$OMNIWM_AGENT_LABEL" 2>/dev/null || true
fi
if [[ -n "$cask" ]] && pgrep -xq OmniWM 2>/dev/null; then
    echo "  ■  quitting OmniWM"
    if ((DRY_RUN == 0)); then
        osascript -e "tell application id \"$OMNIWM_ID\" to quit" >/dev/null 2>&1 || true
        for ((i=0; i<40; i++)); do pgrep -xq OmniWM 2>/dev/null || break; sleep 0.25; done
        pkill -x OmniWM 2>/dev/null || true
    fi
fi
((STOP_ONLY == 0)) || exit 0

# The border colors from before Kadomo's theme, while kadomo-omniwm is still here.
if [[ -s "$OMNIWM_BORDERS_BEFORE" ]]; then
    echo "  ↩  OmniWM's border colors (from before Kadomo's theme)"
    if [[ -x "$OMNIWM_BIN" ]]; then run "$OMNIWM_BIN" restore-borders || echo "  !  could not put OmniWM's border colors back" >&2
    else run "$HERE/bin/kadomo-omniwm" restore-borders || echo "  !  could not put OmniWM's border colors back" >&2; fi
fi

# The workspace keys Kadomo set, also while kadomo-omniwm is still here.
if [[ -e "$OMNIWM_WORKSPACE_KEYS" ]]; then
    echo "  ↩  OmniWM's next and previous workspace keys"
    if [[ -x "$OMNIWM_BIN" ]]; then run "$OMNIWM_BIN" restore-workspace-keys || echo "  !  could not take OmniWM's workspace keys off" >&2
    else run "$HERE/bin/kadomo-omniwm" restore-workspace-keys || echo "  !  could not take OmniWM's workspace keys off" >&2; fi
fi

# The login agent older installs put in place.
if [[ -e "$OMNIWM_AGENT_PLIST" ]]; then
    echo "  -  ${OMNIWM_AGENT_PLIST/#$HOME/~}"
    run rm -f -- "$OMNIWM_AGENT_PLIST"
fi
for path in "$OMNIWM_MENU_FILE" "$OMNIWM_BIN"; do
    if [[ -e "$path" || -L "$path" ]]; then echo "  -  ${path/#$HOME/~}"; run rm -f -- "$path"; fi
done

if [[ -n "$cask" ]]; then
    if brew="$(find_brew)"; then
        if omniwm_app >/dev/null; then
            echo "  -  OmniWM (brew uninstall --cask $cask; its settings in ~/.config/omniwm stay)"
            run "$brew" uninstall --cask "$cask" || echo "  !  brew uninstall --cask $cask failed" >&2
        fi
    else
        echo "  !  Homebrew not found; OmniWM is left installed (brew uninstall --cask $cask)" >&2
    fi
else
    omniwm_app >/dev/null && echo "  =  OmniWM (you installed it; it stays)"
fi

run rm -f -- "$OMNIWM_MANIFEST"
run rmdir "$OMNIWM_STATE_DIR" 2>/dev/null || true
((DRY_RUN)) && echo "Dry run: nothing was changed."
exit 0
