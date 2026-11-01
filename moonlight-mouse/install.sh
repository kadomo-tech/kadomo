#!/bin/bash
# Moonlight Mouse Optimization: makes a mouse in Moonlight behave like one on
# a Windows PC, and leaves every other app as it was. Installs LinearMouse
# (brew install --cask linearmouse) unless it is already on this Mac, and adds
# one profile to its linearmouse.json that applies to a mouse (not the
# trackpad) only while Moonlight is the frontmost app: pointer acceleration
# off, scroll acceleration and smoothing off, 3 lines per wheel step, and
# Windows-style scrolling (wheel down moves the page down).
# Your other LinearMouse settings are kept, the file is backed up before it
# changes, and LinearMouse picks the change up without a restart. A launch
# agent opens LinearMouse at each login (it needs no permission), and
# LinearMouse is started now. macOS mouse settings are not changed. Run this
# again after you change macOS natural scrolling or Moonlight's own
# reverse-scrolling option. What Kadomo did is recorded, so uninstall.sh undoes
# exactly that.
#
# Usage: ./install.sh [--dry-run]
#   --dry-run   show what would change without touching anything
#
# Runs on the Bash 3.2 that ships with macOS.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/mouse.sh"
DRY_RUN=0

case "${1:-}" in
    "") ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
esac

run() { if ((DRY_RUN)); then echo "    would run: $*"; else "$@"; fi; }

# What still needs you, printed together at the end.
todo=()

# Records one fact about what Kadomo did (see mouse.sh).
mark() { # <record file> [content]
    ((DRY_RUN)) && return 0
    mkdir -p "$RECORD_DIR"
    printf '%s\n' "${2:-}" >"$1"
}

# --- LinearMouse -------------------------------------------------------------

app="$(app_path "$LM_APP" || true)"
if [[ -n "$app" ]]; then
    echo "  =  LinearMouse (already installed)"
elif ! brew="$(find_brew)"; then
    echo "  !  LinearMouse needs Homebrew (https://brew.sh); nothing changed" >&2
    exit 1
elif "$brew" list --cask "$LM_CASK" >/dev/null 2>&1; then
    echo "  =  LinearMouse (already installed)"
else
    echo "  +  LinearMouse (brew install --cask $LM_CASK)"
    if ((DRY_RUN)); then
        echo "    would run: $brew install --cask $LM_CASK"
    else
        "$brew" install --cask "$LM_CASK" || echo "  !  brew install --cask $LM_CASK failed" >&2
        # Recorded whenever Homebrew now has it, even after a failure part way,
        # so uninstall.sh can still remove it.
        "$brew" list --cask "$LM_CASK" >/dev/null 2>&1 || exit 1
        mark "$BREW_RECORD"
        app="$(app_path "$LM_APP" || true)"
    fi
fi

# --- the Moonlight profile ---------------------------------------------------

# Moonlight gets the wheel from macOS already flipped when natural scrolling is
# on, and sends it to Windows as it is, after its own reverse option. So the
# profile undoes natural scrolling, unless Moonlight's option already does.
natural="$(natural_scrolling)"
moonlight_reverse="$(moonlight_reverses)"
if [[ "$natural" != "$moonlight_reverse" ]]; then reverse=true; else reverse=false; fi

config="$(recorded_config_path)"
label="$(short_path "$config")"
wanted="$(moonlight_scheme "$reverse")"
recorded=""
[[ -s "$SCHEME_RECORD" ]] && recorded="$SCHEME_RECORD"
schema=""
if [[ -n "$app" ]] && version="$(defaults read "$app/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null)"; then
    schema="https://schema.linearmouse.app/$version"
fi
existed=0
[[ -e "$config" ]] && existed=1

result="$(lm_js apply "$config" "$wanted" "$recorded" "$schema" 1)" || {
    echo "  !  could not update $label; nothing changed there" >&2
    exit 1
}
read -r outcome others <<<"$result"

changed=0
case "$outcome" in
    added|updated)
        note=""
        # A file Kadomo created holds nothing of yours to keep.
        if ((existed)) && [[ ! -e "$CREATED_RECORD" ]]; then
            backup="$(backup_path "$config")"
            note=" (backed up to $(basename "$backup"))"
            run cp -p "$config" "$backup"
        fi
        if [[ "$outcome" == added ]]; then echo "  +  Moonlight profile in $label$note"
        else echo "  ~  Moonlight profile in $label (updated)$note"; fi
        if ! ((DRY_RUN)) && ! lm_js apply "$config" "$wanted" "$recorded" "$schema" 0 >/dev/null; then
            echo "  !  could not write $label" >&2
            exit 1
        fi
        changed=1
        ;;
    unchanged)
        echo "  =  Moonlight profile in $label (unchanged)"
        ;;
    edited)
        echo "  =  Moonlight profile in $label (changed since Kadomo set it up; left as you have it)"
        ;;
    conflict)
        echo "  !  $label already has a Moonlight profile that is not Kadomo's; left it alone" >&2
        todo+=("Kadomo's Moonlight profile was not added: a Moonlight profile of yours is already in LinearMouse. To use Kadomo's, delete yours in LinearMouse and run this again.")
        ;;
esac
if [[ "$outcome" == added || "$outcome" == updated || "$outcome" == unchanged ]]; then
    if ! ((DRY_RUN)); then
        mkdir -p "$RECORD_DIR"
        printf '%s\n' "$wanted" >"$SCHEME_RECORD"
        mark "$CONFIG_RECORD" "$config"
        ((existed)) || mark "$CREATED_RECORD"
    fi
fi

# --- starting LinearMouse, now and at login --------------------------------

if [[ -z "$app" ]]; then
    ((DRY_RUN)) || todo+=("LinearMouse.app was not found in ${APP_DIRS[*]}: open it yourself, and turn on Start at login in its General settings.")
else
    agent="$(launch_agent "$app")"
    if [[ -f "$LAUNCH_AGENT" ]] && [[ "$(cat "$LAUNCH_AGENT")" == "$agent" ]]; then
        echo "  =  $(short_path "$LAUNCH_AGENT") (opens LinearMouse at login)"
    else
        # Read by launchd at the next login; nothing is loaded now.
        echo "  +  $(short_path "$LAUNCH_AGENT") (opens LinearMouse at login)"
        if ! ((DRY_RUN)); then
            mkdir -p "$(dirname "$LAUNCH_AGENT")"
            printf '%s\n' "$agent" >"$LAUNCH_AGENT"
        fi
    fi

    if lm_running; then
        ((changed == 0)) || echo "  ↻  LinearMouse is running and reloads its config by itself"
    elif ((DRY_RUN)); then
        echo "  ▶  starting LinearMouse"
        echo "    would run: open $app"
    else
        # In front, not in the background, so macOS's own prompts are seen: the
        # first-open check for a downloaded app, then LinearMouse's request for
        # Accessibility access.
        echo "  ▶  starting LinearMouse"
        open "$app" 2>/dev/null || true
        if wait_for_linearmouse; then
            todo+=("If LinearMouse asks for Accessibility access, allow it in System Settings › Privacy & Security › Accessibility. It does nothing until you do.")
        else
            echo "  !  LinearMouse did not start" >&2
            todo+=("LinearMouse did not start. Open it from Applications; if macOS asks whether to open an app downloaded from the internet, choose Open. Then allow its Accessibility request.")
        fi
    fi
fi

# --- what to know in Moonlight -----------------------------------------------

if [[ "$outcome" != conflict ]]; then
    if [[ "$reverse" == true ]]; then how="LinearMouse reverses the wheel in Moonlight"
    else how="nothing to reverse"; fi
    echo "  i  Scrolling in Moonlight is Windows-style: macOS natural scrolling is $( ((natural)) && echo on || echo off),"
    echo "     Moonlight's Reverse mouse scrolling direction is $( ((moonlight_reverse)) && echo on || echo off), so $how."
    echo "     Change either one later? Run this installer again."
    echo "  i  Moonlight sends each wheel step to Windows as one notch, and Windows scrolls its own"
    echo "     \"lines per notch\" (3 by default). Pointer acceleration is off on the Mac side only:"
    echo "     also turn off Enhance pointer precision in Windows and any in-game acceleration."
    echo "     More: moonlight-mouse/README.md"
fi

if ((${#todo[@]})); then
    printf '\n  Still needs you:\n'
    for ((i=0; i<${#todo[@]}; i++)); do
        printf '%s\n' "${todo[i]}" | fold -s -w 76 | sed "s/ *$//; 1s/^/  $((i+1)). /; 1!s/^/     /"
    done
fi

((DRY_RUN)) && echo "Dry run: nothing was changed."
exit 0
