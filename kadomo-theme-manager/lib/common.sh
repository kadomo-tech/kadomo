# Shared by every theme-* command: where things live, theme names, the lock,
# and small helpers. Sourced, never run. Plain Bash 3.2, BSD tools.

# The theme manager's own files, one level above this lib/: bin/, lib/,
# themed/ (built-in templates) and themes/ (built-in themes). Installed in
# ~/.local/share/kadomo/theme-manager, with the commands linked from ~/.local/bin.
KADOMO_THEME_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$KADOMO_THEME_ROOT/lib"
BUILTIN_THEMES="$KADOMO_THEME_ROOT/themes"
BUILTIN_TEMPLATES="$KADOMO_THEME_ROOT/themed"

# Kadomo Menu reads ~/.config/kadomo/current/theme/kadomo-menu.toml, so the
# current theme lives in ~/.config/kadomo rather than ~/.local/state.
KADOMO_CONFIG="${KADOMO_CONFIG_DIR:-$HOME/.config/kadomo}"
USER_THEMES="$KADOMO_CONFIG/themes"
USER_TEMPLATES="$KADOMO_CONFIG/themed"
USER_BACKGROUNDS="$KADOMO_CONFIG/backgrounds"
HOOKS_DIR="$KADOMO_CONFIG/hooks/theme-set.d"
SETTINGS="$KADOMO_CONFIG/theme.conf"
CURRENT="$KADOMO_CONFIG/current"
THEME_DIR="$CURRENT/theme"
NEXT_DIR="$CURRENT/next-theme"
OLD_DIR="$CURRENT/old-theme"
NAME_FILE="$CURRENT/theme.name"
# When the current theme is someone else's folder (theme-set --external, used
# by Kadomo Menu for Omarchy themes): "<name>\t<label>\t<folder>".
EXTERNAL_FILE="$CURRENT/theme.external"
# The last of Kadomo's own themes applied, for theme-set --native.
NATIVE_FILE="$CURRENT/native.name"
BG_LINK="$CURRENT/background"
MENU_COMMANDS="$KADOMO_CONFIG/menu/commands/themes.toml"

STATE="${KADOMO_THEME_STATE_DIR:-$HOME/.local/state/kadomo}"
CACHE="${KADOMO_THEME_CACHE_DIR:-$HOME/.cache/kadomo}"
PREVIEWS="$CACHE/theme-selector/previews"

# Every app the installer can wire. theme.conf's apps line picks the ones that
# follow the theme; KADOMO_THEME_APPS overrides it (tests set it to none).
ALL_APPS="ghostty btop omniwm kadomo-menu neovim vim vscode starship appearance wallpaper"

IMAGE_EXTENSIONS="jpg jpeg png webp heic gif tif tiff bmp"

# Kadomo Menu starts commands with a short PATH; Homebrew's tools (btop) are
# looked for there too.
PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"

# Messages can quote theme file names and values, so control characters
# (terminal escape sequences start with one) become ?. Newlines stay.
printable() { LC_ALL=C tr '\000-\011\013-\037\177' '?'; }
warn() { printf '%s\n' "$*" | printable >&2; }
die() { printf '%s\n' "$*" | printable >&2; exit 1; }

# The apps that follow the theme. borders (JankyBorders, which only AeroSpace
# used), terminal (Terminal.app, which Kadomo leaves alone now), sketchybar
# (OmniWM's own menu bar replaces it), and kitty (no longer installed) are no
# longer ones; an older theme.conf that lists them is read without them.
enabled_apps() {
    local apps
    if [[ -n "${KADOMO_THEME_APPS+set}" ]]; then
        apps="$KADOMO_THEME_APPS"
    elif [[ -f "$SETTINGS" ]]; then
        apps="$(sed -n 's/^[[:space:]]*apps[[:space:]]*=[[:space:]]*//p' "$SETTINGS" | tail -n 1)"
    else
        apps="$ALL_APPS"
    fi
    apps=" $apps "
    apps="${apps// borders / }"
    apps="${apps// terminal / }"
    apps="${apps// sketchybar / }"
    apps="${apps// kitty / }"
    apps="${apps# }"
    printf '%s' "${apps% }"
}
app_enabled() { [[ " $(enabled_apps) " == *" $1 "* ]]; }

# "rose-pine" -> "Rose Pine". A word with a digit in it (tmac2k) is kept as is.
display_name() {
    local word out=""
    for word in ${1//-/ }; do
        case "$word" in
            *[0-9]*) ;;
            *) word="$(printf '%s' "${word:0:1}" | tr '[:lower:]' '[:upper:]')${word:1}" ;;
        esac
        out="$out $word"
    done
    printf '%s' "${out# }"
}

# "Rose Pine" or "<b>Rose Pine</b>" -> "rose-pine". Prints nothing for a
# name that cannot be a theme: empty, starting with a dot, or with a slash.
normalize_name() {
    local name
    name="$(printf '%s' "$1" | sed -e 's/<[^>]*>//g' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
        | tr '[:upper:]' '[:lower:]' | tr -s '[:space:]' '-')"
    case "$name" in ""|.*|*/*) return 1 ;; esac
    printf '%s' "$name"
}

builtin_theme_dir() { [[ -d "$BUILTIN_THEMES/$1" ]] && printf '%s' "$BUILTIN_THEMES/$1"; }
user_theme_dir() { [[ -d "$USER_THEMES/$1" ]] && printf '%s' "$USER_THEMES/$1"; }
# Names read back from state files (native.name, settings.conf) get here without
# normalize_name, so this refuses a name that would leave the themes folders.
theme_exists() {
    case "$1" in ""|.*|*/*) return 1 ;; esac
    [[ -d "$BUILTIN_THEMES/$1" || -d "$USER_THEMES/$1" ]]
}

# Only bundled themes and folders explicitly trusted by the user may supply
# executable configuration. Git metadata (including its absence) proves no trust.
# trusted-themes contains one absolute theme folder path per line.
theme_untrusted() {
    case "$1" in */../*|*/..) return 0 ;; esac
    case "$1" in "$BUILTIN_THEMES"/*) return 1 ;; esac
    [[ -f "$KADOMO_CONFIG/trusted-themes" ]] && grep -Fxq -- "$1" "$KADOMO_CONFIG/trusted-themes" && return 1
    return 0
}

# Takes a theme folder off trusted-themes, so another folder that later gets
# its name is not trusted by accident. Written in place, so a link stays one.
theme_forget_trust() {
    local file="$KADOMO_CONFIG/trusted-themes" tmp
    [[ -f "$file" ]] && grep -Fxq -- "$1" "$file" || return 0
    tmp="$file.tmp.$$"
    grep -Fxv -- "$1" "$file" >"$tmp" || true
    cat "$tmp" >"$file"
    rm -f -- "$tmp"
}

# Every theme name, built-in and user, sorted and de-duplicated.
theme_names() {
    local dir
    for dir in "$BUILTIN_THEMES"/*/ "$USER_THEMES"/*/; do
        [[ -d "$dir" ]] || continue
        dir="${dir%/}"
        printf '%s\n' "${dir##*/}"
    done | LC_ALL=C sort -u
}

current_name() { [[ -s "$NAME_FILE" ]] && head -n 1 "$NAME_FILE"; }

# Field $2 (1 name, 2 label, 3 folder) of the current external theme, when
# the current theme is external and named $1.
external_field() {
    [[ -s "$EXTERNAL_FILE" ]] || return 1
    local name label folder
    IFS=$'\t' read -r name label folder <"$EXTERNAL_FILE" || [[ -n "$name" ]] || return 1
    [[ -n "$name" && "$name" == "$1" ]] || return 1
    case "$2" in 1) printf '%s' "$name" ;; 2) printf '%s' "$label" ;; 3) printf '%s' "$folder" ;; esac
}
external_theme_dir() { local dir; dir="$(external_field "$1" 3)" && [[ -d "$dir" ]] && printf '%s' "$dir"; }
current_is_external() { local name; name="$(current_name)" && external_field "$name" 1 >/dev/null; }

# A theme's name for people: an external theme's label, else from its folder name.
theme_label() { external_field "$1" 2 2>/dev/null || display_name "$1"; }

is_image() {
    local ext
    ext="$(printf '%s' "${1##*.}" | tr '[:upper:]' '[:lower:]')"
    [[ " $IMAGE_EXTENSIONS " == *" $ext "* ]]
}

# Images directly in each folder given, one path per line, sorted by file name
# so numeric prefixes (0-road.jpg, 1-sea.jpg) set the order. Symlinks and names
# with a newline are left out.
images_in() {
    local dir file
    for dir in "$@"; do
        [[ -d "$dir" ]] || continue
        for file in "$dir"/*; do
            [[ -f "$file" && ! -L "$file" ]] || continue
            [[ "$file" != *$'\n'* ]] || continue
            is_image "$file" && printf '%s\t%s\n' "${file##*/}" "$file"
        done
    done | LC_ALL=C sort -t $'\t' -k1,1 -k2,2 | cut -f2
}

# The wallpapers of a theme: its own backgrounds/ and your folder for it. A
# built-in image is used where it is installed, a user image where you keep
# it, so macOS always gets a path that stays put.
theme_backgrounds() {
    local name="$1" list="" file base dir
    # An external theme's wallpapers are used where its provider keeps them.
    if dir="$(external_theme_dir "$name")"; then
        { images_in "$dir/backgrounds"; images_in "$USER_BACKGROUNDS/$name"; } | while IFS= read -r file; do printf '%s\t%s\n' "${file##*/}" "$file"; done \
            | LC_ALL=C sort -t $'\t' -k1,1 -k2,2 | cut -f2
        return 0
    fi
    if [[ -d "$USER_THEMES/$name/backgrounds" ]]; then
        list="$(images_in "$USER_THEMES/$name/backgrounds")"
    fi
    if [[ -d "$BUILTIN_THEMES/$name/backgrounds" ]]; then
        # A user image with the same file name overlays the built-in one.
        while IFS= read -r file; do
            [[ -n "$file" ]] || continue
            base="${file##*/}"
            [[ -f "$USER_THEMES/$name/backgrounds/$base" && ! -L "$USER_THEMES/$name/backgrounds/$base" ]] && continue
            list="$list"$'\n'"$file"
        done < <(images_in "$BUILTIN_THEMES/$name/backgrounds")
    fi
    list="$list"$'\n'"$(images_in "$USER_BACKGROUNDS/$name")"
    printf '%s\n' "$list" | awk 'NF' | while IFS= read -r file; do printf '%s\t%s\n' "${file##*/}" "$file"; done \
        | LC_ALL=C sort -t $'\t' -k1,1 -k2,2 | cut -f2
}

# --- locking -------------------------------------------------------------
# One theme change at a time. shlock writes our pid into the lock file and
# takes over a lock whose process has died, so a crash never wedges it.

LOCK_FILE="$STATE/theme.lock"
LOCK_HELD=""

lock_acquire() {
    local file="${1:-$LOCK_FILE}" i=0
    mkdir -p "$(dirname "$file")"
    until /usr/bin/shlock -f "$file" -p $$ 2>/dev/null; do
        i=$((i + 1))
        # About 60 s: something is badly stuck, so say so rather than hang forever.
        ((i < 1200)) || die "theme: gave up waiting for $file (held by pid $(cat "$file" 2>/dev/null))"
        sleep 0.05
    done
    LOCK_HELD="$LOCK_HELD $file"
}

lock_release() {
    local file="${1:-$LOCK_FILE}"
    [[ "$(cat "$file" 2>/dev/null)" == "$$" ]] && rm -f -- "$file"
    LOCK_HELD="${LOCK_HELD/ $file/}"
}

lock_release_all() {
    local file
    for file in $LOCK_HELD; do lock_release "$file"; done
}

# --- palette ---------------------------------------------------------------

# Resolves a colors.toml into "key<TAB>value" lines (see lib/palette.awk).
resolve_palette() { awk -f "$LIB/palette.awk" "$1"; }

# Writes colors.toml into a theme folder from its alacritty.toml.
import_alacritty() { awk -f "$LIB/alacritty.awk" "$1/alacritty.toml" >"$1/colors.toml"; }

# Runs a command with a time limit, so one stuck app never holds up the rest.
with_timeout() {
    local seconds="$1" pid watcher status
    shift
    "$@" &
    pid=$!
    # Detached from our output, so a caller reading it is not kept waiting.
    ( sleep "$seconds"; kill -TERM "$pid" 2>/dev/null ) </dev/null >/dev/null 2>&1 &
    watcher=$!
    wait "$pid"; status=$?
    kill "$watcher" 2>/dev/null; wait "$watcher" 2>/dev/null
    return "$status"
}
