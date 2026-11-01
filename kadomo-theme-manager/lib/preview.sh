#!/bin/bash
# The preview pane of theme-pick and theme-bg-pick: a theme's name, its palette
# as color swatches, and its thumbnail when the terminal can show images.
# Usage: preview.sh theme <name> | image <path>
set -uo pipefail
source "$(dirname "$0")/common.sh"
source "$LIB/apply.sh"
source "$LIB/starship.sh"

# Draws an image in the preview pane: kitty's icat in kitty and Ghostty, else chafa.
show_image() {
    local size="${FZF_PREVIEW_COLUMNS:-40}x${FZF_PREVIEW_LINES:-20}"
    if [[ -n "${KITTY_WINDOW_ID:-}" || "${TERM_PROGRAM:-}" == ghostty ]] && command -v kitten >/dev/null; then
        kitten icat --clear --transfer-mode=memory --stdin=no --place="${size}@0x6" "$1" 2>/dev/null
    elif command -v chafa >/dev/null; then
        chafa --size="$size" "$1" 2>/dev/null
    fi
}

swatches() {
    awk -F'\t' '
        function hv(h,   i, n) { n = 0; for (i = 1; i <= 2; i++) n = n * 16 + index("0123456789abcdef", substr(h, i, 1)) - 1; return n }
        function block(c) { return sprintf("\033[48;2;%d;%d;%dm    \033[0m", hv(substr(c, 2, 2)), hv(substr(c, 4, 2)), hv(substr(c, 6, 2))) }
        { P[$1] = $2 }
        END {
            printf "%s mode\n\n", P["mode"]
            for (i = 0; i < 8; i++) printf "%s", block(P["color" i]); printf "\n"
            for (i = 8; i < 16; i++) printf "%s", block(P["color" i]); printf "\n\n"
            printf "%s accent  %s background  %s foreground\n", block(P["accent"]), block(P["background"]), block(P["foreground"])
        }' "$1"
}

case "${1:-}" in
    theme)
        name="$2"
        printf '%s\n\n' "$(display_name "$name")"
        for dir in "$USER_THEMES/$name" "$BUILTIN_THEMES/$name"; do
            [[ -f "$dir/colors.toml" ]] || continue
            resolve_palette "$dir/colors.toml" 2>/dev/null >"${TMPDIR:-/tmp}/kadomo-preview.$$"
            swatches "${TMPDIR:-/tmp}/kadomo-preview.$$"
            rm -f "${TMPDIR:-/tmp}/kadomo-preview.$$"
            break
        done
        # With Starship on, the prompt this theme would give (drawn, not run).
        if starship_on; then printf '\n'; starship_preview "$name" "$(starship_icons)" 2>/dev/null || true; fi
        image="$(ls "$PREVIEWS/$name".* 2>/dev/null | head -n 1)"
        [[ -z "$image" ]] || show_image "$image"
        ;;
    image)
        printf '%s\n' "${2##*/}"
        show_image "$2"
        ;;
esac
