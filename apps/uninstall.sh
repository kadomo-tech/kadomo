#!/bin/bash
# Uninstalls the apps install.sh installed with Homebrew. Running apps are
# quit first (btop and htop stopped); Neovim is left open, so no unsaved work
# is lost. Apps you installed yourself are left alone, and so is each app's
# own data (settings, browser profiles), as with a plain `brew uninstall`.
# The terminal app this runs in is kept: quitting it would end this script.
#
# Usage: ./uninstall.sh [--dry-run] [--stop | --retired]
#   --dry-run   show what would change without touching anything
#   --stop      only quit the apps Kadomo installed; remove nothing
#   --retired   only remove apps this checkout no longer installs (such as an
#               older Kadomo's kitty); install.sh runs it
#
# Runs on the Bash 3.2 that ships with macOS.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/apps.sh"
DRY_RUN=0
STOP_ONLY=0
RETIRED_ONLY=0

while (($#)); do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        --stop) STOP_ONLY=1 ;;
        --retired) RETIRED_ONLY=1 ;;
        -h|--help) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
    esac
    shift
done

run() { if ((DRY_RUN)); then echo "    would run: $*"; else "$@"; fi; }

if [[ ! -s "$APPS_MANIFEST" ]]; then
    ((RETIRED_ONLY)) || echo "  =  no apps installed"
    exit 0
fi

# Where a recorded app is installed, or nothing (formulae have no app).
recorded_app() { # <kind> <name>
    local entry
    [[ "$1" == cask ]] && entry="$(app_entry "$1" "$2")" && app_path "$(app_field "$entry" 4)"
}

# Every app first, so nothing is removed while it runs. With --retired, only
# the apps this checkout no longer installs; one it still ships is left running.
stop_all() {
    local kind name app
    while IFS='|' read -r kind name; do
        [[ -n "$name" ]] || continue
        ((RETIRED_ONLY == 0)) || ! in_apps "$kind" "$name" || continue
        if app="$(recorded_app "$kind" "$name")"; then stop_app "$app" || true
        else
            case "$name" in btop|htop) stop_command "$name" ;; esac
        fi
    done <"$APPS_MANIFEST"
}
stop_all
((STOP_ONLY == 0)) || exit 0

if ! brew="$(find_brew)"; then
    echo "  !  Homebrew not found; left these apps installed:" >&2
    sed 's/^[^|]*|/       /' "$APPS_MANIFEST" >&2
    # The record stays, so a later run with Homebrew back can finish the job.
    exit 1
fi

failed=0
kept=()
# With --retired, the records of apps this checkout still ships stay as they are.
still_shipped=()
while IFS='|' read -r kind name; do
    [[ -n "$name" ]] || continue
    if ((RETIRED_ONLY)) && in_apps "$kind" "$name"; then
        still_shipped+=("$kind|$name")
        continue
    fi
    if ! "$brew" list "--$kind" "$name" >/dev/null 2>&1; then
        echo "  =  $name (already removed)"
        continue
    fi
    # An app cannot be removed while it runs, and the terminal this runs in
    # cannot be quit without ending this: it is left in place. Its record stays,
    # so ./uninstall.sh run from another terminal removes it later.
    if app="$(recorded_app "$kind" "$name")" && app_running "$app" && runs_inside "$app"; then
        echo "  =  $(basename "$app" .app) left in place: it is running (this uninstaller runs in it), and a running app cannot be removed"
        kept+=("$(basename "$app" .app)|$kind|$name")
        continue
    fi
    echo "  -  $name (brew uninstall --$kind $name)"
    run "$brew" uninstall "--$kind" "$name" || { echo "  !  brew uninstall --$kind $name failed" >&2; failed=1; }
done <"$APPS_MANIFEST"

if ((failed == 0 && ${#kept[@]} == 0)); then
    if ((${#still_shipped[@]})); then
        # --retired: only the records of what is gone go.
        ((DRY_RUN)) || printf '%s\n' "${still_shipped[@]}" >"$APPS_MANIFEST"
    else
        run rm -f -- "$APPS_MANIFEST"
        run rmdir "$STATE_DIR" 2>/dev/null || true
    fi
fi
if ((${#kept[@]} && DRY_RUN == 0)); then
    printf '\n  Still needs you:\n'
    for ((i=0; i<${#kept[@]}; i++)); do
        IFS='|' read -r label kind name <<<"${kept[i]}"
        printf '  %s. %s is still installed: it was running this uninstaller, and a running app cannot be removed, so it was left in place. Kadomo'\''s config and theme for it are removed with the other parts. To remove %s too, quit it and run ./uninstall.sh from Terminal (or brew uninstall --%s %s).\n' \
            "$((i+1))" "$label" "$label" "$kind" "$name"
    done
fi

((DRY_RUN && !RETIRED_ONLY)) && echo "Dry run: nothing was changed."
exit "$failed"
