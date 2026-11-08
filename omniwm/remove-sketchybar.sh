#!/bin/bash
# Kadomo used to ship SketchyBar as its status bar. OmniWM 0.8 has its own
# menu bar, so Kadomo no longer installs SketchyBar, and this removes what an
# older Kadomo put on the Mac for it: the bar is stopped first; its config
# goes (one you edited since is kept as sketchybar.bak.<timestamp>) and the
# folder it replaced comes back; the macOS menu bar and OmniWM's IPC and top
# gap go back to how they were; the fonts Kadomo registered are unregistered;
# the Kadomo Menu entries go; and what Kadomo installed from Homebrew goes. A
# package you installed yourself stays.
#
# omniwm/install.sh and the top-level install.sh and uninstall.sh run it.
# With nothing to remove, it says "no sketchybar installed".
#
# Usage: ./remove-sketchybar.sh [--dry-run]
#
# Runs on the Bash 3.2 that ships with macOS.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
DRY_RUN=0
case "${1:-}" in
    "") ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
esac

run() { if ((DRY_RUN)); then echo "    would run: $*"; else "$@"; fi; }

CONFIG="$HOME/.config/sketchybar"
OMNIWM_SETTINGS="${XDG_CONFIG_HOME:-$HOME/.config}/omniwm/settings.toml"
MENU_FILE="${KADOMO_CONFIG:-$HOME/.config/kadomo}/menu/commands/sketchybar.toml"
TAP="felixkratz/formulae"
FORMULA="$TAP/sketchybar"
HEIGHT=32
STATE_DIR="${KADOMO_STATE_DIR:-$HOME/Library/Application Support/kadomo}"
MANIFEST="$STATE_DIR/sketchybar-installed.txt"
MENU_BAR_GAP="$STATE_DIR/sketchybar-menu-bar-gap"

if [[ ! -s "$MANIFEST" ]]; then
    echo "  =  no sketchybar installed"
    exit 0
fi

echo "  Kadomo no longer includes SketchyBar; removing what an older Kadomo installed for it"

find_brew() {
    local path
    for path in "$(command -v brew 2>/dev/null)" /opt/homebrew/bin/brew /usr/local/bin/brew; do
        [[ -n "$path" && -x "$path" ]] && { printf '%s' "$path"; return 0; }
    done
    return 1
}
recorded() { awk -F'|' -v k="$1" '$1 == k { print $2; exit }' "$MANIFEST"; }
has_record() { grep -q "^$1|" "$MANIFEST"; }
recorded_line() { grep -qxF "$1|$2" "$MANIFEST"; }
tree_sha() { (cd "$1" && find . -type f ! -name .DS_Store -exec shasum -a 256 {} + | LC_ALL=C sort | shasum -a 256 | cut -d' ' -f1); }

# settings.toml itself, following a link to where it really is.
omniwm_target() {
    local path="$OMNIWM_SETTINGS" link
    while [[ -L "$path" ]]; do
        link="$(readlink "$path")"
        case "$link" in /*) path="$link" ;; *) path="$(dirname "$path")/$link" ;; esac
    done
    printf '%s' "$path"
}
omniwm_get() { # <table> <key>
    awk -v t="[$1]" -v k="$2" '$0 == t { on = 1; next } /^\[/ { on = 0 } on && $1 == k && $2 == "=" { print $3; exit }' \
        "$(omniwm_target)"
}
omniwm_set() { # <table> <key> <value>
    local target tmp
    target="$(omniwm_target)"
    tmp="$(dirname "$target")/.settings.toml.kadomo.$$"
    awk -v t="[$1]" -v k="$2" -v v="$3" '
        $0 == t { on = 1; print; next }
        /^\[/ { on = 0 }
        on && $1 == k && $2 == "=" { print k " = " v; next }
        { print }' "$target" >"$tmp"
    mv -f "$tmp" "$target"
}

brew="$(find_brew || true)"

# Stopped first, so nothing is removed while it runs. A bar you were already running stays up.
if [[ -n "$brew" ]] && { has_record service || recorded_line formula "$FORMULA"; } && pgrep -xq sketchybar 2>/dev/null; then
    echo "  ■  stopping SketchyBar"
    run "$brew" services stop sketchybar >/dev/null 2>&1 || true
    run pkill -f "sketchybar/plugins/omniwm_watch.sh" || true
    run pkill -f "omniwmctl watch active-workspace" || true
fi

# The menu bar.
if has_record hide-menu-bar; then
    echo "  ↩  the macOS menu bar (how it was before Kadomo)"
    before="$(recorded hide-menu-bar)"
    if [[ "$before" == absent ]]; then run defaults delete NSGlobalDomain _HIHideMenuBar 2>/dev/null || true
    else run defaults write NSGlobalDomain _HIHideMenuBar -int "$before"; fi
    run osascript -e "tell application \"System Events\" to set autohide menu bar of dock preferences to $(recorded autohide-menu-bar)" >/dev/null 2>&1 \
        || echo "  !  could not show the menu bar now; it comes back after you log out and back in" >&2
fi

# OmniWM's settings, unless you have changed them since.
if [[ -f "$(omniwm_target)" ]]; then
    # The gap the menu bar item raised comes down first, to the one recorded below.
    if [[ -f "$MENU_BAR_GAP" ]]; then
        read -r gap_before gap_raised <"$MENU_BAR_GAP"
        [[ "$(omniwm_get gaps.outer top)" != "$gap_raised" ]] || run omniwm_set gaps.outer top "$gap_before"
    fi
    if has_record omniwm-ipc && [[ "$(omniwm_get general ipcEnabled)" == true ]]; then
        echo "  ↩  OmniWM's IPC (off, as it was)"
        run omniwm_set general ipcEnabled "$(recorded omniwm-ipc)"
    fi
    if has_record omniwm-gap-top && [[ "$(omniwm_get gaps.outer top)" == "$HEIGHT.0" ]]; then
        echo "  ↩  OmniWM's top gap"
        run omniwm_set gaps.outer top "$(recorded omniwm-gap-top)"
    fi
fi

# The config.
label="${CONFIG/#$HOME/~}"
sha="$(recorded config-sha)"
backup="$(recorded config-backup)"
if [[ -d "$CONFIG" && ! -L "$CONFIG" ]]; then
    if [[ "$(tree_sha "$CONFIG")" == "$sha" ]]; then
        echo "  -  $label"
        run rm -rf -- "$CONFIG"
    else
        kept="$CONFIG.bak.$STAMP"
        echo "  ~  $label (edited since install; kept as $(basename "$kept"))"
        run mv "$CONFIG" "$kept"
    fi
fi
if [[ -n "$backup" && -e "$backup" ]]; then
    echo "  ↩  $label (restored from $(basename "$backup"))"
    run mv "$backup" "$CONFIG"
fi

# Your own bar, still running, reads the config it has again.
if ! recorded_line formula "$FORMULA" && ! has_record service && pgrep -xq sketchybar 2>/dev/null; then
    run sketchybar --reload >/dev/null 2>&1 || true
fi

# Kadomo Menu's entries.
if [[ -f "$MENU_FILE" ]]; then
    echo "  -  Kadomo Menu: Services > SketchyBar"
    run rm -f -- "$MENU_FILE"
fi

# The fonts Kadomo registered with macOS, while their files are still here.
while IFS='|' read -r kind path; do
    [[ "$kind" == font-file && -f "$path" ]] || continue
    if ((DRY_RUN)); then echo "    would run: unregister $path"
    else osascript -l JavaScript "$HERE/fonts.js" unregister "$path" >/dev/null 2>&1 || echo "  !  could not unregister $(basename "$path")" >&2; fi
done <"$MANIFEST"

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
    done <"$MANIFEST"
    tap="$(recorded tap)"
    if [[ -n "$tap" ]] && grep -qixF "$tap" <<<"$("$brew" tap)"; then
        echo "  -  tap $tap"
        # Refuses while other formulae from the tap are still installed; those keep it.
        run "$brew" untap "$tap" 2>/dev/null || echo "  =  tap $tap kept (other formulae still use it)"
    fi
elif grep -qE '^(formula|cask)\|' "$MANIFEST"; then
    echo "  !  Homebrew not found; left SketchyBar's packages installed" >&2
fi

run rm -f -- "$MANIFEST" "$MENU_BAR_GAP"
run rmdir "$STATE_DIR" 2>/dev/null || true
((DRY_RUN)) && echo "Dry run: nothing was changed."
exit 0
