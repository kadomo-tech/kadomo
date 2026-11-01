#!/bin/bash
# Undoes install.sh: takes Kadomo's Moonlight profile out of linearmouse.json
# (backed up first; your other LinearMouse settings and profiles stay, and a
# file Kadomo created and nothing else uses goes), and removes the launch
# agent that opens LinearMouse at login. When Kadomo installed LinearMouse and
# nothing else is set up in it, it offers to uninstall LinearMouse too. A
# LinearMouse you installed yourself is never removed. Moonlight, macOS mouse settings, and the
# Windows host are not touched. Safe to run again.
#
# A LinearMouse that goes is quit before anything is removed.
#
# Usage: ./uninstall.sh [--dry-run] [--yes] [--stop]
#   --dry-run   show what would change without touching anything
#   --yes       uninstall LinearMouse, when it may go, without asking
#   --stop      only quit LinearMouse when it would go (with --yes); remove nothing
#
# Runs on the Bash 3.2 that ships with macOS.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/mouse.sh"
DRY_RUN=0
YES=0
STOP_ONLY=0

while (($#)); do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        --yes|-y) YES=1 ;;
        --stop) STOP_ONLY=1 ;;
        -h|--help) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
    esac
    shift
done

run() { if ((DRY_RUN)); then echo "    would run: $*"; else "$@"; fi; }

if [[ ! -d "$RECORD_DIR" ]]; then
    echo "  =  no moonlight-mouse installed"
    exit 0
fi

failed=0
config="$(recorded_config_path)"
label="$(short_path "$config")"
# How many LinearMouse schemes are left that are not Kadomo's; empty when unknown.
others=""

# Quits LinearMouse, so Homebrew can remove it cleanly.
quit_linearmouse() {
    local app
    lm_running && app="$(app_path "$LM_APP")" || return 0
    stop_app "$app" || true
}

# Stopped first: LinearMouse, when it goes too (Kadomo installed it, nothing
# else is set up in it, and --yes said so).
if ((STOP_ONLY)); then
    if [[ -e "$BREW_RECORD" ]] && ((YES)) && lm_running; then
        if [[ ! -e "$config" ]]; then n=0
        elif [[ ! -s "$SCHEME_RECORD" ]]; then n="$(lm_js count "$config" 2>/dev/null || true)"
        else n="$(lm_js remove "$config" "$SCHEME_RECORD" 1 2>/dev/null | awk '{ print $2 }' || true)"; fi
        [[ "$n" != 0 ]] || quit_linearmouse
    fi
    exit 0
fi

# --- the Moonlight profile ---------------------------------------------------

if [[ ! -e "$config" ]]; then
    others=0
    [[ ! -s "$SCHEME_RECORD" ]] || echo "  =  Moonlight profile (already removed)"
elif [[ ! -s "$SCHEME_RECORD" ]]; then
    # Kadomo added no profile (another Moonlight profile was there): every scheme is yours.
    others="$(lm_js count "$config" 2>/dev/null || true)"
elif ! result="$(lm_js remove "$config" "$SCHEME_RECORD" 1)"; then
    echo "  !  could not read $label; left it as it is" >&2
    failed=1
else
    read -r outcome others <<<"$result"
    case "$outcome" in
        absent)
            echo "  =  Moonlight profile (already removed)"
            ;;
        removed|edited)
            if [[ "$outcome" == removed && "$others" == 0 && -e "$CREATED_RECORD" ]]; then
                echo "  -  $label (Kadomo created it, and it holds nothing else)"
                run rm -f -- "$config"
                run rmdir "$(dirname "$config")" 2>/dev/null || true
            else
                backup="$(backup_path "$config")"
                note=""
                [[ "$outcome" == removed ]] || note="; you had changed it, and the backup keeps your version"
                echo "  -  Moonlight profile in $label (backed up to $(basename "$backup")$note)"
                run cp -p "$config" "$backup"
                if ! ((DRY_RUN)) && ! lm_js remove "$config" "$SCHEME_RECORD" 0 >/dev/null; then
                    echo "  !  could not update $label" >&2
                    failed=1
                fi
            fi
            ;;
    esac
fi

# --- opening at login --------------------------------------------------------

if [[ -e "$LAUNCH_AGENT" ]]; then
    echo "  -  $(short_path "$LAUNCH_AGENT")"
    # Loaded only after a login, and it has exited by then; unloading it is tidy, not required.
    run launchctl bootout "gui/$(id -u)/$LAUNCH_AGENT_LABEL" 2>/dev/null || true
    run rm -f -- "$LAUNCH_AGENT"
fi
if [[ -e "$LOGIN_RECORD" ]]; then
    echo "  -  login item: LinearMouse"
    if ((DRY_RUN)); then
        echo "    would run: osascript (System Events: delete login item LinearMouse)"
    elif ! remove_login_item; then
        echo "  !  could not remove it; remove LinearMouse in System Settings › General › Login Items" >&2
    fi
fi

# --- LinearMouse itself, only when Kadomo installed it -------------------------

if [[ -e "$BREW_RECORD" ]]; then
    hint="remove it any time with: brew uninstall --cask $LM_CASK"
    if ! brew="$(find_brew)"; then
        echo "  !  Homebrew not found; LinearMouse left installed" >&2
        # The record stays, so a later run with Homebrew back can finish the job.
        failed=1
    elif ! "$brew" list --cask "$LM_CASK" >/dev/null 2>&1; then
        echo "  =  LinearMouse (already removed)"
    elif [[ "$others" != 0 ]]; then
        if [[ -z "$others" ]]; then echo "  =  LinearMouse kept (its config could not be read; $hint)"
        else echo "  =  LinearMouse kept: it has $others profile(s) of yours ($hint)"; fi
    elif ((DRY_RUN)); then
        if ((YES)); then echo "  -  LinearMouse (Kadomo installed it; brew uninstall --cask $LM_CASK)"
        else echo "  -  LinearMouse (Kadomo installed it; asks before brew uninstall --cask $LM_CASK)"; fi
    else
        answer=n
        if ((YES)); then
            answer=y
        elif [[ -t 0 ]]; then
            read -r -p "  Kadomo installed LinearMouse, and nothing else is set up in it. Uninstall it too? [y/N] " answer </dev/tty || answer=n
        fi
        if [[ "$answer" == [yY]* ]]; then
            quit_linearmouse
            echo "  -  LinearMouse (brew uninstall --cask $LM_CASK)"
            "$brew" uninstall --cask "$LM_CASK" || { echo "  !  brew uninstall --cask $LM_CASK failed" >&2; failed=1; }
        else
            echo "  =  LinearMouse kept ($hint)"
        fi
    fi
fi

if ((failed == 0)); then
    run rm -rf -- "$RECORD_DIR"
    run rmdir "$STATE_DIR" 2>/dev/null || true
fi

((DRY_RUN)) && echo "Dry run: nothing was changed."
exit "$failed"
