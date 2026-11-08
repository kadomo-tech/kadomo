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

# One <key>|<value> line per fact: cask (Kadomo installed OmniWM with Homebrew).
# borders-before.toml is the border colors settings.toml had before Kadomo's
# theme first changed them; kadomo-omniwm restore-borders puts them back.
OMNIWM_STATE_DIR="${KADOMO_STATE_DIR:-$HOME/Library/Application Support/kadomo}"
OMNIWM_MANIFEST="$OMNIWM_STATE_DIR/omniwm-installed.txt"
OMNIWM_BORDERS_BEFORE="$OMNIWM_STATE_DIR/omniwm-borders-before.toml"
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
