# Shared by install.sh and uninstall.sh, and the top-level install.sh: which
# apps Kadomo installs, how to tell one is already there, and the record of
# what Kadomo installed.

# One app per line: <key>|<cask or formula>|<Homebrew name>|<what tells it is
# installed: an app bundle for a cask, a command for a formula>.
# The key is what --only takes.
APPS=(
    "ghostty|cask|ghostty|Ghostty.app"
    "moonlight|cask|moonlight|Moonlight.app"
    "neovim|formula|neovim|nvim"
    "btop|formula|btop|btop"
    "htop|formula|htop|htop"
    "firefox|cask|firefox|Firefox.app"
)

# Apps this checkout no longer installs, but an older Kadomo might have: same
# shape as APPS, so app_entry and app_path can still find and quit them.
# uninstall.sh --retired removes them from the manifest; install.sh runs it.
RETIRED=(
    "kitty|cask|kitty|kitty.app"
)

# Whether <kind> <name> is one of the apps this checkout still installs (not
# merely RETIRED). A manifest line that fails this is retired.
in_apps() {
    local entry
    for entry in "${APPS[@]}"; do
        [[ "$(app_field "$entry" 2)|$(app_field "$entry" 3)" == "$1|$2" ]] && return 0
    done
    return 1
}

# Where macOS apps live. KADOMO_APP_DIRS (colon-separated) overrides it for testing.
if [[ -n "${KADOMO_APP_DIRS:-}" ]]; then
    IFS=: read -r -a APP_DIRS <<<"$KADOMO_APP_DIRS"
else
    APP_DIRS=(/Applications "$HOME/Applications")
fi

# One line per app Kadomo installed: <cask or formula>|<Homebrew name>.
STATE_DIR="${KADOMO_STATE_DIR:-$HOME/Library/Application Support/kadomo}"
APPS_MANIFEST="$STATE_DIR/apps-installed.txt"

# Whether an older Kadomo left anything for kitty on this Mac: the app from
# Homebrew, or its config (dotfiles' own manifest). apps/uninstall.sh --retired
# and dotfiles/uninstall.sh --retired remove them. The top-level install.sh runs both.
kitty_leftovers() {
    local dotfiles_manifest="$STATE_DIR/dotfiles-installed.txt"
    { [[ -f "$APPS_MANIFEST" ]] && grep -qxF "cask|kitty" "$APPS_MANIFEST"; } ||
        { [[ -f "$dotfiles_manifest" ]] && grep -q '/\.config/kitty/' "$dotfiles_manifest"; }
}

app_field() { # <entry> <1-4>
    printf '%s' "$1" | cut -d'|' -f"$2"
}

app_keys() {
    local entry keys=""
    for entry in "${APPS[@]}"; do keys="$keys,${entry%%|*}"; done
    printf '%s' "${keys#,}"
}

app_entry() { # <key>, or <kind> <name>
    local entry
    for entry in "${APPS[@]}"; do
        if [[ $# -eq 1 && "${entry%%|*}" == "$1" ]] ||
           [[ $# -eq 2 && "$(app_field "$entry" 2)|$(app_field "$entry" 3)" == "$1|$2" ]]; then
            printf '%s' "$entry"; return 0
        fi
    done
    # A key names only a current app; a retired one is found by kind+name only,
    # so a manifest entry for it can still be resolved to an app bundle.
    if [[ $# -eq 2 ]]; then
        for entry in "${RETIRED[@]}"; do
            [[ "$(app_field "$entry" 2)|$(app_field "$entry" 3)" == "$1|$2" ]] && { printf '%s' "$entry"; return 0; }
        done
    fi
    return 1
}

# Where an app bundle is installed, or nothing.
app_path() {
    local dir
    for dir in ${APP_DIRS[@]+"${APP_DIRS[@]}"}; do
        [[ -d "$dir/$1" ]] && { printf '%s' "$dir/$1"; return 0; }
    done
    return 1
}

# Whether an app is on this Mac however it got there, without asking Homebrew
# (quick enough for the checklist).
app_present() {
    local entry="$1" check
    check="$(app_field "$entry" 4)"
    if [[ "$(app_field "$entry" 2)" == cask ]]; then app_path "$check" >/dev/null
    else command -v "$check" >/dev/null 2>&1; fi
}

# Homebrew, even when this shell's PATH lacks it: PATH, HOMEBREW_PREFIX, then
# the Apple silicon and Intel locations. KADOMO_BREW replaces the search
# (empty: no Homebrew), for tests.
find_brew() {
    local path
    if [[ -n "${KADOMO_BREW+set}" ]]; then
        [[ -n "$KADOMO_BREW" && -x "$KADOMO_BREW" ]] && { printf '%s' "$KADOMO_BREW"; return 0; }
        return 1
    fi
    for path in "$(command -v brew 2>/dev/null)" "${HOMEBREW_PREFIX:+$HOMEBREW_PREFIX/bin/brew}" /opt/homebrew/bin/brew /usr/local/bin/brew; do
        [[ -n "$path" && -x "$path" ]] && { printf '%s' "$path"; return 0; }
    done
    return 1
}

# --- stopping apps before they are removed -----------------------------------

# The bundle id of the app this script runs inside (the terminal it was started
# from), or nothing: macOS hands it down as __CFBundleIdentifier, and the
# process tree says it too.
host_bundle_id() {
    local pid=$$ comm next
    if [[ -n "${__CFBundleIdentifier:-}" ]]; then printf '%s' "$__CFBundleIdentifier"; return 0; fi
    while [[ "$pid" =~ ^[0-9]+$ ]] && ((pid > 1)); do
        comm="$(ps -o comm= -p "$pid" 2>/dev/null)" || return 1
        if [[ "$comm" == *.app/Contents/MacOS/* ]]; then
            defaults read "${comm%%.app/Contents/MacOS/*}.app/Contents/Info.plist" CFBundleIdentifier 2>/dev/null
            return
        fi
        next="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')"
        [[ "$next" != "$pid" ]] || return 1
        pid="$next"
    done
    return 1
}

app_bundle_id() { defaults read "$1/Contents/Info.plist" CFBundleIdentifier 2>/dev/null; }

# Whether this script runs inside the app at <path>: quitting it would end the script.
runs_inside() { # <app path>
    local id host
    id="$(app_bundle_id "$1")" && host="$(host_bundle_id)" && [[ -n "$id" && "$id" == "$host" ]]
}

app_running() { pgrep -qf "$1/Contents/MacOS/" 2>/dev/null; }

# Quits a running app the way you would (it can save its state), waits for it,
# and stops it when it does not quit in time. The app this script runs in is
# left running. Returns 1 when the app is still running. DRY_RUN=1 only says so.
stop_app() { # <app path> [seconds to wait]
    local app="$1" wait="${2:-10}" name id i
    name="$(basename "$app" .app)"
    app_running "$app" || return 0
    if runs_inside "$app"; then
        echo "  =  $name stays open: this uninstaller runs in it"
        return 1
    fi
    echo "  ■  quitting $name"
    ((${DRY_RUN:-0} == 0)) || return 0
    if id="$(app_bundle_id "$app")"; then osascript -e "tell application id \"$id\" to quit" >/dev/null 2>&1 || true; fi
    for ((i=0; i<wait*4; i++)); do app_running "$app" || return 0; sleep 0.25; done
    echo "  ■  $name did not quit in ${wait}s; stopping it"
    pkill -f "$app/Contents/MacOS/" 2>/dev/null || true
    for ((i=0; i<20; i++)); do app_running "$app" || return 0; sleep 0.25; done
    pkill -9 -f "$app/Contents/MacOS/" 2>/dev/null || true
    sleep 0.5
    app_running "$app" || return 0
    echo "  !  could not stop $name" >&2
    return 1
}

# Stops a command-line program by name (btop, htop).
stop_command() { # <command>
    pgrep -xq "$1" 2>/dev/null || return 0
    echo "  ■  stopping $1"
    ((${DRY_RUN:-0} == 0)) || return 0
    pkill -x "$1" 2>/dev/null || true
}
