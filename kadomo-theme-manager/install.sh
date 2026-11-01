#!/bin/bash
# Installs the theme manager: the theme-* commands in ~/.local/bin, the
# built-in themes (tmac2k, Catppuccin, Catppuccin Latte, Gruvbox,
# Rosé Pine, Sora), and the wiring that makes each app follow the current theme:
#   Ghostty and kitty   a line in their config that reads the theme's colors
#   Kadomo Menu         its theme set to "kadomo", plus a Desktop Themes list
#   OmniWM              its focus border colors in settings.toml (kadomo-omniwm)
#   Neovim and Vim      a "kadomo" colorscheme in tmac2k's style, selected in
#                       init.lua (or LazyVim's plugins) and ~/.vimrc
#   VS Code             a "Kadomo" color theme drawn from the theme, in
#                       workbench.colorTheme (nothing from the Marketplace)
#   Starship (zsh)      theme-starship; nothing changes until you run
#                       theme-starship enable (developer/ does)
#   btop                color_theme "current", linked to the theme  (btop)
#   wallpaper, light/dark mode                                      (desktop)
# Then it applies tmac2k, or reapplies the theme you already have. What was
# there before is recorded, and uninstall.sh puts it back.
#
# Usage: ./install.sh [--dry-run] [--only LIST]
#   --dry-run     show what would change without touching anything
#   --only LIST   comma-separated: themes (always installed), btop, desktop
#
# Runs on the Bash 3.2 that ships with macOS.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib/common.sh"
source "$LIB/apply.sh"
source "$HERE/setup.sh"
DRY_RUN=0
ONLY=""
KEYS="themes,btop,desktop"

while (($#)); do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        --only)
            shift; [[ $# -gt 0 ]] || { echo "--only needs a list (try --help)" >&2; exit 2; }
            ONLY="$1"
            for key in ${ONLY//,/ }; do
                [[ ",$KEYS," == *",$key,"* ]] || { echo "Unknown item for --only: $key (known: $KEYS)" >&2; exit 2; }
            done
            ;;
        -h|--help) sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
    esac
    shift
done

selected() { [[ -z "$ONLY" || ",$ONLY," == *",$1,"* ]]; }
run() { if ((DRY_RUN)); then echo "    would run: $*"; else "$@"; fi; }

# --- the commands and built-in themes ----------------------------------------

echo "  +  $(short_path "$SHARE") (commands, templates, and themes)"
make_dirs "$(dirname "$SHARE")"
if ! ((DRY_RUN)); then
    rm -rf -- "$SHARE.new"
    mkdir -p "$SHARE.new"
    cp -R "$HERE/bin" "$HERE/lib" "$HERE/themed" "$HERE/themes" "$SHARE.new/"
    rm -rf -- "$SHARE"
    mv "$SHARE.new" "$SHARE"
fi
record "dir|$SHARE"
make_dirs "$BIN_DIR"
for cmd in "${COMMANDS[@]}"; do
    link="$BIN_DIR/$cmd"
    if [[ -e "$link" && ! -L "$link" ]] || { [[ -L "$link" ]] && [[ "$(readlink "$link")" != "$SHARE/bin/$cmd" ]]; }; then
        echo "  !  $(short_path "$link") is not Kadomo's; left alone" >&2
        continue
    fi
    [[ -L "$link" ]] || echo "  +  $(short_path "$link")"
    run ln -sfh "$SHARE/bin/$cmd" "$link"
    record "link|$link"
done
for cmd in "${RETIRED_COMMANDS[@]}"; do
    link="$BIN_DIR/$cmd"
    if [[ -L "$link" && "$(readlink "$link")" == "$SHARE/bin/$cmd" ]]; then
        echo "  -  $(short_path "$link") (no longer part of Kadomo)"
        run rm -f -- "$link"
    fi
done

# Yours to fill, and the folders theme-set writes to.
for dir in "$USER_THEMES" "$USER_TEMPLATES" "$USER_BACKGROUNDS" "$HOOKS_DIR" \
    "$(dirname "$MENU_COMMANDS")" "$STATE" "$CACHE"; do
    make_dirs "$dir"
done
if [[ ! -e "$HOOKS_DIR/notify.sample" ]]; then
    echo "  +  $(short_path "$HOOKS_DIR/notify.sample")"
    run cp "$HERE/hooks/notify.sample" "$HOOKS_DIR/notify.sample"
fi

# Which apps follow the theme. theme.conf is yours to edit afterwards.
apps="ghostty kitty borders omniwm kadomo-menu neovim vim vscode starship"
selected btop && apps="$apps btop"
selected desktop && apps="$apps appearance wallpaper"
echo "  +  $(short_path "$SETTINGS") (apps = $apps)"
if ! ((DRY_RUN)); then
    cat >"$SETTINGS" <<EOF
# Apps that follow the Kadomo theme. Take a name out to leave that app alone,
# then run theme-refresh. All of them: $ALL_APPS
# install.sh writes this file again.
apps = $apps
EOF
fi

# --- wiring ------------------------------------------------------------------

wire "$(ghostty_config)" "$GHOSTTY_LINE"
wire "$(kitty_config)" "$KITTY_LINE"
wire_editors
selected btop && btop_install

# How things are now, before the first theme changes them. An earlier
# install's record is kept: it knows what was there before Kadomo.
if ! ((DRY_RUN)); then
    mkdir -p "$RECORD_DIR"
    if menu_installed && [[ ! -s "$MENU_BEFORE" ]]; then menu_theme >"$MENU_BEFORE"; fi
    if selected desktop; then
        [[ -s "$APPEARANCE_BEFORE" ]] || { macos_dark && echo dark || echo light; } >"$APPEARANCE_BEFORE"
        # The whole wallpaper store too (every Space and display, and macOS's
        # dynamic and aerial pictures, which a path cannot name), taken only
        # with the first record so it is never one of Kadomo's own.
        if [[ ! -s "$WALLPAPER_BEFORE" ]]; then
            osascript -l JavaScript "$LIB/wallpaper.js" save "$WALLPAPER_STORE_BEFORE" >/dev/null 2>&1 || rm -f -- "$WALLPAPER_STORE_BEFORE"
            osascript -l JavaScript "$LIB/wallpaper.js" get >"$WALLPAPER_BEFORE" 2>/dev/null || true
        fi
    fi
fi

# --- the first theme -----------------------------------------------------------

# Purple Night (once called Tokyo Night) is no longer built in. If it was your
# theme, and is not a whole theme of your own, you get tmac2k.
retired() { [[ "$1" == purple-night || "$1" == tokyo-night ]] && [[ ! -e "$USER_THEMES/$1/colors.toml" ]]; }

# The theme you have is kept: one of Kadomo's, or an external one (Kadomo
# Menu's Omarchy themes) whose folder is still there.
keep_current() { local name; name="$(current_name)" && ! retired "$name" && { theme_exists "$name" || external_theme_dir "$name" >/dev/null; }; }
if ((DRY_RUN)); then
    if keep_current; then echo "  ▶  would apply $(theme_label "$(current_name)") again"; else echo "  ▶  would apply tmac2k"; fi
elif keep_current; then
    name="$(current_name)"
    echo "  ▶  applying $(theme_label "$name") again"
    "$BIN_DIR/theme-refresh" >/dev/null || "$SHARE/bin/theme-refresh" >/dev/null
else
    echo "  ▶  applying tmac2k"
    "$SHARE/bin/theme-set" tmac2k >/dev/null
fi

if app_enabled kadomo-menu && menu_installed; then
    if [[ "$(menu_theme)" != kadomo ]]; then
        echo "  ~  Kadomo Menu theme → kadomo (follows the desktop theme)"
        menu_set_theme kadomo
    fi
fi

case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) echo "  !  $(short_path "$BIN_DIR") is not on your PATH; add it to run theme-set and friends by name" ;;
esac
((DRY_RUN)) && echo "Dry run: nothing was changed."
exit 0
