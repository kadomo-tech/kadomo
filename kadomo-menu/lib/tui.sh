#!/bin/bash
# Terminal UI shared by install.sh and uninstall.sh, here and at the repo root:
# colors, logo, keys, a checklist, two buttons, and one-line steps. Plain Bash
# 3.2 and ANSI escapes.
# The sourcing script sets TITLE and the ITEM_LABEL, ITEM_DETAIL, ITEM_ON arrays.

ESC=$'\033'
CYAN=""; DIM=""; BOLD=""; RED=""; BUTTON=""; RESET=""; LOGO_COLORS=()
if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != dumb ]]; then
    CYAN=$'\033[36m'; DIM=$'\033[2m'; BOLD=$'\033[1m'; RED=$'\033[31m'
    BUTTON=$'\033[30;42m'; RESET=$'\033[0m'
    LOGO_COLORS=($'\033[38;5;51m' $'\033[38;5;45m' $'\033[38;5;39m' $'\033[38;5;33m' $'\033[38;5;63m' $'\033[38;5;99m')
fi

LOGO=(
'██╗  ██╗ █████╗ ██████╗  ██████╗ ███╗   ███╗ ██████╗ '
'██║ ██╔╝██╔══██╗██╔══██╗██╔═══██╗████╗ ████║██╔═══██╗'
'█████╔╝ ███████║██║  ██║██║   ██║██╔████╔██║██║   ██║'
'██╔═██╗ ██╔══██║██║  ██║██║   ██║██║╚██╔╝██║██║   ██║'
'██║  ██╗██║  ██║██████╔╝╚██████╔╝██║ ╚═╝ ██║╚██████╔╝'
'╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝  ╚═════╝ ╚═╝     ╚═╝ ╚═════╝ ')

# The controlling terminal's width, else 80. The braces keep a missing tty quiet.
term_cols() {
    local cols
    cols="$({ stty size </dev/tty || stty size; } 2>/dev/null | cut -d' ' -f2 || true)"
    [[ "$cols" =~ ^[0-9]+$ ]] && printf '%s' "$cols" || printf 80
}

logo() {
    local i
    printf '\n'
    # A terminal too narrow for the block letters gets the name in bold instead.
    if [[ -t 1 ]] && (($(term_cols) <= 60)); then printf '  %sKADOMO MENU%s\n\n' "$BOLD" "$RESET"; return; fi
    for ((i=0; i<${#LOGO[@]}; i++)); do printf '%s%s%s\n' "${LOGO_COLORS[i]:-}" "${LOGO[i]}" "$RESET"; done
    printf '\n'
}

read_key() {
    local tail=""
    IFS= read -rsn1 KEY || exit 130
    if [[ "$KEY" == $'\033' ]]; then
        IFS= read -rsn2 -t 1 tail || true
        case "$tail" in
            '[A') KEY=up ;; '[B') KEY=down ;; '[C') KEY=right ;; '[D') KEY=left ;;
            *) KEY=escape ;;
        esac
    fi
    case "$KEY" in
        k) KEY=up ;; j) KEY=down ;; '') KEY=enter ;; ' ') KEY=space ;;
    esac
}

die() { printf '\n  %s✗ %s%s\n\n' "$RED" "$*" "$RESET" >&2; exit 1; }

# A path with the home folder shown as ~.
short_path() { case "$1" in "$HOME"/*) printf '~%s' "${1#"$HOME"}" ;; *) printf '%s' "$1" ;; esac; }

# A button label; the selected one is green, or bracketed without color.
button() {
    if (($2 == 0)); then printf '  %s  ' "$1"
    elif [[ -n "$BUTTON" ]]; then printf '%s  %s  %s' "$BUTTON" "$1" "$RESET"
    else printf '[ %s ]' "$1"; fi
}

# Two buttons. Returns 0 for the first, 1 for the second; Esc or q counts as the second.
confirm() {
    local first="$1" second="$2" cursor=0 one two
    while :; do
        if ((cursor == 0)); then one="$(button "$first" 1)"; two="$(button "$second" 0)"
        else one="$(button "$first" 0)"; two="$(button "$second" 1)"; fi
        printf '\r\033[2K  %s   %s\n\n\033[2K  %s←/→ toggle · Enter submit · y %s · n %s%s' "$one" "$two" "$DIM" "$first" "$second" "$RESET"
        read_key
        case "$KEY" in
            left|right) cursor=$((1-cursor)) ;;
            enter) printf '\n'; return "$cursor" ;;
            y|Y) printf '\n'; return 0 ;;
            n|N|escape|q|Q) printf '\n'; return 1 ;;
        esac
        printf '\r\033[2A'
    done
}

# Selects every item, or clears them all when every item is already selected.
toggle_all() {
    local i any_off=0
    for ((i=0; i<${#ITEM_ON[@]}; i++)); do ((ITEM_ON[i])) || any_off=1; done
    for ((i=0; i<${#ITEM_ON[@]}; i++)); do ITEM_ON[i]=$any_off; done
}

draw_checklist() {
    local cursor="$1" width="$2" i check
    printf '\033[2J\033[H'
    logo
    printf '  %s%s%s\n\n' "$BOLD" "$TITLE" "$RESET"
    for ((i=0; i<${#ITEM_LABEL[@]}; i++)); do
        check=" "; ((ITEM_ON[i])) && check=x
        if ((i == cursor)); then
            printf '%s > [%s] %-*s  %s%s\n' "$CYAN" "$check" "$width" "${ITEM_LABEL[i]}" "${ITEM_DETAIL[i]}" "$RESET"
        else
            printf '   [%s] %-*s  %s%s%s\n' "$check" "$width" "${ITEM_LABEL[i]}" "$DIM" "${ITEM_DETAIL[i]}" "$RESET"
        fi
    done
    printf '\n  %s↑/↓ or j/k move · Space toggle · a all/none · Enter review · q quit%s\n' "$DIM" "$RESET"
}

# The checklist. Returns 0 when Enter is pressed, 1 on q or Esc.
checklist() {
    local cursor=0 n=${#ITEM_LABEL[@]} i width=0
    for ((i=0; i<n; i++)); do ((${#ITEM_LABEL[i]} <= width)) || width=${#ITEM_LABEL[i]}; done
    while :; do
        draw_checklist "$cursor" "$width"
        read_key
        case "$KEY" in
            up) cursor=$(((cursor+n-1)%n)) ;;
            down) cursor=$(((cursor+1)%n)) ;;
            space) ITEM_ON[cursor]=$((1-ITEM_ON[cursor])) ;;
            a|A) toggle_all ;;
            enter) return 0 ;;
            q|Q|escape) return 1 ;;
        esac
    done
}

# Runs a command or function as one step: a dim "·" while it runs, then ✓ or ✗.
# Its output goes to LOG; a failed step shows the last lines of its own output.
# Failures are counted in FAILED, and the script keeps going.
run_step() {
    local label="$1" status=0 start
    shift
    start="$(wc -c < "$LOG" | tr -d ' ')"
    printf '  %s·%s %s\n' "$DIM" "$RESET" "$label"
    "$@" >>"$LOG" 2>&1 || status=$?
    printf '\033[1A\033[2K'
    if ((status == 0)); then
        printf '  %s✓%s %s\n' "$CYAN" "$RESET" "$label"
        return 0
    fi
    printf '  %s✗%s %s\n' "$RED" "$RESET" "$label"
    tail -c "+$((start+1))" "$LOG" | tail -n 6 | while IFS= read -r line; do printf '      %s%s%s\n' "$DIM" "$line" "$RESET"; done
    FAILED=$((FAILED+1))
}
