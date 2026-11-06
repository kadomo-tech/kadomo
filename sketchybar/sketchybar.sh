# Shared by install.sh and uninstall.sh, and the top-level install.sh: what the
# bar needs from Homebrew, where its config goes, the record of what Kadomo
# changed, and the two OmniWM settings the bar depends on.

# find_brew, STATE_DIR.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/apps/apps.sh"

SKETCHYBAR_TAP="felixkratz/formulae"
SKETCHYBAR_FORMULA="$SKETCHYBAR_TAP/sketchybar"
# The music item, the headphones icon on the volume item, and the agents item.
SKETCHYBAR_FORMULAE=("$SKETCHYBAR_FORMULA" media-control switchaudio-osx bun)
# One line per font: <cask>|<a file it installs>|<the files the bar's font family is in>.
SKETCHYBAR_FONTS=(
    "font-hack-nerd-font|HackNerdFont-Regular.ttf|HackNerdFont-*.ttf"
    "font-sketchybar-app-font|sketchybar-app-font.ttf|sketchybar-app-font.ttf"
)
SKETCHYBAR_CONFIG="$HOME/.config/sketchybar"
SKETCHYBAR_OMNIWM_SETTINGS="${XDG_CONFIG_HOME:-$HOME/.config}/omniwm/settings.toml"
# The bar's height in sketchybarrc: windows stay below it.
SKETCHYBAR_HEIGHT=32

# One <key>|<value> line per fact: tap, formula, cask (Kadomo installed it);
# service (Kadomo started the bar); config-sha (the copy Kadomo placed);
# config-backup (what was there before); font-file (a font Kadomo registered with
# macOS); hide-menu-bar, autohide-menu-bar, omniwm-ipc, omniwm-gap-top (each
# setting from before Kadomo changed it).
SKETCHYBAR_MANIFEST="$STATE_DIR/sketchybar-installed.txt"

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
    [[ -n "${SKETCHYBAR_SOURCE:-}" && -d "$SKETCHYBAR_CONFIG" && -s "$SKETCHYBAR_MANIFEST" ]] || return 1
    command -v sketchybar >/dev/null 2>&1 || [[ -x /opt/homebrew/bin/sketchybar || -x /usr/local/bin/sketchybar ]] || return 1
    [[ "$(sketchybar_tree_sha "$SKETCHYBAR_CONFIG")" == "$(sketchybar_tree_sha "$SKETCHYBAR_SOURCE")" ]]
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
