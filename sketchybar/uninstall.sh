#!/bin/bash
# Removes what install.sh put in place. The bar is stopped first; ~/.config/sketchybar
# goes (one you edited is kept as sketchybar.bak.<timestamp>) and the folder it replaced
# comes back; the menu bar and OmniWM's IPC and top gap go back to how they were; and
# what Kadomo installed from Homebrew goes. A package you installed yourself stays.
#
# Usage: ./uninstall.sh [--dry-run | --stop]
#   --stop   only stop the bar; remove nothing
#
# Runs on the Bash 3.2 that ships with macOS.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/sketchybar.sh"
STAMP="$(date +%Y%m%d-%H%M%S)"
DRY_RUN=0
STOP_ONLY=0

case "${1:-}" in
    "") ;;
    --dry-run) DRY_RUN=1 ;;
    --stop) STOP_ONLY=1 ;;
    -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
esac

run() { if ((DRY_RUN)); then echo "    would run: $*"; else "$@"; fi; }

if [[ ! -s "$SKETCHYBAR_MANIFEST" ]]; then
    echo "  =  no sketchybar installed"
    exit 0
fi

brew="$(find_brew || true)"

# Whether Kadomo installed this package.
recorded_line() { grep -qxF "$1|$2" "$SKETCHYBAR_MANIFEST"; }

# Stopped first, so nothing is removed while it runs. A bar you were already running stays up.
if [[ -n "$brew" ]] && { sketchybar_has_record service || recorded_line formula "$SKETCHYBAR_FORMULA"; }; then
    if pgrep -xq sketchybar 2>/dev/null; then
        echo "  ■  stopping SketchyBar"
        run "$brew" services stop sketchybar >/dev/null 2>&1 || true
        # Its watcher stops itself with the bar, within seconds; this is at once.
        run pkill -f "sketchybar/plugins/omniwm_watch.sh" || true
        run pkill -f "omniwmctl watch active-workspace" || true
    fi
fi
((STOP_ONLY == 0)) || exit 0

# The menu bar.
if sketchybar_has_record hide-menu-bar; then
    echo "  ↩  the macOS menu bar (how it was before Kadomo)"
    before="$(sketchybar_recorded hide-menu-bar)"
    if [[ "$before" == absent ]]; then run defaults delete NSGlobalDomain _HIHideMenuBar 2>/dev/null || true
    else run defaults write NSGlobalDomain _HIHideMenuBar -int "$before"; fi
    run osascript -e "tell application \"System Events\" to set autohide menu bar of dock preferences to $(sketchybar_recorded autohide-menu-bar)" >/dev/null 2>&1 \
        || echo "  !  could not show the menu bar now; it comes back after you log out and back in" >&2
fi

# OmniWM's settings, unless you have changed them since.
if [[ -f "$(sketchybar_omniwm_target)" ]]; then
    if sketchybar_has_record omniwm-ipc && [[ "$(sketchybar_omniwm_get general ipcEnabled)" == true ]]; then
        echo "  ↩  OmniWM's IPC (off, as it was)"
        run sketchybar_omniwm_set general ipcEnabled "$(sketchybar_recorded omniwm-ipc)"
    fi
    if sketchybar_has_record omniwm-gap-top && [[ "$(sketchybar_omniwm_get gaps.outer top)" == "$SKETCHYBAR_HEIGHT.0" ]]; then
        echo "  ↩  OmniWM's top gap"
        run sketchybar_omniwm_set gaps.outer top "$(sketchybar_recorded omniwm-gap-top)"
    fi
fi

# The config.
label="${SKETCHYBAR_CONFIG/#$HOME/~}"
sha="$(sketchybar_recorded config-sha)"
backup="$(sketchybar_recorded config-backup)"
if [[ -d "$SKETCHYBAR_CONFIG" && ! -L "$SKETCHYBAR_CONFIG" ]]; then
    if [[ "$(sketchybar_tree_sha "$SKETCHYBAR_CONFIG")" == "$sha" ]]; then
        echo "  -  $label"
        run rm -rf -- "$SKETCHYBAR_CONFIG"
    else
        kept="$SKETCHYBAR_CONFIG.bak.$STAMP"
        echo "  ~  $label (edited since install; kept as $(basename "$kept"))"
        run mv "$SKETCHYBAR_CONFIG" "$kept"
    fi
fi
if [[ -n "$backup" && -e "$backup" ]]; then
    echo "  ↩  $label (restored from $(basename "$backup"))"
    run mv "$backup" "$SKETCHYBAR_CONFIG"
fi

# Your own bar, still running, reads the config it has again.
if ! recorded_line formula "$SKETCHYBAR_FORMULA" && ! sketchybar_has_record service && pgrep -xq sketchybar 2>/dev/null; then
    run sketchybar --reload >/dev/null 2>&1 || true
fi

# The fonts Kadomo registered with macOS, while their files are still here.
while IFS='|' read -r kind path; do
    [[ "$kind" == font-file && -f "$path" ]] || continue
    if ((DRY_RUN)); then echo "    would run: unregister $path"
    else osascript -l JavaScript "$HERE/fonts.js" unregister "$path" >/dev/null 2>&1 || echo "  !  could not unregister $(basename "$path")" >&2; fi
done <"$SKETCHYBAR_MANIFEST"

# The packages Kadomo installed.
if [[ -n "$brew" ]]; then
    while IFS='|' read -r kind name; do
        case "$kind" in
            formula)
                echo "  -  ${name##*/} (brew uninstall $name)"
                run "$brew" uninstall --formula "$name" || echo "  !  brew uninstall $name failed" >&2
                ;;
            cask)
                echo "  -  $name (brew uninstall --cask $name)"
                run "$brew" uninstall --cask "$name" || echo "  !  brew uninstall --cask $name failed" >&2
                ;;
        esac
    done <"$SKETCHYBAR_MANIFEST"
    tap="$(sketchybar_recorded tap)"
    if [[ -n "$tap" ]] && grep -qixF "$tap" <<<"$("$brew" tap)"; then
        echo "  -  tap $tap"
        # Refuses while other formulae from the tap are still installed; those keep it.
        run "$brew" untap "$tap" 2>/dev/null || echo "  =  tap $tap kept (other formulae still use it)"
    fi
elif grep -qE '^(formula|cask)\|' "$SKETCHYBAR_MANIFEST"; then
    echo "  !  Homebrew not found; left SketchyBar's packages installed" >&2
fi

run rm -f -- "$SKETCHYBAR_MANIFEST"
run rmdir "$STATE_DIR" 2>/dev/null || true
((DRY_RUN)) && echo "Dry run: nothing was changed."
exit 0
