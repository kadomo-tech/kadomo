# Shared by neovim/install.sh and uninstall.sh, and the top-level install.sh:
# Kadomo's Neovim setup (LazyVim for Java, JavaScript and TypeScript, Node,
# and AWS), the tools it needs from Homebrew, the AI tools that can go in it,
# and the record of what Kadomo did.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/developer/dev.sh"

NVIM_SOURCE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config"
# Neovim's config folder. KADOMO_NVIM_CONFIG replaces it, for tests.
NVIM_CONFIG="${KADOMO_NVIM_CONFIG:-$HOME/.config/nvim}"

# One item per line: <key>|<label>. The key is what --only takes.
NVIM_ITEMS=(
    "ide|Neovim IDE (LazyVim)"
    "copilot|GitHub Copilot in Neovim"
    "claude|Claude Code"
)

# The files Kadomo places, relative to NVIM_CONFIG and to config/ here.
NVIM_FILES=(init.lua lua/config/lazy.lua lua/plugins/kadomo-aws.lua)
# What would get in the way of Kadomo's config: another config's entry
# point, its modules, and its plugin records. The first install sets these
# aside next to themselves; uninstall.sh puts them back. Other files in the
# folder stay where they are (plugin/, colors/, after/, ftplugin/ load with
# Kadomo's config too).
NVIM_ASIDE=(init.lua init.vim lua lazy-lock.json lazyvim.json)
# What Neovim writes into the folder while it runs Kadomo's config.
NVIM_RUNTIME=(lazy-lock.json lazyvim.json)
# Which AI tools are on, for lua/config/lazy.lua. Written from the record.
NVIM_AI_FILE="$NVIM_CONFIG/kadomo-ai.lua"

# What LazyVim needs from Homebrew: <formula>|<command it provides>.
# ripgrep and fd for searching, tree-sitter's CLI to build syntax parsers
# (with the Command Line Tools' compiler, which Homebrew brings), and lazygit
# for LazyVim's Git screen (Space g g).
NVIM_DEPS=("ripgrep|rg" "fd|fd" "tree-sitter-cli|tree-sitter" "lazygit|lazygit")
CLAUDE_CASK="claude-code"

# One line per thing Kadomo did: file|<path>|<SHA-256 of the copy placed>,
# aside|<path>|<where it was set aside>, dir|<folder Kadomo made>,
# formula|<name> and cask|<name> (installed with Homebrew), and
# enabled|copilot, enabled|claude (the AI tools turned on).
NVIM_MANIFEST="$STATE_DIR/neovim-installed.txt"

nvim_keys() {
    local entry keys=""
    for entry in "${NVIM_ITEMS[@]}"; do keys="$keys,${entry%%|*}"; done
    printf '%s' "${keys#,}"
}
nvim_known() { [[ ",$(nvim_keys)," == *",$1,"* ]]; }

nvim_recorded() { [[ -f "$NVIM_MANIFEST" ]] && grep -qxF "$1" "$NVIM_MANIFEST"; }
# Whether Kadomo's config files were placed (and not removed since).
nvim_config_recorded() { [[ -f "$NVIM_MANIFEST" ]] && grep -q '^file|' "$NVIM_MANIFEST"; }

nvim_sha() { shasum -a 256 "$1" | cut -d' ' -f1; }

# The checksum recorded for a placed file, or nothing.
nvim_recorded_sha() {
    [[ -f "$NVIM_MANIFEST" ]] || return 0
    awk -F'|' -v p="$1" '$1 == "file" && $2 == p { print $3; exit }' "$NVIM_MANIFEST"
}

# A backup path next to $1 that does not exist yet.
nvim_backup_path() {
    local stamp path n=2
    stamp="${STAMP:-$(date +%Y%m%d-%H%M%S)}"
    path="$1.bak.$stamp"
    while [[ -e "$path" || -L "$path" ]]; do path="$1.bak.$stamp-$n"; n=$((n+1)); done
    printf '%s' "$path"
}

# Whether Kadomo's config files are in place, as this checkout has them.
nvim_config_current() {
    local f
    for f in "${NVIM_FILES[@]}"; do
        [[ -f "$NVIM_CONFIG/$f" && ! -L "$NVIM_CONFIG/$f" ]] && cmp -s "$NVIM_SOURCE/$f" "$NVIM_CONFIG/$f" || return 1
    done
}

# The Homebrew formulae LazyVim needs that are not on this Mac, one per line.
nvim_deps_missing() {
    local entry
    for entry in "${NVIM_DEPS[@]}"; do
        dev_command "${entry#*|}" >/dev/null || printf '%s\n' "${entry%%|*}"
    done
}

# The claude command wherever it is: PATH, Homebrew, the native installer's
# ~/.local/bin, or an old npm "local" install.
nvim_claude_cmd() {
    local path
    for path in "$(dev_command claude || true)" "$HOME/.local/bin/claude" "$HOME/.claude/local/claude"; do
        [[ -n "$path" && -x "$path" ]] && { printf '%s' "$path"; return 0; }
    done
    return 1
}

# Whether an item is set up with nothing left to do (quick enough for the checklist).
nvim_present() {
    case "$1" in
        ide) nvim_config_current && [[ -z "$(nvim_deps_missing)" ]] ;;
        copilot) nvim_recorded "enabled|copilot" ;;
        claude) nvim_recorded "enabled|claude" && nvim_claude_cmd >/dev/null ;;
        *) return 1 ;;
    esac
}

# Whether installing an item needs Homebrew for something not here yet.
nvim_needs_brew() {
    case "$1" in
        ide) [[ -n "$(nvim_deps_missing)" ]] ;;
        claude) ! nvim_claude_cmd >/dev/null ;;
        *) return 1 ;;
    esac
}

# kadomo-ai.lua, from the record: which AI tools lua/config/lazy.lua loads.
# Removed when none is on. Respects DRY_RUN.
nvim_write_ai() {
    local copilot=false claude=false
    nvim_recorded "enabled|copilot" && copilot=true
    nvim_recorded "enabled|claude" && claude=true
    ((${DRY_RUN:-0} == 0)) || return 0
    if [[ "$copilot" == false && "$claude" == false ]]; then
        rm -f -- "$NVIM_AI_FILE"
        return 0
    fi
    mkdir -p "$(dirname "$NVIM_AI_FILE")"
    cat >"$NVIM_AI_FILE" <<LUA
-- Written by Kadomo's installer: the AI tools Neovim loads (see
-- lua/config/lazy.lua). Kadomo's installer and uninstaller rewrite this file,
-- so edits here do not last.
return { copilot = $copilot, claude_code = $claude }
LUA
}

# Whether another Neovim config is there, which the first install sets aside.
nvim_other_config() {
    local entry
    nvim_config_recorded && return 1
    [[ ! -L "$NVIM_CONFIG" ]] || return 1
    for entry in "${NVIM_ASIDE[@]}"; do
        [[ -e "$NVIM_CONFIG/$entry" || -L "$NVIM_CONFIG/$entry" ]] && return 0
    done
    return 1
}
