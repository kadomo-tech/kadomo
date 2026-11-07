# Shared by install.sh and uninstall.sh, and the top-level install.sh: what the
# bar needs from Homebrew, where its config goes, the record of what Kadomo
# changed, and the two OmniWM settings the bar depends on.

# find_brew, STATE_DIR.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/apps/apps.sh"

SKETCHYBAR_TAP="felixkratz/formulae"
SKETCHYBAR_FORMULA="$SKETCHYBAR_TAP/sketchybar"
# The headphones icon on the volume item.
SKETCHYBAR_FORMULAE=("$SKETCHYBAR_FORMULA" switchaudio-osx)
# One line per font: <cask>|<a file it installs>|<the files the bar's font family is in>.
SKETCHYBAR_FONTS=(
    "font-jetbrains-mono-nerd-font|JetBrainsMonoNerdFont-Regular.ttf|JetBrainsMonoNerdFont-*.ttf"
    "font-sketchybar-app-font|sketchybar-app-font.ttf|sketchybar-app-font.ttf"
)
SKETCHYBAR_CONFIG="$HOME/.config/sketchybar"
SKETCHYBAR_OMNIWM_SETTINGS="${XDG_CONFIG_HOME:-$HOME/.config}/omniwm/settings.toml"
SKETCHYBAR_MENU_FILE="${KADOMO_CONFIG:-$HOME/.config/kadomo}/menu/commands/sketchybar.toml"
# The bar's height in sketchybarrc: windows stay below it.
SKETCHYBAR_HEIGHT=32

# One <key>|<value> line per fact: tap, formula, cask (Kadomo installed it);
# service (Kadomo started the bar); config-sha (the copy Kadomo placed);
# config-backup (what was there before); font-file (a font Kadomo registered with
# macOS); hide-menu-bar, autohide-menu-bar, omniwm-ipc, omniwm-gap-top (each
# setting from before Kadomo changed it).
SKETCHYBAR_MANIFEST="$STATE_DIR/sketchybar-installed.txt"
# Written by plugins/menu_bar.sh while the menu bar shows: "<gap before> <gap now>".
SKETCHYBAR_MENU_BAR_GAP="$STATE_DIR/sketchybar-menu-bar-gap"

sketchybar_record() {
    mkdir -p "$STATE_DIR"
    printf '%s|%s\n' "$1" "$2" >>"$SKETCHYBAR_MANIFEST"
}
sketchybar_forget() {
    [[ -f "$SKETCHYBAR_MANIFEST" ]] || return 0
    awk -F'|' -v k="$1" '$1 != k' "$SKETCHYBAR_MANIFEST" >"$SKETCHYBAR_MANIFEST.tmp"
    mv "$SKETCHYBAR_MANIFEST.tmp" "$SKETCHYBAR_MANIFEST"
}
sketchybar_recorded() {
    [[ -f "$SKETCHYBAR_MANIFEST" ]] || return 0
    awk -F'|' -v k="$1" '$1 == k { print $2; exit }' "$SKETCHYBAR_MANIFEST"
}
sketchybar_has_record() { [[ -f "$SKETCHYBAR_MANIFEST" ]] && grep -q "^$1|" "$SKETCHYBAR_MANIFEST"; }

# A checksum of a folder's files and their names, to tell Kadomo's copy from one you edited.
sketchybar_tree_sha() {
    (cd "$1" && find . -type f ! -name .DS_Store -exec shasum -a 256 {} + | LC_ALL=C sort | shasum -a 256 | cut -d' ' -f1)
}

# Whether everything install.sh puts in place is there and current.
sketchybar_up_to_date() {
    [[ -n "${SKETCHYBAR_SOURCE:-}" && -d "$SKETCHYBAR_CONFIG" && -s "$SKETCHYBAR_MANIFEST" && -f "$SKETCHYBAR_MENU_FILE" ]] || return 1
    command -v sketchybar >/dev/null 2>&1 || [[ -x /opt/homebrew/bin/sketchybar || -x /usr/local/bin/sketchybar ]] || return 1
    [[ "$(sketchybar_tree_sha "$SKETCHYBAR_CONFIG")" == "$(sketchybar_tree_sha "$SKETCHYBAR_SOURCE")" ]]
}

# Kadomo Menu › Services › SketchyBar. Homebrew's service is what starts the bar at
# login, so these go through it: a bar killed any other way comes straight back.
# And Services › Menu Bar, which does what the bar's menu bar item does, with a
# key for it.
sketchybar_write_menu() { # <brew>
    local verb title note sym n=1
    mkdir -p "$(dirname "$SKETCHYBAR_MENU_FILE")"
    {
        printf '# Written by sketchybar/install.sh; changes here are replaced.\n\n'
        printf '[[category]]\nid = "services/sketchybar"\ntitle = "SketchyBar"\nsubtitle = "The status bar, in the theme'\''s colors"\n'
        printf 'icon = "menubar.rectangle"\norder = 1\nkeywords = ["sketchybar", "status bar", "bar"]\n\n'
        while IFS='|' read -r verb title note sym; do
            printf '[[command]]\nid = "kadomo-sketchybar-%s"\ntitle = "%s"\nsubtitle = "%s"\n' "$verb" "$title" "$note"
            printf 'category = "services/sketchybar"\nicon = "%s"\norder = %s\nkeywords = ["sketchybar", "status bar", "bar"]\n' "$sym" "$n"
            printf 'exec = "%s"\nargs = ["services", "%s", "sketchybar"]\n\n' "$1" "$verb"
            n=$((n + 1))
        done <<EOF
start|Start|Start the bar, and at every login|play
stop|Stop|Quit the bar; it stays off at login until you start it|stop
restart|Restart|Start the bar again|arrow.clockwise
EOF
        printf '[[category]]\nid = "services/menu-bar"\ntitle = "Menu Bar"\nsubtitle = "The macOS menu bar, with the app menus"\n'
        printf 'icon = "menubar.arrow.down.rectangle"\norder = 2\nkeywords = ["menu bar", "menubar", "macos", "app menus"]\n\n'
        while IFS='|' read -r verb title note sym; do
            printf '[[command]]\nid = "kadomo-menu-bar-%s"\ntitle = "%s"\nsubtitle = "%s"\n' "$verb" "$title" "$note"
            printf 'category = "services/menu-bar"\nicon = "%s"\norder = %s\nkeywords = ["menu bar", "menubar", "macos", "app menus"]\n' "$sym" "$n"
            [[ "$verb" != toggle ]] || printf 'hotkey = "option+shift+m"\n'
            printf 'exec = "%s"\nargs = ["%s"]\n\n' "$SKETCHYBAR_CONFIG/plugins/menu_bar.sh" "$verb"
            n=$((n + 1))
        done <<EOF
toggle|Show or Hide|Flip the menu bar, with the bar and windows|menubar.arrow.up.rectangle
show|Show|Show the menu bar, and move the bar and windows below it|eye
hide|Hide|Hide the menu bar, and put the bar and windows back|eye.slash
EOF
        printf '[[keybind]]\nheading = "Menu bar"\norder = 60\n\n'
        printf '[[keybind]]\nkey = "OPT SHIFT + M"\ntitle = "Show or hide the macOS menu bar"\norder = 61\n'
    } >"$SKETCHYBAR_MENU_FILE.tmp.$$"
    mv -f "$SKETCHYBAR_MENU_FILE.tmp.$$" "$SKETCHYBAR_MENU_FILE"
}

# --- OmniWM's settings.toml ----------------------------------------------------

# settings.toml itself, following a link to where it really is.
sketchybar_omniwm_target() {
    local path="$SKETCHYBAR_OMNIWM_SETTINGS" link
    while [[ -L "$path" ]]; do
        link="$(readlink "$path")"
        case "$link" in /*) path="$link" ;; *) path="$(dirname "$path")/$link" ;; esac
    done
    printf '%s' "$path"
}

sketchybar_omniwm_get() { # <table> <key>
    awk -v t="[$1]" -v k="$2" '$0 == t { on = 1; next } /^\[/ { on = 0 } on && $1 == k && $2 == "=" { print $3; exit }' \
        "$(sketchybar_omniwm_target)"
}

# Changes one value, written atomically; OmniWM sees the new file and reloads it.
# A key that is not there is left out: the file stays as it was.
sketchybar_omniwm_set() { # <table> <key> <value>
    local target tmp
    target="$(sketchybar_omniwm_target)"
    tmp="$(dirname "$target")/.settings.toml.kadomo.$$"
    awk -v t="[$1]" -v k="$2" -v v="$3" '
        $0 == t { on = 1; print; next }
        /^\[/ { on = 0 }
        on && $1 == k && $2 == "=" { print k " = " v; next }
        { print }' "$target" >"$tmp"
    mv -f "$tmp" "$target"
}
