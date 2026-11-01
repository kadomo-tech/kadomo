#!/bin/bash
# Terminal UI for Kadomo's install.sh and uninstall.sh: colors, the logo, keys,
# buttons, a Field/Value table, and steps that each end in one ✓ or ✗ line
# while their output goes to a log. Plain Bash 3.2 and ANSI escapes.

TAB=$'\t'; ESC=$'\033'
CYAN=""; DIM=""; BOLD=""; RED=""; BUTTON=""; DANGER=""; RESET=""; LOGO_COLORS=()
if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != dumb ]]; then
    CYAN=$'\033[36m'; DIM=$'\033[2m'; BOLD=$'\033[1m'; RED=$'\033[31m'
    BUTTON=$'\033[30;42m'; DANGER=$'\033[97;41m'; RESET=$'\033[0m'
    LOGO_COLORS=($'\033[38;5;51m' $'\033[38;5;45m' $'\033[38;5;39m' $'\033[38;5;33m' $'\033[38;5;63m' $'\033[38;5;99m')
fi

LOGO=(
'██╗  ██╗ █████╗ ██████╗  ██████╗ ███╗   ███╗ ██████╗ '
'██║ ██╔╝██╔══██╗██╔══██╗██╔═══██╗████╗ ████║██╔═══██╗'
'█████╔╝ ███████║██║  ██║██║   ██║██╔████╔██║██║   ██║'
'██╔═██╗ ██╔══██║██║  ██║██║   ██║██║╚██╔╝██║██║   ██║'
'██║  ██╗██║  ██║██████╔╝╚██████╔╝██║ ╚═╝ ██║╚██████╔╝'
'╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝  ╚═════╝ ╚═╝     ╚═╝ ╚═════╝ ')
LOGO_WIDTH=54

# The controlling terminal's size, else stdin's; the braces quiet a missing tty.
term_size() { { stty size </dev/tty || stty size; } 2>/dev/null || true; }
term_rows() { local size; size="$(term_size)"; size="${size%% *}"; [[ "$size" =~ ^[0-9]+$ ]] && printf '%s' "$size" || printf 24; }
term_cols() { local size; size="$(term_size)"; size="${size##* }"; [[ "$size" =~ ^[0-9]+$ ]] && printf '%s' "$size" || printf 80; }

clear_screen() { [[ ! -t 1 ]] || printf '\033[2J\033[H'; }

# The logo, one shade per row; a terminal too narrow for it gets the name in bold.
logo() {
    local i
    printf '\n'
    if [[ -t 1 ]] && (($(term_cols) <= LOGO_WIDTH + 2)); then printf '  %sKADOMO%s\n\n' "$BOLD" "$RESET"; return; fi
    for ((i=0; i<${#LOGO[@]}; i++)); do printf '%s%s%s\n' "${LOGO_COLORS[i]:-}" "${LOGO[i]}" "$RESET"; done
    printf '\n'
}

read_key() {
    local tail=""
    IFS= read -rsn1 KEY </dev/tty || exit 130
    if [[ "$KEY" == $'\033' ]]; then
        IFS= read -rsn2 -t 1 tail </dev/tty || true
        case "$tail" in '[A') KEY=up ;; '[B') KEY=down ;; '[C') KEY=right ;; '[D') KEY=left ;; *) KEY=escape ;; esac
    fi
    case "$KEY" in k) KEY=up ;; j) KEY=down ;; h) KEY=left ;; l) KEY=right ;; '') KEY=enter ;; ' '|x|X) KEY=space ;; esac
}

pause() { printf '\n  %sPress any key to go back to the %s...%s' "$DIM" "${1:-list}" "$RESET"; IFS= read -rsn1 KEY </dev/tty || exit 130; }

die() { printf '\n  %s✗ %s%s\n\n' "$RED" "$*" "$RESET" >&2; exit 1; }

# A path with the home folder shown as ~.
short_path() { case "$1" in "$HOME"/*) printf '~%s' "${1#"$HOME"}" ;; *) printf '%s' "$1" ;; esac; }

# A button label; the selected one is green (red for a removal), or bracketed without color.
button() {
    if (($2 == 0)); then printf '  %s  ' "$1"
    elif [[ -n "$BUTTON" ]]; then printf '%s  %s  %s' "$BUTTON" "$1" "$RESET"
    else printf '[ %s ]' "$1"; fi
}

# Two buttons. Returns 0 for the first, 1 for the second (also Esc and q), and
# 3 for d, which shows the details.
buttons() {
    local first="$1" second="$2" cursor=0 one two
    while :; do
        if ((cursor == 0)); then one="$(button "$first" 1)"; two="$(button "$second" 0)"
        else one="$(button "$first" 0)"; two="$(button "$second" 1)"; fi
        printf '\r\033[2K  %s   %s\n\n\033[2K  %s←/→ choose · Enter submit · y %s · n %s · d details%s' \
            "$one" "$two" "$DIM" "$first" "$second" "$RESET"
        read_key
        case "$KEY" in
            left|right|$'\t') cursor=$((1-cursor)) ;;
            enter) printf '\n'; return "$cursor" ;;
            y|Y) printf '\n'; return 0 ;;
            n|N|q|Q|escape) printf '\n'; return 1 ;;
            d|D) printf '\n'; return 3 ;;
        esac
        printf '\r\033[2A'
    done
}

hline() { printf "%${1}s" '' | sed 's/ /─/g'; }

# A two-column table. Each argument is "field<TAB>value"; newlines in a value add lines.
summary_table() {
    local row field line fw=5 vw=5
    for row in "$@"; do
        field="${row%%"$TAB"*}"; ((${#field} <= fw)) || fw=${#field}
        while IFS= read -r line; do ((${#line} <= vw)) || vw=${#line}; done <<<"${row#*"$TAB"}"
    done
    printf '  %s┌%s┬%s┐%s\n' "$DIM" "$(hline $((fw+2)))" "$(hline $((vw+2)))" "$RESET"
    for row in "$@"; do
        field="${row%%"$TAB"*}"
        while IFS= read -r line; do
            printf '  %s│%s %s%-*s%s %s│%s %-*s %s│%s\n' "$DIM" "$RESET" "$BOLD" "$fw" "$field" "$RESET" "$DIM" "$RESET" "$vw" "$line" "$DIM" "$RESET"
            field=""
        done <<<"${row#*"$TAB"}"
    done
    printf '  %s└%s┴%s┘%s\n' "$DIM" "$(hline $((fw+2)))" "$(hline $((vw+2)))" "$RESET"
}

# Joins its arguments with ", ", wrapping lines at WIDTH characters.
wrap_list() {
    local width="$1" item line="" out=""; shift
    for item in "$@"; do
        if [[ -n "$line" ]] && ((${#line} + ${#item} + 2 > width)); then out="$out$line,"$'\n'; line="$item"
        else line="${line:+$line, }$item"; fi
    done
    printf '%s%s' "$out" "$line"
}

# Wraps text at WIDTH characters.
wrap_text() { printf '%s\n' "$2" | fold -s -w "$1" | sed 's/ *$//'; }

# --- steps ---------------------------------------------------------------------

# Each step prints one ✓ or ✗ line; its output goes to STEP_LOG. While a step
# runs, the last lines of its output show dimmed under it.
STEP_LOG=""; STEP_START=0; TAIL_PID=""; TAIL_LINES=6

start_tail() {
    [[ -n "$CYAN" ]] || return 0
    local i width; width="$(term_cols)"
    ((width > 20)) || width=80
    # Make room first, so the saved cursor position survives scrolling.
    for ((i=0; i<TAIL_LINES; i++)); do printf '\n'; done
    printf '%s[%sA%s7%s[?25l' "$ESC" "$TAIL_LINES" "$ESC" "$ESC"
    (
        while kill -0 "$$" 2>/dev/null; do
            out="${ESC}8"; i=0
            while IFS= read -r line; do
                line="${line//$'\r'/}"
                out="$out${ESC}[2K$DIM    → ${line:0:$((width-8))}$RESET"$'\n'; i=$((i+1))
            done < <(tail -c "+$((STEP_START+1))" "$STEP_LOG" 2>/dev/null | tail -n "$TAIL_LINES")
            for ((; i<TAIL_LINES; i++)); do out="$out${ESC}[2K"$'\n'; done
            printf '%s' "$out"; sleep 0.2
        done
    ) &
    TAIL_PID=$!
}

stop_tail() {
    [[ -n "$TAIL_PID" ]] || return 0
    kill "$TAIL_PID" 2>/dev/null || true; wait "$TAIL_PID" 2>/dev/null || true
    TAIL_PID=""
    printf '%s8%s[J%s[?25h' "$ESC" "$ESC" "$ESC"
}

# The ✓ or ✗ line; a failed step shows the last lines of its own output.
step_result() {
    local label="$1" status="$2" line
    if ((status == 0)); then printf '  %s✓%s %s\n' "$CYAN" "$RESET" "$label"; return 0; fi
    printf '  %s✗%s %s\n' "$RED" "$RESET" "$label"
    tail -c "+$((STEP_START+1))" "$STEP_LOG" | grep -v '^ *$\|^== ' | tail -n 6 | while IFS= read -r line; do
        printf '      %s%s%s\n' "$DIM" "$line" "$RESET"
    done
}

# Runs a command as one step, its output in the log. Returns its status.
step() {
    local label="$1" status=0
    shift
    STEP_START="$(wc -c <"$STEP_LOG" | tr -d ' ')"
    printf '\n== %s\n' "$label" >>"$STEP_LOG"
    [[ -z "$CYAN" ]] || printf '  %s·%s %s\n' "$DIM" "$RESET" "$label"
    start_tail
    "$@" </dev/null >>"$STEP_LOG" 2>&1 || status=$?
    stop_tail
    [[ -z "$CYAN" ]] || printf '%s[1A\r%s[2K' "$ESC" "$ESC"
    step_result "$label" "$status"
    return "$status"
}

# Runs a command that may ask you something (your password, or yes or no) in
# the open: its output shows as it comes, and goes to the log too.
step_open() {
    local label="$1" status=0
    shift
    STEP_START="$(wc -c <"$STEP_LOG" | tr -d ' ')"
    printf '\n== %s\n' "$label" >>"$STEP_LOG"
    printf '  %s▸%s %s\n' "$CYAN" "$RESET" "$label"
    "$@" 2>&1 | tee -a "$STEP_LOG" || status=$?
    step_result "$label" "$status"
    return "$status"
}

# The "Still needs you" items the last step printed, one per line.
step_todos() {
    tail -c "+$((STEP_START+1))" "$STEP_LOG" | awk '
        /^  Still needs you:/ { on = 1; next }
        on && /^  [0-9]+\. / { if (item != "") print item; sub(/^  [0-9]+\. /, ""); item = $0; next }
        on && /^     [^ ]/ { sub(/^ +/, ""); item = item " " $0; next }
        { if (item != "") print item; item = ""; on = 0 }
        END { if (item != "") print item }'
}
