# Shared by developer/install.sh and uninstall.sh, and the top-level
# install.sh: the developer tools Kadomo offers, how to tell each is already
# on this Mac (however it got there), and the record of what Kadomo installed.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/apps/apps.sh"

# One tool per line: <key>|<formula or cask>|<Homebrew name>|<label>. The key
# is what --only takes.
DEV_ITEMS=(
    "node|formula|node|Node.js"
    "java|cask|temurin@25|Java 25 (Temurin JDK)"
    "rancher|cask|rancher|Rancher Desktop"
    "vscode|cask|visual-studio-code|Visual Studio Code"
    "starship|formula|starship|Starship"
)
RANCHER_APP="Rancher Desktop.app"
VSCODE_APP="Visual Studio Code.app"

# One line per thing Kadomo did: formula|<name> and cask|<name> (installed
# with Homebrew), script|<path> (Starship from its own installer), and
# enabled|starship (Kadomo turned Starship on for zsh), and enabled|vscode
# (Kadomo made VS Code follow the theme).
DEV_MANIFEST="$STATE_DIR/developer-installed.txt"

# Homebrew's bin folders, searched besides PATH (a Kadomo run may start with a
# short PATH). KADOMO_EXTRA_PATH replaces them, for tests.
DEV_EXTRA_PATH="${KADOMO_EXTRA_PATH-/opt/homebrew/bin:/usr/local/bin}"
# macOS's JDK finder. /usr/bin/java exists even with no JDK (it only offers to
# install one), so java_home is what tells. KADOMO_JAVA_HOME overrides it.
JAVA_HOME_CMD="${KADOMO_JAVA_HOME:-/usr/libexec/java_home}"

dev_keys() {
    local entry keys=""
    for entry in "${DEV_ITEMS[@]}"; do keys="$keys,${entry%%|*}"; done
    printf '%s' "${keys#,}"
}
dev_entry() {
    local entry
    for entry in "${DEV_ITEMS[@]}"; do [[ "${entry%%|*}" == "$1" ]] && { printf '%s' "$entry"; return 0; }; done
    return 1
}

dev_command() { PATH="$PATH${DEV_EXTRA_PATH:+:$DEV_EXTRA_PATH}" command -v "$1" 2>/dev/null; }

# Starship wherever it is: PATH, Homebrew, its install script's ~/.local/bin,
# cargo. KADOMO_STARSHIP_SEARCH (the theme manager's too) replaces the list.
dev_starship() {
    local candidates=() path
    if [[ -n "${KADOMO_STARSHIP_SEARCH+set}" ]]; then
        IFS=: read -r -a candidates <<<"$KADOMO_STARSHIP_SEARCH"
    else
        candidates=("$(dev_command starship || true)" "$HOME/.local/bin/starship" "$HOME/.cargo/bin/starship")
    fi
    for path in ${candidates[@]+"${candidates[@]}"}; do
        [[ -n "$path" && -f "$path" && -x "$path" ]] && { printf '%s' "$path"; return 0; }
    done
    return 1
}

# Whether a tool is on this Mac, without asking Homebrew (quick enough for the checklist).
dev_present() {
    case "$1" in
        node) dev_command node >/dev/null ;;
        java) [[ -x "$JAVA_HOME_CMD" ]] && "$JAVA_HOME_CMD" >/dev/null 2>&1 ;;
        rancher) app_path "$RANCHER_APP" >/dev/null ;;
        vscode) app_path "$VSCODE_APP" >/dev/null ;;
        starship) dev_starship >/dev/null ;;
        *) return 1 ;;
    esac
}

# The installed version, for the report after installing.
dev_version() {
    local home bin app
    case "$1" in
        node) bin="$(dev_command node)" && "$bin" --version 2>/dev/null | head -n 1 ;;
        java) home="$("$JAVA_HOME_CMD" 2>/dev/null)" && "$home/bin/java" -version 2>&1 | head -n 1 ;;
        rancher) app="$(app_path "$RANCHER_APP")" && plutil -extract CFBundleShortVersionString raw -o - "$app/Contents/Info.plist" 2>/dev/null ;;
        vscode) app="$(app_path "$VSCODE_APP")" && plutil -extract CFBundleShortVersionString raw -o - "$app/Contents/Info.plist" 2>/dev/null ;;
        starship) bin="$(dev_starship)" && "$bin" --version 2>/dev/null | head -n 1 ;;
    esac
}

# A theme manager command (theme-starship, theme-vscode), when it is installed.
theme_cmd() {
    local path
    for path in "$HOME/.local/bin/$1" "$HOME/.local/share/kadomo/theme-manager/bin/$1"; do
        [[ -x "$path" ]] && { printf '%s' "$path"; return 0; }
    done
    return 1
}
theme_starship_cmd() { theme_cmd theme-starship; }
theme_vscode_cmd() { theme_cmd theme-vscode; }

dev_recorded() { [[ -f "$DEV_MANIFEST" ]] && grep -qxF "$1" "$DEV_MANIFEST"; }

short_path() { case "$1" in "$HOME"/*) printf '~%s' "${1#"$HOME"}" ;; *) printf '%s' "$1" ;; esac; }
