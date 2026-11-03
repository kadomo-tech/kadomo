# Shared by install.sh, aerospace/, omniwm/ and kadomo-wm: which window manager
# Kadomo runs, and the one login agent that starts it. Sourced, never run.
# Runs on the Bash 3.2 that ships with macOS.
#
# Both window managers may be installed, but only the chosen one runs and
# starts at login. The choice is one word, aerospace or omniwm, in
#   ${XDG_STATE_HOME:-~/.local/state}/kadomo/wm-choice
# It is written only when someone picks a manager (the installer, or
# kadomo-wm use), so an install that finds it keeps that choice. The file
# "window-manager" next to it is an older Kadomo's and is not read.

KADOMO_WM_STATE="${XDG_STATE_HOME:-$HOME/.local/state}/kadomo"
KADOMO_WM_CHOICE="$KADOMO_WM_STATE/wm-choice"
KADOMO_WM_BIN="$HOME/.local/bin/kadomo-wm"
KADOMO_WM_AGENT_LABEL="tech.kadomo.window-manager"
KADOMO_WM_AGENT_PLIST="$HOME/Library/LaunchAgents/$KADOMO_WM_AGENT_LABEL.plist"

# The saved choice, or nothing when nobody picked one yet.
wm_choice() {
    local choice
    [[ -s "$KADOMO_WM_CHOICE" ]] || return 1
    choice="$(head -n 1 "$KADOMO_WM_CHOICE" | tr -d '[:space:]')"
    case "$choice" in aerospace|omniwm) printf '%s' "$choice" ;; *) return 1 ;; esac
}

wm_save_choice() {
    case "$1" in aerospace|omniwm) ;; *) return 2 ;; esac
    mkdir -p "$KADOMO_WM_STATE"
    printf '%s\n' "$1" >"$KADOMO_WM_CHOICE.tmp.$$"
    mv -f "$KADOMO_WM_CHOICE.tmp.$$" "$KADOMO_WM_CHOICE"
}

wm_label() {
    case "$1" in aerospace) printf 'AeroSpace Kadomo' ;; omniwm) printf 'OmniWM' ;; *) printf '%s' "$1" ;; esac
}

# The login agent: at login it runs "kadomo-wm login", which starts the chosen
# manager and quits the other one if its own setting started it.
wm_agent_plist() {
    cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$KADOMO_WM_AGENT_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$KADOMO_WM_BIN</string>
        <string>login</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
PLIST
}

# Puts kadomo-wm and its login agent in place. Writing the same agent again
# changes nothing, so installing twice never adds a second one. Loading it is
# left to the next login: kadomo-wm use starts the manager now.
wm_install_switcher() { # <source wm/bin dir> <dry run: 0|1>
    local src="$1" dry="${2:-0}"
    if ! cmp -s "$src/kadomo-wm" "$KADOMO_WM_BIN"; then
        echo "  +  ${KADOMO_WM_BIN/#$HOME/~}"
        if ((dry == 0)); then mkdir -p "$(dirname "$KADOMO_WM_BIN")"; install -m 755 "$src/kadomo-wm" "$KADOMO_WM_BIN"; fi
    fi
    if [[ "$(cat "$KADOMO_WM_AGENT_PLIST" 2>/dev/null)" != "$(wm_agent_plist)" ]]; then
        echo "  +  ${KADOMO_WM_AGENT_PLIST/#$HOME/~} (starts the chosen window manager at login)"
        if ((dry == 0)); then mkdir -p "$(dirname "$KADOMO_WM_AGENT_PLIST")"; wm_agent_plist >"$KADOMO_WM_AGENT_PLIST"; fi
    fi
}

# Removes kadomo-wm, its agent and the choice. Each manager's uninstall.sh
# calls it once no window manager of Kadomo's is left.
wm_remove_switcher() { # <dry run: 0|1>
    local dry="${1:-0}" path
    if [[ -e "$KADOMO_WM_AGENT_PLIST" ]] && ((dry == 0)); then
        launchctl bootout "gui/$(id -u)/$KADOMO_WM_AGENT_LABEL" 2>/dev/null || true
    fi
    for path in "$KADOMO_WM_AGENT_PLIST" "$KADOMO_WM_BIN" "$KADOMO_WM_CHOICE"; do
        [[ -e "$path" ]] || continue
        echo "  -  ${path/#$HOME/~}"
        ((dry)) || rm -f -- "$path"
    done
}
