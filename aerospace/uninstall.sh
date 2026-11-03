#!/bin/bash
# Removes what install.sh put in place: AeroSpace Kadomo (when Kadomo installed
# it), the aerospace command link, kadomo-aerospace and kadomo-borders, Kadomo's
# aerospace.toml and bordersrc, JankyBorders (when Kadomo installed it), and the
# Kadomo Menu entries. Your files that install.sh set aside come back. A copy of
# your edits to Kadomo's configs (<name>.kadomo-edited) stays.
# What an older Kadomo installed for AeroSpace goes too (remove-legacy.sh).
#
# AeroSpace Kadomo and its borders are quit first. OmniWM, if Kadomo installed
# it, stays, and so do kadomo-wm and its login agent while it does; with no
# window manager of Kadomo's left, they go too.
#
# Usage: ./uninstall.sh [--dry-run | --stop]
#   --stop   only quit AeroSpace Kadomo and its borders; remove nothing
#
# Runs on the Bash 3.2 that ships with macOS.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
source "$HERE/aerospace.sh"
source "$ROOT/wm/wm.sh"
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
short() { printf '%s' "${1/#$HOME/~}"; }
ours() { [[ -f "$1" && ! -L "$1" ]] && head -n 2 "$1" | grep -qF "$2"; }
find_brew() {
    local path
    for path in "$(command -v brew 2>/dev/null)" /opt/homebrew/bin/brew /usr/local/bin/brew; do
        [[ -n "$path" && -x "$path" ]] && { printf '%s' "$path"; return 0; }
    done
    return 1
}

legacy_args=()
((DRY_RUN == 0)) || legacy_args=(--dry-run)

renewed=0
{ [[ -s "$AEROSPACE_MANIFEST" ]] || [[ -e "$AEROSPACE_BIN" || -e "$BORDERS_BIN" || -e "$AEROSPACE_MENU_FILE" ]] \
    || ours "$AEROSPACE_CONFIG" "# Kadomo's AeroSpace config" || ours "$BORDERS_RC" "# Kadomo's JankyBorders config"; } && renewed=1

if ((STOP_ONLY)); then
    [[ ! -x "$AEROSPACE_BIN" ]] || "$AEROSPACE_BIN" stop || true
    exit 0
fi

if ((renewed == 0)); then
    # Only an older Kadomo's AeroSpace, or nothing: remove-legacy.sh says which.
    exec "$HERE/remove-legacy.sh" ${legacy_args[@]+"${legacy_args[@]}"}
fi

if [[ -x "$AEROSPACE_BIN" ]] && "$AEROSPACE_BIN" status 2>/dev/null | grep -q ': running$'; then
    echo "  ■  quitting AeroSpace Kadomo and its borders"
    run "$AEROSPACE_BIN" stop || true
elif pgrep -xq borders 2>/dev/null && [[ -x "$BORDERS_BIN" ]]; then
    echo "  ■  stopping borders"
    run "$BORDERS_BIN" stop || true
fi

if [[ -n "$(aerospace_recorded app)" && -d "$AEROSPACE_APP" ]]; then
    echo "  -  $(short "$AEROSPACE_APP") ($(aerospace_app_version))"
    run rm -rf -- "$AEROSPACE_APP"
    run tccutil reset Accessibility "$AEROSPACE_ID" >/dev/null 2>&1 || true
fi
removed_link=0
if [[ -L "$AEROSPACE_CLI_LINK" && "$(readlink "$AEROSPACE_CLI_LINK")" == "$AEROSPACE_APP_CLI" ]]; then
    echo "  -  $(short "$AEROSPACE_CLI_LINK")"
    run rm -f -- "$AEROSPACE_CLI_LINK"
    removed_link=1
fi
for path in "$AEROSPACE_BIN" "$BORDERS_BIN" "$AEROSPACE_MENU_FILE"; do
    [[ -e "$path" ]] || continue
    echo "  -  $(short "$path")"
    run rm -f -- "$path"
done
# What is removed here, so a dry run knows which places become free.
removed=" "
((removed_link == 0)) || removed="$removed$AEROSPACE_CLI_LINK "
if ours "$AEROSPACE_CONFIG" "# Kadomo's AeroSpace config"; then
    echo "  -  $(short "$AEROSPACE_CONFIG")"
    run rm -f -- "$AEROSPACE_CONFIG"
    removed="$removed$AEROSPACE_CONFIG "
fi
if ours "$BORDERS_RC" "# Kadomo's JankyBorders config"; then
    echo "  -  $(short "$BORDERS_RC")"
    run rm -f -- "$BORDERS_RC"
    removed="$removed$BORDERS_RC "
fi
if [[ -d "$AEROSPACE_LAYOUT_STATE" ]]; then
    echo "  -  $(short "$AEROSPACE_LAYOUT_STATE") (the layout picked for each workspace)"
    run rm -rf -- "$AEROSPACE_LAYOUT_STATE"
fi

# Your files come back where they were, unless something new is there now.
while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    backup="$path$AEROSPACE_BACKUP_SUFFIX"
    if [[ ! -e "$backup" && ! -L "$backup" ]]; then
        ((DRY_RUN)) || aerospace_forget backup "$path"
        continue
    fi
    if [[ -e "$path" || -L "$path" ]] && [[ "$removed" != *" $path "* ]]; then
        echo "  !  $(short "$backup") stays: $(short "$path") is there again" >&2
        continue
    fi
    echo "  ↩  $(short "$path") (put back)"
    run mv "$backup" "$path"
    ((DRY_RUN)) || aerospace_forget backup "$path"
done < <(aerospace_recorded backup)

formula="$(aerospace_recorded formula | head -n 1)"
if [[ -n "$formula" ]]; then
    if brew="$(find_brew)"; then
        echo "  -  borders (brew uninstall $formula)"
        if run "$brew" uninstall "$formula"; then ((DRY_RUN)) || aerospace_forget formula; fi
    else
        echo "  !  Homebrew not found; remove JankyBorders with: brew uninstall $formula" >&2
    fi
fi

# kadomo-wm and its agent stay while OmniWM is Kadomo's; the choice of AeroSpace goes.
if [[ -e "$HOME/.local/bin/kadomo-omniwm" ]]; then
    if [[ "$(wm_choice || true)" == aerospace ]]; then
        echo "  -  $(short "$KADOMO_WM_CHOICE") (AeroSpace was the window manager; start OmniWM from Kadomo Menu › Services › OmniWM)"
        run rm -f -- "$KADOMO_WM_CHOICE"
    fi
else
    wm_remove_switcher "$DRY_RUN"
fi

# Whatever an older Kadomo installed for AeroSpace.
"$HERE/remove-legacy.sh" ${legacy_args[@]+"${legacy_args[@]}"} | grep -v 'no aerospace installed' || true

# A JankyBorders that could not be removed stays recorded, so the next run tries again.
if ((DRY_RUN == 0)) && [[ -z "$(aerospace_recorded formula)" && -z "$(aerospace_recorded backup)" ]]; then
    rm -f -- "$AEROSPACE_MANIFEST"
fi
((DRY_RUN)) && echo "Dry run: nothing was changed."
exit 0
