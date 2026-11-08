#!/bin/bash
# Removes everything install.sh put in place and puts back what it changed:
# the theme-* commands and built-in themes, the current theme, the theme lists
# in Kadomo Menu (whose own theme goes back to what it was), the
# lines added to your Ghostty, Neovim, and Vim configs and their
# "kadomo" colorscheme links, Kadomo's Starship block in .zshrc and its
# config (Starship itself stays installed), btop's old theme, Neovim's theme link,
# VS Code's color theme from before (and the Kadomo theme extension and any
# Marketplace themes an older Kadomo installed for a theme),
# and the wallpaper (on every Space and display still showing Kadomo's, from
# the copy of macOS's wallpaper store taken at first install) and light/dark
# mode from before, when the theme still shows them. Your own themes,
# templates, wallpapers, and hooks in ~/.config/kadomo are kept.
# Also cleans up the btop theme that older Kadomo dotfiles set up. Terminal.app
# is never touched.
#
# Usage: ./uninstall.sh [--dry-run]
#   --dry-run   show what would change without touching anything
#
# Runs on the Bash 3.2 that ships with macOS.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib/common.sh"
source "$LIB/apply.sh"
source "$HERE/setup.sh"
DRY_RUN=0

case "${1:-}" in
    "") ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help) sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
esac

run() { if ((DRY_RUN)); then echo "    would run: $*"; else "$@"; fi; }

if [[ ! -d "$RECORD_DIR" && ! -s "$BTOP_MANIFEST" && ! -d "$LEGACY_TERMINAL_DIR" && ! -d "$KADOMO_CONFIG/starship" ]]; then
    echo "  =  no kadomo-theme-manager installed"
    exit 0
fi

# The apps that were following the theme, read before theme.conf goes.
following=" $(enabled_apps) "

# Where the theme manager's wallpapers live: its themes, yours, the ones it
# draws, and Kadomo Menu's Omarchy themes.
OUR_WALLPAPERS=("$SHARE" "$KADOMO_CONFIG" "$STATE" "$HOME/Library/Application Support/kadomo-menu")
ours() { local dir; for dir in "${OUR_WALLPAPERS[@]}"; do [[ "$1" == "$dir"/* ]] && return 0; done; return 1; }

# --- live state first, while the theme files are still there -----------------

source "$LIB/starship.sh"
if starship_on; then
    if ((DRY_RUN)); then echo "  -  Starship for zsh (Kadomo's block in $(short_path "$(starship_zshrc)"), its init.zsh and config; Starship stays installed)"
    else starship_disable || echo "  !  Starship: see above; the rest is removed anyway" >&2; fi
fi

if [[ -s "$MENU_BEFORE" ]] && menu_installed && [[ "$(menu_theme)" == kadomo ]]; then
    before="$(cat "$MENU_BEFORE")"
    [[ "$before" != kadomo ]] || before=kadomo-dark
    echo "  ↩  Kadomo Menu theme → $before"
    menu_set_theme "$before"
fi

# Older dotfiles' record of a Terminal profile they made: only the record goes.
if [[ -d "$LEGACY_TERMINAL_DIR" ]]; then
    echo "  -  $(short_path "$LEGACY_TERMINAL_DIR") (older dotfiles' record; Terminal is left as it is)"
    run rm -rf -- "$LEGACY_TERMINAL_DIR"
fi

btop_uninstall
vscode_remove

if [[ -s "$WALLPAPER_STORE_BEFORE" ]]; then
    # Every Space and display still showing one of Kadomo's wallpapers gets
    # back the picture it had before install; one you chose since stays.
    if ((DRY_RUN)); then
        echo "  ↩  wallpaper (every Space showing Kadomo's gets back the one from before install)"
    elif restored="$(osascript -l JavaScript "$LIB/wallpaper.js" restore "$WALLPAPER_STORE_BEFORE" "${OUR_WALLPAPERS[@]}" 2>/dev/null)"; then
        if [[ -n "$restored" ]]; then echo "  ↩  wallpaper (from before install, on every Space)"
        else echo "  =  wallpaper (changed since install; left as is)"; fi
    else
        echo "  !  could not put back the wallpaper from before install; choose one in System Settings > Wallpaper" >&2
    fi
elif [[ -s "$WALLPAPER_BEFORE" ]]; then
    # Installed before the store was recorded: each display's picture, on
    # this Space and every other one still showing Kadomo's.
    shown="$(osascript -l JavaScript "$LIB/wallpaper.js" get 2>/dev/null | head -n 1 || true)"
    if [[ -z "$shown" ]] || ours "$shown"; then
        pictures=()
        while IFS= read -r file; do [[ -n "$file" ]] && pictures+=("$file"); done <"$WALLPAPER_BEFORE"
        if ((${#pictures[@]})) && [[ -f "${pictures[0]}" ]]; then
            echo "  ↩  wallpaper (${pictures[0]##*/})"
            run osascript -l JavaScript "$LIB/wallpaper.js" set-each "${pictures[@]}" -- "${OUR_WALLPAPERS[@]}" >/dev/null || true
        fi
    else
        echo "  =  wallpaper (changed since install; left as is)"
    fi
fi
if [[ -s "$APPEARANCE_BEFORE" ]]; then
    before="$(cat "$APPEARANCE_BEFORE")"
    if [[ "$before" == dark ]] && ! macos_dark; then
        echo "  ↩  dark mode"; run macos_set_dark true || true
    elif [[ "$before" == light ]] && macos_dark; then
        echo "  ↩  light mode"; run macos_set_dark false || true
    fi
fi

nvim_link="$HOME/.config/nvim/lua/plugins/theme.lua"
if [[ -L "$nvim_link" && "$(readlink "$nvim_link")" == "$THEME_DIR/neovim.lua" ]]; then
    echo "  -  $(short_path "$nvim_link")"
    run rm -f -- "$nvim_link"
fi

# --- what install.sh recorded ------------------------------------------------

dirs=()
if [[ -s "$RECORD" ]]; then
    while IFS='|' read -r kind path extra leader; do
        case "$kind" in
            link)
                if [[ -L "$path" ]]; then echo "  -  $(short_path "$path")"; run rm -f -- "$path"; fi
                ;;
            block) unwire "$path" "$extra" "$leader" ;;
            dir) dirs+=("$path") ;;
        esac
    done <"$RECORD"
fi

# Generated files: the current theme, the launcher's list, caches and locks.
for path in "$CURRENT" "$MENU_COMMANDS" "$SETTINGS" "$STARSHIP_DIR" "$STATE" "$CACHE" "$SHARE"; do
    if [[ -e "$path" || -L "$path" ]]; then
        echo "  -  $(short_path "$path")"
        run rm -rf -- "$path"
    fi
done
if [[ -f "$HOOKS_DIR/notify.sample" ]] && cmp -s "$HERE/hooks/notify.sample" "$HOOKS_DIR/notify.sample"; then
    run rm -f -- "$HOOKS_DIR/notify.sample"
fi

# Folders install.sh made go when they are empty; deepest first. One with your
# themes, templates, wallpapers, or hooks in it stays.
for path in "$KADOMO_CONFIG/menu/commands" "$KADOMO_CONFIG/menu"; do dirs+=("$path"); done
while IFS= read -r path; do
    [[ -d "$path" ]] || continue
    if ((DRY_RUN)); then continue; fi
    if rmdir "$path" 2>/dev/null; then :; elif [[ "$path" != "$BIN_DIR" && "$path" != "$SHARE" ]]; then
        echo "  =  $(short_path "$path") (kept: it has your files)"
    fi
done < <(printf '%s\n' ${dirs[@]+"${dirs[@]}"} | awk '{ print length($0) "\t" $0 }' | sort -rn | cut -f2-)
run rmdir "$(dirname "$SHARE")" 2>/dev/null || true

# Apps still showing the theme go back to their own colors.
if ! ((DRY_RUN)); then
    [[ "$following" != *" ghostty "* ]] || reload_ghostty
    [[ "$following" != *" btop "* ]] || reload_btop
    # OmniWM gets back the border colors it had before Kadomo's theme.
    if [[ "$following" == *" omniwm "* && -x "$HOME/.local/bin/kadomo-omniwm" ]]; then
        "$HOME/.local/bin/kadomo-omniwm" restore-borders >/dev/null 2>&1 || true
    fi
fi

run rm -rf -- "$RECORD_DIR"
run rmdir "$STATE_DIR" 2>/dev/null || true
((DRY_RUN)) && echo "Dry run: nothing was changed."
exit 0
