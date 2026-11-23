# Shared by install.sh and uninstall.sh, and the top-level install.sh: where
# OmniWM and Kadomo's pieces for it live, the record of what Kadomo installed,
# and whether this Mac can run it.

OMNIWM_APP_NAME="OmniWM.app"
OMNIWM_ID="com.barut.OmniWM"
OMNIWM_CASK="omniwm"
# OmniWM 0.8 and later draw their own menu bar, which is why Kadomo no longer
# installs SketchyBar (remove-sketchybar.sh removes what an older Kadomo did).
OMNIWM_MIN_VERSION="0.8"
OMNIWM_BIN="$HOME/.local/bin/kadomo-omniwm"
# The login agent older Kadomo installs used to start OmniWM (kadomo-omniwm login).
# OmniWM now starts at login by its own setting; install.sh and uninstall.sh remove this.
OMNIWM_AGENT_LABEL="tech.kadomo.omniwm-login"
OMNIWM_AGENT_PLIST="$HOME/Library/LaunchAgents/$OMNIWM_AGENT_LABEL.plist"
OMNIWM_MENU_FILE="${KADOMO_CONFIG:-$HOME/.config/kadomo}/menu/commands/omniwm.toml"
OMNIWM_SETTINGS="${XDG_CONFIG_HOME:-$HOME/.config}/omniwm/settings.toml"

# Kadomo's widgets for OmniWM's menu bar, each in the shell's top-level widgets
# folder, where OmniWM uses it over its own widget of the same name: apple-menu
# (the Omarchy logo in place of the Apple logo) and volume (the speaker icon
# without the percentage). A widget's first line marks it as Kadomo's, so a
# widget of yours by that name is never replaced or removed.
OMNIWM_WIDGETS_SOURCE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/shell"
OMNIWM_WIDGETS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/omniwm/shell/widgets"
OMNIWM_LOGO_SOURCE="$OMNIWM_WIDGETS_SOURCE/apple-menu/init.luau"
OMNIWM_LOGO_WIDGET="$OMNIWM_WIDGETS_DIR/apple-menu/init.luau"
OMNIWM_VOLUME_WIDGET="$OMNIWM_WIDGETS_DIR/volume/init.luau"

# One <key>|<value> line per fact: cask (Kadomo installed OmniWM with Homebrew).
# borders-before.toml is the border colors settings.toml had before Kadomo's
# theme first changed them, and text-before.toml the workspace bar's text color
# (empty when there was none); kadomo-omniwm restore-borders puts them back.
OMNIWM_STATE_DIR="${KADOMO_STATE_DIR:-$HOME/Library/Application Support/kadomo}"
OMNIWM_MANIFEST="$OMNIWM_STATE_DIR/omniwm-installed.txt"
OMNIWM_BORDERS_BEFORE="$OMNIWM_STATE_DIR/omniwm-borders-before.toml"
OMNIWM_TEXT_BEFORE="$OMNIWM_STATE_DIR/omniwm-text-before.toml"
# The next / previous workspace keys Kadomo set; kadomo-omniwm restore-workspace-keys takes them off.
OMNIWM_WORKSPACE_KEYS="$OMNIWM_STATE_DIR/omniwm-workspace-keys.txt"

# OmniWM runs on Apple silicon with macOS 26 or later.
omniwm_supported() {
    local major
    [[ "$(uname -m)" == arm64 ]] || return 1
    major="$(sw_vers -productVersion 2>/dev/null)"; major="${major%%.*}"
    [[ "$major" =~ ^[0-9]+$ ]] && ((major >= 26))
}
omniwm_requirement() { printf 'needs macOS 26 or later on Apple silicon'; }

# Where OmniWM.app is installed, or nothing.
omniwm_app() {
    local dir
    for dir in /Applications "$HOME/Applications"; do
        [[ -d "$dir/$OMNIWM_APP_NAME" ]] && { printf '%s' "$dir/$OMNIWM_APP_NAME"; return 0; }
    done
    return 1
}

# The installed OmniWM's own version (CFBundleShortVersionString), or nothing.
omniwm_app_version() {
    local app
    app="$(omniwm_app)" || return 1
    /usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$app/Contents/Info.plist" 2>/dev/null
}

# Whether dotted, numeric version $1 is $2 or later.
omniwm_version_at_least() {
    local IFS=.
    local a=($1) b=($2) i n
    n=${#a[@]}; ((${#b[@]} <= n)) || n=${#b[@]}
    for ((i=0; i<n; i++)); do
        ((10#${a[i]:-0} == 10#${b[i]:-0})) || { ((10#${a[i]:-0} > 10#${b[i]:-0})); return; }
    done
    return 0
}

# Whether the installed OmniWM is $OMNIWM_MIN_VERSION or later, which Kadomo
# needs for its own menu bar.
omniwm_version_ok() {
    local v
    v="$(omniwm_app_version)" && [[ -n "$v" ]] && omniwm_version_at_least "$v" "$OMNIWM_MIN_VERSION"
}

# Whether everything install.sh puts in place is there and current.
omniwm_up_to_date() {
    [[ -n "${OMNIWM_SOURCE_BIN:-}" ]] || return 1
    omniwm_app >/dev/null && omniwm_version_ok && cmp -s "$OMNIWM_SOURCE_BIN/kadomo-omniwm" "$OMNIWM_BIN" \
        && [[ -f "$OMNIWM_MENU_FILE" && ! -e "$OMNIWM_AGENT_PLIST" ]]
}

# Whether widget $1 there is Kadomo's, and whether it is the current one.
omniwm_widget_ours() {
    local file="$OMNIWM_WIDGETS_DIR/$1/init.luau"
    [[ -f "$file" ]] && head -n 1 "$file" | grep -q '^-- Kadomo:'
}
omniwm_widget_up_to_date() { cmp -s "$OMNIWM_WIDGETS_SOURCE/$1/init.luau" "$OMNIWM_WIDGETS_DIR/$1/init.luau"; }
# Whether a widget of yours named $1 is there, which Kadomo leaves alone.
omniwm_widget_yours() { [[ -e "$OMNIWM_WIDGETS_DIR/$1/init.luau" ]] && ! omniwm_widget_ours "$1"; }

# Puts Kadomo's widget $1 in place; OmniWM picks it up by itself. Returns 1,
# and changes nothing, when a widget of yours by that name is there.
omniwm_widget_install() {
    local file="$OMNIWM_WIDGETS_DIR/$1/init.luau"
    if omniwm_widget_yours "$1"; then return 1; fi
    mkdir -p "$(dirname "$file")"
    cp "$OMNIWM_WIDGETS_SOURCE/$1/init.luau" "$file.tmp"
    mv "$file.tmp" "$file"
}
# Takes Kadomo's widget $1 away, so OmniWM's own is back; one of yours stays.
omniwm_widget_remove() {
    local file="$OMNIWM_WIDGETS_DIR/$1/init.luau"
    omniwm_widget_ours "$1" || return 0
    rm -f -- "$file"
    rmdir "$(dirname "$file")" 2>/dev/null || true
}

# The Omarchy logo, Kadomo's apple-menu widget.
omniwm_logo_ours() { omniwm_widget_ours apple-menu; }
omniwm_logo_up_to_date() { omniwm_widget_up_to_date apple-menu; }
omniwm_logo_install() { omniwm_widget_install apple-menu; }
omniwm_logo_remove() { omniwm_widget_remove apple-menu; }

omniwm_record() {
    mkdir -p "$OMNIWM_STATE_DIR"
    omniwm_forget "$1"
    printf '%s|%s\n' "$1" "$2" >>"$OMNIWM_MANIFEST"
}
omniwm_forget() {
    [[ -f "$OMNIWM_MANIFEST" ]] || return 0
    awk -F'|' -v k="$1" '$1 != k' "$OMNIWM_MANIFEST" >"$OMNIWM_MANIFEST.tmp"
    mv "$OMNIWM_MANIFEST.tmp" "$OMNIWM_MANIFEST"
}
omniwm_recorded() {
    [[ -f "$OMNIWM_MANIFEST" ]] || return 0
    awk -F'|' -v k="$1" '$1 == k { print $2; exit }' "$OMNIWM_MANIFEST"
}

# Whether an older Kadomo left anything for AeroSpace on this Mac: its build,
# commands, login agents, menu entries, saved choices, or (in the dotfiles'
# records) AeroSpace's config and JankyBorders. remove-aerospace.sh and
# dotfiles/uninstall.sh --retired remove them.
aerospace_leftovers() {
    local state="${KADOMO_STATE_DIR:-$HOME/Library/Application Support/kadomo}" path
    for path in "/Applications/AeroSpace Kadomo.app" "$HOME/.local/bin/kadomo-aerospace" \
        "$HOME/.local/bin/kadomo-workspace-layout" "$HOME/Library/LaunchAgents/tech.kadomo.aerospace-login.plist" \
        "$HOME/Library/LaunchAgents/tech.kadomo.aerospace-scrolling.plist" \
        "${KADOMO_CONFIG:-$HOME/.config/kadomo}/menu/commands/aerospace.toml" \
        "${XDG_STATE_HOME:-$HOME/.local/state}/kadomo/window-manager" \
        "${XDG_STATE_HOME:-$HOME/.local/state}/kadomo/aerospace-build" \
        "$state/aerospace-installed.txt" "$state/packages-installed.txt"; do
        [[ -e "$path" ]] && return 0
    done
    [[ -f "$state/dotfiles-installed.txt" ]] && grep -qE '/\.config/(aerospace|borders)/' "$state/dotfiles-installed.txt"
}

# Whether an older Kadomo left anything for SketchyBar on this Mac: it no
# longer ships it, OmniWM's own menu bar does its job. remove-sketchybar.sh
# removes what install.sh put there.
sketchybar_leftovers() {
    local state="${KADOMO_STATE_DIR:-$HOME/Library/Application Support/kadomo}"
    [[ -s "$state/sketchybar-installed.txt" ]]
}
