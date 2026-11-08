#!/bin/bash
# Sets Neovim up as an IDE for Java, JavaScript and TypeScript, Node, and AWS,
# with LazyVim, and adds the AI tools you pick:
#   ide        Kadomo's LazyVim config in ~/.config/nvim, and what it needs
#              from Homebrew: ripgrep, fd, tree-sitter-cli, and lazygit.
#              Another config already there is set aside, not deleted
#              (init.lua, init.vim, lua/, and its plugin records), and comes
#              back with uninstall.sh. The plugins download right away; the
#              language servers download the first time Neovim opens.
#   copilot    GitHub Copilot in Neovim (LazyVim's ai.copilot extra); you
#              sign in once with :Copilot auth
#   claude     Claude Code: the claude command (brew install --cask
#              claude-code, unless it is on this Mac already) and its Neovim
#              integration (LazyVim's ai.claudecode extra)
# Each thing Kadomo does is recorded, so uninstall.sh undoes exactly that.
#
# Usage: ./install.sh [--dry-run] [--only LIST] [--later LIST] [--no-sync]
#   --dry-run     show what would change without touching anything
#   --only LIST   only these, comma-separated (ide,copilot,claude)
#   --later LIST  tools the rest of this Kadomo install adds afterwards
#                 (node,java,neovim), so no reminder is printed for them
#   --no-sync     leave downloading the plugins for when Neovim first opens
#
# Runs on the Bash 3.2 that ships with macOS.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/neovim.sh"
STAMP="$(date +%Y%m%d-%H%M%S)"
DRY_RUN=0
ONLY=""
LATER=""
SYNC=1

while (($#)); do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        --no-sync) SYNC=0 ;;
        --only)
            shift; [[ $# -gt 0 ]] || { echo "--only needs a list (try --help)" >&2; exit 2; }
            ONLY="$1"
            for key in ${ONLY//,/ }; do
                nvim_known "$key" || { echo "Unknown item for --only: $key (known: $(nvim_keys))" >&2; exit 2; }
            done
            ;;
        --later)
            shift; [[ $# -gt 0 ]] || { echo "--later needs a list (try --help)" >&2; exit 2; }
            LATER="$1"
            ;;
        -h|--help) sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
    esac
    shift
done

selected() { [[ -z "$ONLY" || ",$ONLY," == *",$1,"* ]]; }
later() { [[ ",$LATER," == *",$1,"* ]]; }
run() { if ((DRY_RUN)); then echo "    would run: $*"; else "$@"; fi; }

# Adds a line to the record; a file| line replaces the one for the same path.
record() {
    ((DRY_RUN)) && return 0
    mkdir -p "$(dirname "$NVIM_MANIFEST")"
    case "$1" in
        file\|*)
            local path="${1#file|}"; path="${path%|*}"
            if [[ -f "$NVIM_MANIFEST" ]]; then
                awk -F'|' -v p="$path" '!($1 == "file" && $2 == p)' "$NVIM_MANIFEST" >"$NVIM_MANIFEST.tmp"
                mv "$NVIM_MANIFEST.tmp" "$NVIM_MANIFEST"
            fi
            ;;
        *) nvim_recorded "$1" && return 0 ;;
    esac
    printf '%s\n' "$1" >>"$NVIM_MANIFEST"
}

# Makes a folder and the ones above it that are missing, recording each.
make_dirs() {
    local dir="$1" made=()
    while [[ ! -d "$dir" ]]; do made+=("$dir"); dir="$(dirname "$dir")"; done
    ((${#made[@]})) || return 0
    run mkdir -p "$1"
    for dir in "${made[@]}"; do record "dir|$dir"; done
}

todo=()
failed=0
brew=""

# Installs one Homebrew formula or cask and records it. Returns 1 when it could not.
brew_install() { # <formula or cask> <name> <label>
    local kind="$1" name="$2" label="$3"
    if [[ -z "$brew" ]] && ! brew="$(find_brew)"; then
        brew=""
        echo "  !  $label needs Homebrew, which is not installed" >&2
        todo+=("$label: install Homebrew (https://brew.sh), then run this again.")
        return 1
    fi
    if "$brew" list "--$kind" "$name" >/dev/null 2>&1; then
        echo "  =  $label (already installed with Homebrew)"
        return 0
    fi
    echo "  +  $label (brew install --$kind $name)"
    if ((DRY_RUN)); then echo "    would run: $brew install --$kind $name"; return 0; fi
    "$brew" install "--$kind" "$name" || echo "  !  brew install --$kind $name failed (offline?); run this again to retry" >&2
    if "$brew" list "--$kind" "$name" >/dev/null 2>&1; then record "$kind|$name"; else return 1; fi
}

# --- the IDE: Kadomo's LazyVim config ------------------------------------------

install_ide() {
    local entry formula cmd path backup f src dest last nvim ts label
    if [[ -L "$NVIM_CONFIG" ]]; then
        echo "  !  $(short_path "$NVIM_CONFIG") is a link to $(readlink "$NVIM_CONFIG"); left alone" >&2
        todo+=("Neovim IDE: $(short_path "$NVIM_CONFIG") is a link (a dotfiles manager's, perhaps), so Kadomo did not put its config there. Move it away and run this again to use Kadomo's.")
        return 1
    fi

    # What LazyVim needs from Homebrew.
    for entry in "${NVIM_DEPS[@]}"; do
        formula="${entry%%|*}"; cmd="${entry#*|}"
        if path="$(dev_command "$cmd")"; then
            echo "  =  $formula (already installed: $(short_path "$path"))"
        else
            brew_install formula "$formula" "$formula" || failed=1
        fi
    done

    # Another config's files, set aside once: on the first install only, so
    # what Kadomo's own config made since stays where it is.
    if ! nvim_config_recorded; then
        for entry in "${NVIM_ASIDE[@]}"; do
            path="$NVIM_CONFIG/$entry"
            [[ -e "$path" || -L "$path" ]] || continue
            backup="$(nvim_backup_path "$path")"
            echo "  ~  $(short_path "$path") (yours, set aside as $(basename "$backup"))"
            run mv "$path" "$backup"
            record "aside|$path|$backup"
        done
    fi

    for f in "${NVIM_FILES[@]}"; do
        src="$NVIM_SOURCE/$f"; dest="$NVIM_CONFIG/$f"; label="$(short_path "$dest")"
        [[ -f "$src" ]] || { echo "  !  missing neovim/config/$f" >&2; exit 1; }
        if [[ -f "$dest" && ! -L "$dest" ]] && cmp -s "$src" "$dest"; then
            echo "  =  $label (unchanged)"
            record "file|$dest|$(nvim_sha "$src")"
            continue
        fi
        last="$(nvim_recorded_sha "$dest")"
        if [[ -n "$last" && -f "$dest" && ! -L "$dest" && "$(nvim_sha "$dest")" == "$last" ]]; then
            echo "  ~  $label (updated)"
        elif [[ -e "$dest" || -L "$dest" ]]; then
            backup="$(nvim_backup_path "$dest")"
            echo "  ~  $label (your edits kept as $(basename "$backup"))"
            run mv "$dest" "$backup"
        else
            echo "  +  $label"
        fi
        make_dirs "$(dirname "$dest")"
        run cp "$src" "$dest"
        record "file|$dest|$(nvim_sha "$src")"
    done

    # The theme manager picks the theme's colors for a LazyVim config with
    # lua/plugins/theme.lua; it makes that link when it applies a theme.
    if [[ ! -L "$NVIM_CONFIG/lua/plugins/theme.lua" ]] && ts="$(theme_cmd theme-refresh)"; then
        if ((DRY_RUN)); then echo "  ▶  would run: theme-refresh (Neovim takes the theme's colors)"
        else echo "  ▶  theme-refresh (Neovim takes the theme's colors)"; "$ts" >/dev/null 2>&1 || true; fi
    fi

    if nvim="$(dev_command nvim)"; then
        if ((SYNC)); then
            echo "  ▶  downloading Neovim's plugins (nvim --headless \"+Lazy! sync\" +qa)"
            if ((DRY_RUN)); then
                echo "    would run: $nvim --headless +Lazy! sync +qa"
            elif ! "$nvim" --headless "+Lazy! sync" +qa </dev/null >/dev/null 2>&1; then
                todo+=("Neovim's plugins could not all be downloaded now (offline?). They download the next time you open nvim.")
            fi
        fi
        ((DRY_RUN)) || echo "     The first time Neovim opens, it downloads the language servers (Space c m shows them)."
    elif ! later neovim; then
        todo+=("Neovim itself is not installed: turn on Developer › Neovim in Kadomo's installer, or run: brew install neovim")
    fi
    if ! dev_present node && ! later node; then
        todo+=("The language servers for JavaScript, TypeScript, JSON, and YAML run on Node.js, which is not installed: turn on Developer › Node.js in Kadomo's installer, or run: brew install node")
    fi
    if ! dev_present java && ! later java; then
        todo+=("Java support (jdtls) needs a JDK 21 or later, and none is installed: turn on Developer › Java 25 in Kadomo's installer.")
    fi
}

# --- the AI tools ------------------------------------------------------------

# The AI tools turned on in a Neovim that does not have Kadomo's config, for one reminder at the end.
without_ide=()
ai_needs_ide() { nvim_config_recorded || selected ide || without_ide+=("$1"); }

install_copilot() {
    if nvim_recorded "enabled|copilot"; then
        echo "  =  GitHub Copilot in Neovim (already on)"
        return 0
    fi
    echo "  +  GitHub Copilot in Neovim (LazyVim's ai.copilot extra)"
    record "enabled|copilot"
    todo+=("GitHub Copilot: open nvim and run :Copilot auth to sign in with your GitHub account (it needs a Copilot plan; Copilot Free works).")
    if ! dev_present node && ! later node; then
        todo+=("GitHub Copilot runs on Node.js, which is not installed: turn on Developer › Node.js in Kadomo's installer, or run: brew install node")
    fi
    ai_needs_ide "GitHub Copilot"
}

install_claude() {
    local cmd new=0
    if cmd="$(nvim_claude_cmd)"; then
        echo "  =  Claude Code (already installed: $(short_path "$cmd"))"
    else
        brew_install cask "$CLAUDE_CASK" "Claude Code" || { failed=1; return 0; }
        new=1
    fi
    if nvim_recorded "enabled|claude"; then
        echo "  =  Claude Code in Neovim (already on)"
    else
        echo "  +  Claude Code in Neovim (LazyVim's ai.claudecode extra: Space a c opens it)"
        record "enabled|claude"
        ai_needs_ide "Claude Code"
    fi
    if ((new)) && ! ((DRY_RUN)); then
        todo+=("Claude Code: run claude in a terminal once to sign in (it needs a Claude Pro or Max plan, or an Anthropic Console account). Homebrew does not update it on its own: brew upgrade claude-code.")
    fi
}

selected ide && { install_ide || failed=1; }
selected copilot && install_copilot
selected claude && install_claude
if selected copilot || selected claude; then
    if ((DRY_RUN)); then echo "  ▶  would write $(short_path "$NVIM_AI_FILE")"
    else make_dirs "$NVIM_CONFIG"; nvim_write_ai; fi
    if ((${#without_ide[@]})); then
        todo+=("$(printf '%s' "${without_ide[*]}" | sed 's/ Claude/ and Claude/') in Neovim $( ((${#without_ide[@]} > 1)) && echo need || echo needs) Kadomo's Neovim IDE setup to load: turn on Developer › Neovim IDE in Kadomo's installer.")
    fi
fi

if ((${#todo[@]})); then
    printf '\n  Still needs you:\n'
    for ((i=0; i<${#todo[@]}; i++)); do
        printf '%s\n' "${todo[i]}" | fold -s -w 76 | sed "s/ *$//; 1s/^/  $((i+1)). /; 1!s/^/     /"
    done
fi

((DRY_RUN)) && echo "Dry run: nothing was changed."
exit "$failed"
