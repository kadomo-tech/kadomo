# Shared by install.sh and uninstall.sh: which configs go where, the record of
# what was installed, and how to tell a running tool to reload.

# Source (relative to dotfiles/) and destination, one pair per line. Files
# deeper in a folder come first, so uninstall.sh empties a subfolder before
# trying to remove its parent.
FILES=(
    "aerospace/aerospace.toml|$HOME/.config/aerospace/aerospace.toml"
    "ghostty/themes/tmac2k|$HOME/.config/ghostty/themes/tmac2k"
    "ghostty/config.ghostty|$HOME/.config/ghostty/config.ghostty"
)

# One line per installed file: <destination>|<backup of the original, or empty>.
STATE_DIR="${KADOMO_STATE_DIR:-$HOME/Library/Application Support/kadomo}"
MANIFEST="$STATE_DIR/dotfiles-installed.txt"

manifest_has() { [[ -f "$MANIFEST" ]] && grep -qF "$1|" "$MANIFEST"; }

# Tells a running tool to pick up its new config. Respects DRY_RUN via run().
reload() {
    case "$1" in
        aerospace)
            if command -v aerospace >/dev/null && pgrep -xq AeroSpace 2>/dev/null; then
                echo "  ↻  reloading AeroSpace"
                run aerospace reload-config || echo "  !  aerospace reload-config failed" >&2
            fi
            ;;
        ghostty)
            # Ghostty has no command to reload a running instance on macOS.
            if pgrep -xq ghostty 2>/dev/null; then
                echo "  ↻  Ghostty is running: press Cmd+Shift+, in it to reload its config"
            fi
            ;;
    esac
}

# Reloads each tool named in "$@" once, however many of its files changed.
reload_each() {
    local seen=" " tool
    for tool in "$@"; do
        [[ "$seen" == *" $tool "* ]] && continue
        seen+="$tool "
        reload "$tool"
    done
}

# A backup path next to $1 that does not exist yet, so no backup ever overwrites another.
backup_path() {
    local path="$1.bak.$STAMP" n=2
    while [[ -e "$path" || -L "$path" ]]; do path="$1.bak.$STAMP-$n"; n=$((n+1)); done
    printf '%s' "$path"
}
