#!/bin/bash
# Undoes neovim/install.sh: removes Kadomo's Neovim config (a file you edited
# is kept as <name>.bak.<timestamp>), the AI tools' switch file, and what
# Neovim wrote for that config (lazy-lock.json, lazyvim.json); puts back the
# config that was there before; and uninstalls what install.sh installed with
# Homebrew (ripgrep, fd, tree-sitter-cli, lazygit, Claude Code). Neovim's own
# data stays, as with a plain `brew uninstall`: the downloaded plugins and
# language servers in ~/.local/share/nvim, and Claude Code's ~/.claude.
#
# Usage: ./uninstall.sh [--dry-run]
#   --dry-run   show what would change without touching anything
#
# Runs on the Bash 3.2 that ships with macOS.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/neovim.sh"
STAMP="$(date +%Y%m%d-%H%M%S)"
DRY_RUN=0

case "${1:-}" in
    "") ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
esac

run() { if ((DRY_RUN)); then echo "    would run: $*"; else "$@"; fi; }

if [[ ! -s "$NVIM_MANIFEST" ]]; then
    echo "  =  no neovim installed"
    exit 0
fi

failed=0
had_config=0
nvim_config_recorded && had_config=1

# Kadomo's files; one you edited is kept next to itself.
while IFS='|' read -r kind path sha; do
    [[ "$kind" == file ]] || continue
    if [[ ! -e "$path" && ! -L "$path" ]]; then
        echo "  =  $(short_path "$path") (already removed)"
    elif [[ -f "$path" && ! -L "$path" && "$(nvim_sha "$path")" == "$sha" ]]; then
        echo "  -  $(short_path "$path")"
        run rm -f -- "$path"
    else
        backup="$(nvim_backup_path "$path")"
        echo "  ~  $(short_path "$path") (you edited it; kept as $(basename "$backup"))"
        run mv "$path" "$backup"
    fi
done <"$NVIM_MANIFEST"

# The AI tools' switch file, and what Neovim wrote for Kadomo's config.
if [[ -e "$NVIM_AI_FILE" ]]; then
    echo "  -  $(short_path "$NVIM_AI_FILE") (the AI tools)"
    run rm -f -- "$NVIM_AI_FILE"
fi
if ((had_config)); then
    for f in "${NVIM_RUNTIME[@]}"; do
        [[ -e "$NVIM_CONFIG/$f" ]] || continue
        echo "  -  $(short_path "$NVIM_CONFIG/$f") (Neovim's record for Kadomo's config)"
        run rm -f -- "$NVIM_CONFIG/$f"
    done
    # The theme manager's link for a LazyVim config; one of yours that comes
    # back gets it again the next time a theme is applied.
    link="$NVIM_CONFIG/lua/plugins/theme.lua"
    if [[ -L "$link" && "$(readlink "$link")" == */kadomo/* ]]; then
        echo "  -  $(short_path "$link") (the theme manager's link)"
        run rm -f -- "$link"
    fi
fi

# The folders Kadomo made, deepest first, when nothing else is in them.
awk -F'|' '$1 == "dir" { print length($2) "|" $2 }' "$NVIM_MANIFEST" | sort -t'|' -k1,1nr | cut -d'|' -f2- |
while IFS= read -r dir; do
    [[ -d "$dir" ]] || continue
    if ((DRY_RUN)); then
        [[ -n "$(ls -A "$dir" 2>/dev/null)" ]] || echo "    would run: rmdir $dir"
    else
        rmdir "$dir" 2>/dev/null || true
    fi
done

# The config that was here before: what was set aside comes back. Files you
# added to Kadomo's in the meantime are kept, set aside in turn.
while IFS='|' read -r kind path backup; do
    [[ "$kind" == aside ]] || continue
    if [[ ! -e "$backup" && ! -L "$backup" ]]; then
        echo "  !  $(short_path "$backup") is gone; nothing to put back at $(short_path "$path")" >&2
        continue
    fi
    if [[ -e "$path" || -L "$path" ]]; then
        if ((DRY_RUN == 0)) && [[ -d "$path" && ! -L "$path" && -z "$(ls -A "$path" 2>/dev/null)" ]]; then
            rmdir "$path"
        else
            kept="$(nvim_backup_path "$path")"
            echo "  ~  $(short_path "$path") (what you added since; kept as $(basename "$kept"))"
            run mv "$path" "$kept"
        fi
    fi
    echo "  ↩  $(short_path "$path") (yours, from $(basename "$backup"))"
    run mv "$backup" "$path"
done <"$NVIM_MANIFEST"

# What Kadomo installed with Homebrew.
brew=""
if grep -qE '^(formula|cask)\|' "$NVIM_MANIFEST"; then
    if ! brew="$(find_brew)"; then
        echo "  !  Homebrew not found; left these installed:" >&2
        grep -E '^(formula|cask)\|' "$NVIM_MANIFEST" | sed 's/^[^|]*|/       /' >&2
        # The record stays, so a later run with Homebrew back can finish the job.
        exit 1
    fi
fi
while IFS='|' read -r kind name; do
    case "$kind" in
        formula|cask)
            if ! "$brew" list "--$kind" "$name" >/dev/null 2>&1; then
                echo "  =  $name (already removed)"
                continue
            fi
            echo "  -  $name (brew uninstall --$kind $name)"
            if ! run "$brew" uninstall "--$kind" "$name"; then
                # Most often another package needs it now; it stays, and that is fine.
                echo "  !  brew uninstall --$kind $name failed; $name stays installed" >&2
            fi
            ;;
    esac
done <"$NVIM_MANIFEST"

if ((failed == 0)); then
    run rm -f -- "$NVIM_MANIFEST"
    run rmdir "$STATE_DIR" 2>/dev/null || true
fi

((DRY_RUN)) && echo "Dry run: nothing was changed."
exit "$failed"
