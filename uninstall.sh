#!/bin/bash
# Removes what ./install.sh set up. It finds what Kadomo put on this Mac, lists
# it, and removes what you leave checked once you confirm the review. Before
# anything is removed, the apps and services it is about to remove are quit
# and their login agents stopped. Run it from macOS's own Terminal: it stops
# before changing anything when run inside a terminal Kadomo installed. Run
# from zsh, it ends by starting a new zsh, so the prompt from before Kadomo
# is back once Starship is gone:
#   Kadomo Menu      the app, its command, the font it added, its config,
#                    history, and preferences
#   Configs          the configs Kadomo placed; the files they replaced are
#                    put back, and JankyBorders goes if an older Kadomo
#                    installed it
#   OmniWM           kadomo-omniwm and its menu entries; the border colors
#                    from before Kadomo come back, and OmniWM goes if Kadomo
#                    installed it (its settings stay)
#   AeroSpace from an older Kadomo
#                    Kadomo's build, its commands, login agents, and settings
#                    (Kadomo uses OmniWM only now); a regular AeroSpace you
#                    installed stays
#   Apps             the apps Kadomo installed with Homebrew (their data stays)
#   Moonlight Mouse Optimization
#                    the Moonlight profile and the login agent, and LinearMouse
#                    when Kadomo installed it and nothing else is set up in it
#   Developer tools  Kadomo's Starship prompt and VS Code colors, and the tools
#                    Kadomo installed
#   Theme manager    the theme commands and themes; btop, Kadomo Menu,
#                    VS Code, the wallpaper, and light/dark mode go back to
#                    what they were
#   Homebrew         when Kadomo installed it and nothing of yours is in it:
#                    Homebrew, its PATH block in ~/.zprofile, and the Xcode
#                    Command Line Tools if it added them (asks for your password)
# Anything that was on this Mac before Kadomo stays, and so does this checkout.
#
# Usage: ./uninstall.sh [--yes]
#   --yes   ask nothing, and remove everything found
#
# Runs on the Bash 3.2 that ships with macOS.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSUME_YES=0

source "$ROOT/lib/tui.sh"
source "$ROOT/apps/apps.sh"
source "$ROOT/developer/dev.sh"
source "$ROOT/homebrew/homebrew.sh"

case "${1:-}" in
    "") ;;
    --yes|-y) ASSUME_YES=1 ;;
    -h|--help) sed -n '2,36p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown option: $1 (try --help)" ;;
esac

[[ "$(uname -s)" == Darwin ]] || die "Kadomo is for macOS."
((EUID != 0)) || die "run this as your own user, not with sudo."

# The terminal app Kadomo installed (Ghostty or kitty) that this runs inside,
# or nothing. The uninstall quits and removes those apps, and quitting the one
# this runs in would end the uninstall halfway, so it has to run elsewhere.
kadomo_terminal_host() {
    local kind name entry app
    [[ -s "$APPS_MANIFEST" ]] || return 1
    while IFS='|' read -r kind name; do
        [[ "$kind" == cask ]] || continue
        case "$name" in ghostty|kitty) ;; *) continue ;; esac
        entry="$(app_entry cask "$name")" && app="$(app_path "$(app_field "$entry" 4)")" || continue
        runs_inside "$app" && { basename "$app" .app; return 0; }
    done <"$APPS_MANIFEST"
    return 1
}
if host_app="$(kadomo_terminal_host)"; then
    printf '\n  %s✗ This is running in %s, which Kadomo installed. Nothing was changed.%s\n\n' "$RED" "$host_app" "$RESET" >&2
    wrap_text 74 "The uninstaller quits and removes the apps Kadomo installed, $host_app included. Quitting $host_app would end this uninstall partway through and leave Kadomo half removed, and a running app cannot be removed anyway. Its shell also uses Kadomo's prompt and theme, which go during the uninstall." | sed 's/^/  /' >&2
    printf '\n  Run it from the Terminal app that comes with macOS instead:\n' >&2
    printf '    1. Open Terminal (Applications > Utilities > Terminal, or Spotlight: "Terminal")\n' >&2
    printf '    2. Run:  cd %q && ./uninstall.sh\n\n' "$ROOT" >&2
    exit 1
fi

# In the order they are removed. The Kadomo Menu uninstaller removes its whole
# config, so it goes first; the developer tools go before the theme manager,
# which turns the prompt off with theme-starship; the theme manager goes last,
# because a config the dotfiles put back may still carry its theme lines.
# Homebrew goes after them all: the others use it to remove what they installed.
COMPONENTS=(kadomo-menu dotfiles omniwm aerospace apps moonlight-mouse developer kadomo-theme-manager homebrew)
LABELS=("Kadomo Menu" "Configs" "OmniWM" "AeroSpace from an older Kadomo" "Apps" "Moonlight Mouse Optimization" "Developer tools" "Theme manager" "Homebrew")
# The parts whose uninstaller can stop what runs (--stop) before anything is removed.
# (AeroSpace's remover stops what runs itself, before it removes anything.)
STOPPABLE=" kadomo-menu dotfiles omniwm apps moonlight-mouse developer "

# Each part's uninstaller. Kadomo no longer ships AeroSpace: only its remover is left.
uninstaller_for() {
    case "$1" in
        aerospace) printf '%s' "$ROOT/omniwm/remove-aerospace.sh" ;;
        *) printf '%s' "$ROOT/$1/uninstall.sh" ;;
    esac
}

# The Homebrew names in a record, as people know them.
known_name() {
    case "$1" in
        temurin@25) printf 'Java 25' ;; node) printf 'Node.js' ;; rancher) printf 'Rancher Desktop' ;;
        visual-studio-code) printf 'VS Code' ;;
        starship|*/starship) printf 'Starship' ;; ghostty) printf 'Ghostty' ;; moonlight) printf 'Moonlight' ;;
        firefox) printf 'Firefox' ;; neovim) printf 'Neovim' ;; *) printf '%s' "$1" ;;
    esac
}
record_names() { # <record file>
    local kind name out=""
    [[ -s "$1" ]] || return 0
    while IFS='|' read -r kind name; do
        case "$kind" in formula|cask|script) out="${out:+$out, }$(known_name "$name")" ;; esac
    done <"$1"
    printf '%s' "$out"
}

detail_for() {
    local names
    case "$1" in
        kadomo-menu) printf 'the app, its command and font, config, history, and preferences' ;;
        dotfiles) printf 'the configs Kadomo placed; the files they replaced come back' ;;
        omniwm)
            if [[ -n "$(awk -F'|' '$1 == "cask"' "$STATE_DIR/omniwm-installed.txt" 2>/dev/null)" ]]; then
                printf 'OmniWM and its menu entries; its settings stay'
            else
                printf 'its menu entries; OmniWM stays, its border colors go back'
            fi
            ;;
        aerospace) printf "Kadomo's build, its commands and login agents; a regular AeroSpace you installed stays" ;;
        apps) names="$(record_names "$APPS_MANIFEST")"; printf '%s' "${names:-the apps Kadomo installed}" ;;
        moonlight-mouse) printf 'the Moonlight profile and login agent; LinearMouse if Kadomo installed it' ;;
        developer)
            names="$(record_names "$DEV_MANIFEST")"
            if dev_recorded "enabled|starship"; then names="Starship prompt off${names:+; $names}"; fi
            if dev_recorded "enabled|vscode"; then names="VS Code's Kadomo colors off${names:+; $names}"; fi
            printf '%s' "${names:-the tools Kadomo installed}"
            ;;
        kadomo-theme-manager) printf 'themes and theme-set; btop, VS Code, the wallpaper, and light/dark go back' ;;
        homebrew)
            names="Homebrew in $(hb_recorded prefix || true) and its PATH block"
            [[ "$(hb_recorded clt || true)" != added ]] || names="$names, and the Command Line Tools"
            printf '%s; it stays if you installed packages with it' "$names"
            ;;
    esac
}

# What is installed: each component's own uninstaller, asked for a dry run.
ITEM_COMPONENT=(); ITEM_LABEL=(); ITEM_DETAIL=(); ITEM_PLAN=(); ITEM_ON=()
[[ ! -t 1 ]] || printf '\n  %sChecking what Kadomo set up...%s' "$DIM" "$RESET"
for ((c=0; c<${#COMPONENTS[@]}; c++)); do
    component="${COMPONENTS[c]}"
    plan="$("$(uninstaller_for "$component")" --dry-run </dev/null 2>&1 || true)"
    [[ "$plan" != *"no $component installed"* ]] || continue
    plan="$(printf '%s\n' "$plan" | grep -v '^    would run:\|^Dry run:' || true)"
    detail="$(detail_for "$component")"
    # Nothing but Kadomo's record of it is left (removed by hand, say).
    if [[ -z "${plan//[[:space:]]/}" ]]; then plan="  -  Kadomo's record of it (nothing else is left)"; detail="only Kadomo's record of it is left"; fi
    ITEM_COMPONENT+=("$component"); ITEM_LABEL+=("${LABELS[c]}"); ITEM_DETAIL+=("$detail")
    ITEM_PLAN+=("$plan"); ITEM_ON+=(1)
done
[[ ! -t 1 ]] || printf '\r\033[2K'
N=${#ITEM_COMPONENT[@]}
if ((N == 0)); then
    printf '\n  Nothing to remove: Kadomo is not set up on this Mac.\n\n'
    exit 0
fi
LABEL_WIDTH=0
for ((i=0; i<N; i++)); do ((${#ITEM_LABEL[i]} <= LABEL_WIDTH)) || LABEL_WIDTH=${#ITEM_LABEL[i]}; done

item_on() { local i; for ((i=0; i<N; i++)); do [[ "${ITEM_COMPONENT[i]}" != "$1" ]] || ((ITEM_ON[i] == 0)) || return 0; done; return 1; }

# Whether removing the developer tools uninstalls Java, which asks for your password.
removes_java() {
    local i
    for ((i=0; i<N; i++)); do
        [[ "${ITEM_COMPONENT[i]}" == developer ]] && ((ITEM_ON[i])) && grep -qx 'cask|temurin@25' "$DEV_MANIFEST" 2>/dev/null && return 0
    done
    return 1
}

# Why removing what is selected needs your Mac password, one reason per line,
# or nothing. Each is something in a system folder, which only an
# administrator can change.
password_reasons() {
    local prefix
    removes_java && echo "Java 25 (Temurin) is in /Library/Java/JavaVirtualMachines"
    if item_on developer && grep -qx 'cask|rancher' "$DEV_MANIFEST" 2>/dev/null; then
        echo "Rancher Desktop's uninstaller removes /opt/rancher-desktop"
    fi
    if item_on homebrew; then
        prefix="$(hb_recorded prefix || true)"
        echo "Homebrew's folder, ${prefix:-/opt/homebrew}, was made by its installer as an administrator"
        if [[ "$(hb_recorded clt || true)" == added && -d "$CLT_DIR" ]]; then
            echo "the Xcode Command Line Tools Homebrew added are in $CLT_DIR"
        fi
    fi
    return 0
}

# Asks for your password once, before anything is removed, saying why, and
# keeps it fresh in the background so no step asks again halfway through.
SUDO_KEEPALIVE=""
ask_password() {
    local reasons
    reasons="$(password_reasons)"
    [[ -n "$reasons" ]] || return 0
    if ! sudo -n true 2>/dev/null; then
        # Without a terminal, each part asks (or says it cannot) on its own.
        { : </dev/tty; } 2>/dev/null || return 0
        printf '  %sYour Mac password is needed%s
' "$BOLD" "$RESET"
        printf '  Some of what you chose to remove is in system folders, which only an
  administrator can change:
'
        printf '%s
' "$reasons" | while IFS= read -r line; do wrap_text 70 "$line" | sed '1s/^/    • /; 1!s/^/      /'; done
        printf '  It is asked once, now, and used only to remove these. Kadomo does not keep it.

'
        if ! sudo -v -p "  Password for $(id -un): " </dev/tty; then
            printf '
  Nothing was changed. Without your password these cannot be removed;
  run ./uninstall.sh again and leave them unchecked to remove the rest.

'
            exit 1
        fi
        printf '
'
    fi
    ( while kill -0 "$$" 2>/dev/null; do sudo -n true 2>/dev/null; sleep 30; done ) &
    SUDO_KEEPALIVE=$!
}
stop_keepalive() { [[ -z "$SUDO_KEEPALIVE" ]] || kill "$SUDO_KEEPALIVE" 2>/dev/null || true; SUDO_KEEPALIVE=""; }

selected_count() { local i n=0; for ((i=0; i<N; i++)); do n=$((n+ITEM_ON[i])); done; printf '%s' "$n"; }

banner() {
    logo
    printf '  %sUninstall Kadomo%s\n\n' "$BOLD" "$RESET"
    printf '  %sFound%s     %s parts of Kadomo on this Mac\n' "$DIM" "$RESET" "$N"
    printf '  %sSelected%s  %s of %s\n\n' "$DIM" "$RESET" "$(selected_count)" "$N"
}

draw_list() {
    local cursor="$1" i check
    clear_screen; banner
    for ((i=0; i<N; i++)); do
        check=' '; ((ITEM_ON[i] == 0)) || check=x
        if ((i == cursor)); then printf '%s > [%s] %-*s  %s%s\n' "$CYAN" "$check" "$LABEL_WIDTH" "${ITEM_LABEL[i]}" "${ITEM_DETAIL[i]}" "$RESET"
        else printf '   [%s] %-*s  %s%s%s\n' "$check" "$LABEL_WIDTH" "${ITEM_LABEL[i]}" "$DIM" "${ITEM_DETAIL[i]}" "$RESET"; fi
    done
    printf '\n  %s↑/↓ move · Space toggle · a all/none · d details · Enter review · q quit%s\n' "$DIM" "$RESET"
}

# Each selected part's plan, from its own uninstaller; just one part when given.
details() {
    local i
    clear_screen; logo
    printf '  %sWhat will be removed or put back%s\n' "$BOLD" "$RESET"
    for ((i=0; i<N; i++)); do
        if [[ -n "${1:-}" ]]; then ((i == $1)) || continue; else ((ITEM_ON[i])) || continue; fi
        printf '\n  %s%s%s\n' "$BOLD" "${ITEM_LABEL[i]}" "$RESET"
        printf '%s\n' "${ITEM_PLAN[i]}" | sed "s/^/  /"
    done
    pause "${2:-list}"
}

# Returns 0 to review, 1 to quit.
choose() {
    local cursor=0 i all
    while :; do
        draw_list "$cursor"
        read_key
        case "$KEY" in
            up) cursor=$(((cursor+N-1)%N)) ;;
            down) cursor=$(((cursor+1)%N)) ;;
            space) ITEM_ON[cursor]=$((1-ITEM_ON[cursor])) ;;
            a|A) all=1; for ((i=0; i<N; i++)); do ((ITEM_ON[i])) || all=0; done
                 for ((i=0; i<N; i++)); do ITEM_ON[i]=$((1-all)); done ;;
            d|D|p|P) details "$cursor" ;;
            enter) return 0 ;;
            q|Q|escape) return 1 ;;
        esac
    done
}

# Returns 0 to remove.
review() {
    local i width names=() back=() answer fields=() kept=0 reasons
    width=$(($(term_cols) - 22)); ((width <= 64)) || width=64; ((width >= 30)) || width=30
    for ((i=0; i<N; i++)); do
        if ((ITEM_ON[i] == 0)); then kept=$((kept+1)); continue; fi
        names+=("${ITEM_LABEL[i]}")
        case "${ITEM_COMPONENT[i]}" in
            dotfiles) back+=("the configs Kadomo replaced") ;;
            kadomo-theme-manager) back+=("btop's theme" "the wallpaper" "light/dark mode") ;;
            developer)
                dev_recorded "enabled|starship" && back+=("your .zshrc")
                dev_recorded "enabled|vscode" && back+=("VS Code's color theme")
                ;;
        esac
    done
    fields+=("Remove${TAB}$(wrap_list "$width" "${names[@]}")")
    ((${#back[@]} == 0)) || fields+=("Put back${TAB}$(wrap_list "$width" "${back[@]}")")
    fields+=("First${TAB}$(wrap_list "$width" "the apps and services being removed are quit" "their login agents stopped")")
    reasons="$(password_reasons)"
    if [[ -n "$reasons" ]]; then
        fields+=("Asks you${TAB}$(wrap_list "$width" "your Mac password, once, right after you confirm" "it removes things in system folders")")
    fi
    fields+=("Stays${TAB}$(wrap_list "$width" "anything that was here before Kadomo" "each app's own data" "this checkout")")
    ((kept == 0)) || fields+=("Not selected${TAB}$kept $( ((kept == 1)) && echo part || echo parts) (left installed)")
    while :; do
        clear_screen; logo
        printf "  Let's remove Kadomo...\n\n"
        summary_table "${fields[@]}"
        printf '\n  %sDoes this look right? This cannot be undone.%s\n\n' "$CYAN" "$RESET"
        buttons "Yes, remove" "No, change it" && answer=0 || answer=$?
        case "$answer" in
            0) return 0 ;;
            3) details "" review ;;
            *) return 1 ;;
        esac
    done
}

if ((ASSUME_YES == 0)); then
    [[ -t 0 && -t 1 ]] || die "run this in a terminal, or pass --yes."
    # Removing cannot be undone, so the Yes button is red.
    BUTTON="$DANGER"
    while :; do
        choose || { clear_screen; printf '\n  Nothing changed.\n\n'; exit 0; }
        (($(selected_count))) || continue
        review && break
    done
    clear_screen; logo
    printf '  Removing Kadomo...\n\n'
else
    printf '\n  %sUninstalling Kadomo%s\n\n' "$BOLD" "$RESET"
fi

# Whether the zsh this was started from runs Kadomo's Starship prompt (or gets
# brew from Kadomo's ~/.zprofile block) and this uninstall takes that away.
# That shell keeps calling starship at every prompt after it is gone, and a
# script cannot change the shell that started it, so the end starts a new one.
shell_changes=0
if item_on developer || item_on kadomo-theme-manager; then
    [[ ! -d "${KADOMO_CONFIG_DIR:-$HOME/.config/kadomo}/starship" ]] || shell_changes=1
fi
! item_on homebrew || shell_changes=1

ask_password

STEP_LOG="$(mktemp "${TMPDIR:-/tmp}/kadomo-uninstall.XXXXXX")"
trap 'stop_tail; stop_keepalive' EXIT
failed=()
todos=()

# Everything that runs stops before anything is removed: each selected part's
# uninstaller quits its apps and stops its login agents (--stop), in the order
# they are removed. One that cannot stop something says so; removing goes on.
stop_selected() {
    local i component args status=0
    for ((i=0; i<N; i++)); do
        ((ITEM_ON[i])) || continue
        component="${ITEM_COMPONENT[i]}"
        [[ "$STOPPABLE" == *" $component "* ]] || continue
        args=(--stop)
        [[ "$component" != moonlight-mouse ]] || args=(--yes --stop)
        "$(uninstaller_for "$component")" "${args[@]}" || { echo "  !  ${ITEM_LABEL[i]}: could not stop everything" >&2; status=1; }
    done
    return "$status"
}
step "Stopping the apps and services being removed" stop_selected || failed+=("Stopping the apps and services")
while IFS= read -r line; do [[ -z "$line" ]] || todos+=("$line"); done < <(step_todos)

for ((i=0; i<N; i++)); do
    ((ITEM_ON[i])) || continue
    component="${ITEM_COMPONENT[i]}"; args=()
    # Both remove what Kadomo installed without asking again: the review was the question.
    case "$component" in kadomo-menu|moonlight-mouse) args=(--yes) ;; esac
    how=step
    # Uninstalling Java asks for your password, so it runs in the open.
    if [[ "$component" == developer ]] && ((ASSUME_YES == 0)) && removes_java; then how=step_open; fi
    # So does removing Homebrew.
    if [[ "$component" == homebrew && -t 0 ]]; then how=step_open; fi
    "$how" "${ITEM_LABEL[i]}" "$(uninstaller_for "$component")" ${args[@]+"${args[@]}"} || failed+=("${ITEM_LABEL[i]}")
    while IFS= read -r line; do [[ -z "$line" ]] || todos+=("$line"); done < <(step_todos)
done

printf '\n'
if ((${#failed[@]})); then
    printf '  %s✗ %s of the steps failed:%s %s\n' "$RED" "${#failed[@]}" "$RESET" "$(IFS=';'; echo "${failed[*]}" | sed 's/;/; /g')"
    printf '  %sRun ./uninstall.sh again to retry; what is gone already is skipped.%s\n' "$DIM" "$RESET"
else
    printf '  %s✓ Kadomo is removed%s\n' "$CYAN" "$RESET"
fi
printf '\n  %sLog%s       %s\n' "$DIM" "$RESET" "$(short_path "$STEP_LOG")"
printf '  %sKept%s      this checkout, %s; delete it yourself if you want it gone\n' "$DIM" "$RESET" "$(short_path "$ROOT")"
if ((${#todos[@]})); then
    printf '\n  %sStill needs you%s\n' "$BOLD" "$RESET"
    for ((i=0; i<${#todos[@]}; i++)); do
        wrap_text 74 "${todos[i]}" | sed "1s/^/  $((i+1)). /; 1!s/^/     /"
    done
fi
printf '\n'

# The zsh this was run from still has Starship's prompt hooks loaded, and with
# Starship gone each prompt breaks. Sourcing .zshrc from here would not help: a
# script runs in a child process and cannot change the shell that started it.
# So, run from zsh in a terminal, this hands the window to a new zsh that reads
# your startup files as they are now, with the prompt from before Kadomo.
parent_shell="$(ps -o comm= -p "$PPID" 2>/dev/null | tr -d ' ' || true)"
if ((shell_changes)) && [[ -t 0 && -t 1 && "${parent_shell##*/}" == *zsh ]] && zsh_bin="$(command -v zsh)"; then
    printf '  %sStarting a new zsh so your prompt from before Kadomo is back (exit returns to the old shell; just close this window instead).%s\n\n' "$DIM" "$RESET"
    trap - EXIT
    stop_tail
    # exec keeps this process id, so the keepalive would never see it end.
    stop_keepalive
    exec "$zsh_bin" -l
fi
((${#failed[@]} == 0))
