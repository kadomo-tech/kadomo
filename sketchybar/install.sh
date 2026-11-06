#!/bin/bash
# Installs SketchyBar with the omarchy4mac bar, adapted for Kadomo, and starts it:
#   sketchybar, media-control, switchaudio-osx, bun   from Homebrew, unless already here
#   Hack Nerd Font, sketchybar-app-font               from Homebrew, unless already here
#   ~/.config/sketchybar                              the bar's config and plugins; a
#                                                     different folder there is backed up
# The bar replaces the macOS menu bar, so that is set to hide. OmniWM's IPC goes on
# (the workspace items need it) and its top gap makes room for the bar. Everything
# is recorded, and ./uninstall.sh puts it back.
#
# Usage: ./install.sh [--dry-run]
#
# Runs on the Bash 3.2 that ships with macOS.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKETCHYBAR_SOURCE="$HERE/config"
source "$HERE/sketchybar.sh"
STAMP="$(date +%Y%m%d-%H%M%S)"
DRY_RUN=0

case "${1:-}" in
    "") ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
esac

run() { if ((DRY_RUN)); then echo "    would run: $*"; else "$@"; fi; }
record() { ((DRY_RUN)) || sketchybar_record "$@"; }

((EUID != 0)) || { echo "  !  run this as your own user, not with sudo" >&2; exit 1; }
brew="$(find_brew)" || { echo "  !  SketchyBar needs Homebrew (https://brew.sh)" >&2; exit 1; }

# --- packages ------------------------------------------------------------------

if ! grep -qixF "$SKETCHYBAR_TAP" <<<"$("$brew" tap)"; then
    echo "  +  tap $SKETCHYBAR_TAP"
    run "$brew" tap "$SKETCHYBAR_TAP"
    record tap "$SKETCHYBAR_TAP"
fi
for formula in "${SKETCHYBAR_FORMULAE[@]}"; do
    if "$brew" list --formula "${formula##*/}" >/dev/null 2>&1; then
        echo "  =  ${formula##*/} (already installed)"
    else
        echo "  +  ${formula##*/} (brew install $formula)"
        run "$brew" install --formula "$formula"
        record formula "$formula"
    fi
done
for font in "${SKETCHYBAR_FONTS[@]}"; do
    IFS='|' read -r cask file files <<<"$font"
    if [[ -e "$HOME/Library/Fonts/$file" || -e "/Library/Fonts/$file" ]]; then
        echo "  =  $cask (already installed)"
    else
        echo "  +  $cask (brew install --cask $cask)"
        run "$brew" install --cask "$cask"
        record cask "$cask"
    fi
done

# A file in the Fonts folder is not always enough: macOS can leave it out of its
# list of fonts, and the bar then draws in a fallback font. Registered like Font
# Book does; a font macOS already knows is left alone.
register_font() {
    local result
    if result="$(osascript -l JavaScript "$HERE/fonts.js" register "$1" 2>/dev/null)"; then
        [[ "$result" != registered ]] || grep -qxF "font-file|$1" "$SKETCHYBAR_MANIFEST" 2>/dev/null || sketchybar_record font-file "$1"
    else
        echo "  !  could not register $(basename "$1"); open it in Font Book to install it" >&2
    fi
}
for font in "${SKETCHYBAR_FONTS[@]}"; do
    IFS='|' read -r cask file files <<<"$font"
    for dir in "$HOME/Library/Fonts" /Library/Fonts; do
        for path in "$dir"/$files; do
            [[ -f "$path" ]] || continue
            if ((DRY_RUN)); then echo "    would run: register_font $path"; else register_font "$path"; fi
        done
    done
done

# --- the config ----------------------------------------------------------------

label="${SKETCHYBAR_CONFIG/#$HOME/~}"
src_sha="$(sketchybar_tree_sha "$SKETCHYBAR_SOURCE")"
last_sha="$(sketchybar_recorded config-sha)"
dest_sha=""
if [[ -d "$SKETCHYBAR_CONFIG" && ! -L "$SKETCHYBAR_CONFIG" ]]; then dest_sha="$(sketchybar_tree_sha "$SKETCHYBAR_CONFIG")"; fi

if [[ "$dest_sha" == "$src_sha" ]]; then
    echo "  =  $label (unchanged)"
else
    if [[ -n "$dest_sha" && "$dest_sha" == "$last_sha" ]]; then
        # Kadomo's own older copy, untouched since: replace it, nothing to keep.
        echo "  ~  $label (updated)"
        run rm -rf -- "$SKETCHYBAR_CONFIG"
    elif [[ -e "$SKETCHYBAR_CONFIG" || -L "$SKETCHYBAR_CONFIG" ]]; then
        backup="$SKETCHYBAR_CONFIG.bak.$STAMP"
        echo "  ~  $label (backed up to $(basename "$backup"))"
        run mv "$SKETCHYBAR_CONFIG" "$backup"
        # Kept from the first install only: it is the folder that was there before Kadomo.
        sketchybar_has_record config-backup || record config-backup "$backup"
    else
        echo "  +  $label"
    fi
    run mkdir -p "$(dirname "$SKETCHYBAR_CONFIG")"
    run cp -R "$SKETCHYBAR_SOURCE" "$SKETCHYBAR_CONFIG"
fi
if ! ((DRY_RUN)); then
    sketchybar_forget config-sha
    sketchybar_record config-sha "$src_sha"
fi

# --- the menu bar --------------------------------------------------------------

# The bar sits where the menu bar is. The defaults key alone waits for a logout;
# System Events hides the menu bar now.
if ! ((DRY_RUN)) && ! sketchybar_has_record hide-menu-bar; then
    record hide-menu-bar "$(defaults read NSGlobalDomain _HIHideMenuBar 2>/dev/null || echo absent)"
    record autohide-menu-bar "$(osascript -e 'tell application "System Events" to get autohide menu bar of dock preferences' 2>/dev/null || echo false)"
fi
echo "  +  hiding the macOS menu bar (it shows when the pointer reaches the top of the screen)"
run defaults write NSGlobalDomain _HIHideMenuBar -bool true
hide_menu_bar_now() { osascript -e 'tell application "System Events" to set autohide menu bar of dock preferences to true' >/dev/null; }
run hide_menu_bar_now \
    || echo "  !  could not hide the menu bar now (allow System Events under Privacy & Security > Automation); it hides after you log out and back in" >&2

# --- OmniWM --------------------------------------------------------------------

if [[ -f "$(sketchybar_omniwm_target)" ]]; then
    ipc="$(sketchybar_omniwm_get general ipcEnabled)"
    if [[ "$ipc" == false ]]; then
        echo "  +  OmniWM: turning on its IPC, for the workspace items"
        sketchybar_has_record omniwm-ipc || record omniwm-ipc false
        run sketchybar_omniwm_set general ipcEnabled true
    fi
    gap="$(sketchybar_omniwm_get gaps.outer top)"
    if [[ -n "$gap" ]] && awk -v g="$gap" -v h="$SKETCHYBAR_HEIGHT" 'BEGIN { exit !(g < h) }'; then
        echo "  +  OmniWM: top gap $SKETCHYBAR_HEIGHT, so windows stay below the bar"
        sketchybar_has_record omniwm-gap-top || record omniwm-gap-top "$gap"
        run sketchybar_omniwm_set gaps.outer top "$SKETCHYBAR_HEIGHT.0"
    fi
fi

# --- start ---------------------------------------------------------------------

if ! pgrep -xq sketchybar 2>/dev/null && ! sketchybar_has_record service; then record service started; fi
echo "  ▶  starting SketchyBar"
run "$brew" services restart sketchybar || echo "  !  could not start SketchyBar: brew services restart sketchybar" >&2

((DRY_RUN)) && echo "Dry run: nothing was changed."
exit 0
