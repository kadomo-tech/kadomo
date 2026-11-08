# Shared by install.sh and uninstall.sh: which configs go where, the record of
# what was installed, and how to tell a running tool to reload.

# Source (relative to dotfiles/) and destination, one pair per line. Files
# deeper in a folder come first, so uninstall.sh empties a subfolder before
# trying to remove its parent.
FILES=(
    "ghostty/config.ghostty|$HOME/.config/ghostty/config.ghostty"
    "editors/kadomo.vim|$HOME/.vim/plugin/kadomo.vim"
    "editors/kadomo.lua|$HOME/.config/nvim/plugin/kadomo.lua"
)

# Configs and formulae older installs placed that this checkout no longer ships
# (kitty's config, AeroSpace's config, and JankyBorders with its bordersrc) are
# still in the records below; uninstall.sh --retired removes them, and
# install.sh runs it.

# One line per installed file: <destination>|<backup of the original, or
# empty>|<SHA-256 of the copy Kadomo placed>. The checksum tells Kadomo's own
# copy from one you edited, even when this checkout no longer ships that file.
STATE_DIR="${KADOMO_STATE_DIR:-$HOME/Library/Application Support/kadomo}"
MANIFEST="$STATE_DIR/dotfiles-installed.txt"
# One line per formula Kadomo installed: <formula>|<tap it added, or empty>. None
# is installed any more; older installs recorded JankyBorders here.
PACKAGE_MANIFEST="$STATE_DIR/packages-installed.txt"

# The tools --only can name: each FILES folder.
tool_names() {
    local entry names=""
    for entry in "${FILES[@]}"; do names="$names,${entry%%/*}"; done
    printf '%s' "$names" | tr ',' '\n' | awk 'NF && !seen[$0]++' | paste -sd, -
}
tool_known() { [[ ",$(tool_names)," == *",$1,"* ]]; }

manifest_has() { [[ -f "$MANIFEST" ]] && grep -qF "$1|" "$MANIFEST"; }

sha256() { shasum -a 256 "$1" | cut -d' ' -f1; }

# The checksum recorded for a destination, or nothing (also for records made before checksums).
recorded_sha() {
    [[ -f "$MANIFEST" ]] || return 0
    awk -F'|' -v d="$1" '$1 == d { print $3; exit }' "$MANIFEST"
}

# Homebrew, even when this shell's PATH lacks it.
find_brew() {
    local path
    for path in "$(command -v brew 2>/dev/null)" /opt/homebrew/bin/brew /usr/local/bin/brew; do
        [[ -n "$path" && -x "$path" ]] && { printf '%s' "$path"; return 0; }
    done
    return 1
}

# Running Ghostty apps, one "<pid> <executable>" line each. Found with ps by the
# app's executable path, because pgrep does not match Ghostty's process name.
ghostty_processes() {
    ps -axo pid=,comm= 2>/dev/null | sed -n 's|^ *\([0-9][0-9]*\) \(.*\.app/Contents/MacOS/ghostty\)$|\1 \2|p'
}

# Whether the Ghostty at this executable reloads its config on SIGUSR2 (1.2 and
# later). An older one would quit on that signal instead.
ghostty_reloads_on_signal() {
    local version major minor
    version="$(defaults read "${1%/MacOS/*}/Info.plist" CFBundleShortVersionString 2>/dev/null)" || return 1
    major="${version%%.*}"; minor="${version#*.}"; minor="${minor%%[!0-9]*}"
    [[ "$major" =~ ^[0-9]+$ && "$minor" =~ ^[0-9]+$ ]] || return 1
    ((major > 1 || (major == 1 && minor >= 2)))
}

# Tells a running tool to pick up its new config. Respects DRY_RUN via run().
reload() {
    case "$1" in
        ghostty)
            local pid exe
            while read -r pid exe; do
                if ghostty_reloads_on_signal "$exe"; then
                    echo "  ↻  reloading Ghostty"
                    run kill -USR2 "$pid" || echo "  !  could not signal Ghostty; press Cmd+Shift+, in it" >&2
                else
                    echo "  ↻  Ghostty is running: press Cmd+Shift+, in it to reload its config"
                fi
            done < <(ghostty_processes)
            ;;
    esac
}

# Undoes what a running tool still shows after its config is gone and nothing
# was restored. Respects DRY_RUN via run().
unload() {
    case "$1" in
        borders)
            # Without its bordersrc (from older installs), the running borders would keep Kadomo's style.
            if pgrep -xq borders 2>/dev/null; then
                echo "  ■  stopping borders"
                run pkill -x borders || true
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
