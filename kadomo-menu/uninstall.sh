#!/bin/bash
# Removes everything install.sh put on this Mac, plus what the app itself
# leaves behind: the launch-at-login item, KadomoMenu.app, the kadomo-menu
# command, the font files install.sh added, config and themes, usage history and sockets, preferences, caches,
# saved state, logs, and the build cache. Your checkout is never touched.
#
# Usage: ./uninstall.sh [--yes]
#   --yes   skip the checklist and review, and remove every item found
#
# Runs on the Bash 3.2 that ships with macOS.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="KadomoMenu"
BUNDLE_ID="tech.kadomo.menu"
PREFIX="${PREFIX:-$HOME/Applications}"
BIN="$HOME/.local/bin/kadomo-menu"
TITLE="Uninstall"
ASSUME_YES=0
FAILED=0
LOG="$(mktemp "${TMPDIR:-/tmp}/kadomo-menu-uninstall.XXXXXX")"

source "$ROOT/lib/tui.sh"

usage() {
    cat <<EOF
Usage: ./uninstall.sh [--yes]

  --yes     Skip the checklist and review; remove every item found.
  --help    Show this help.

Only items that are actually present are listed. Space toggles an item,
Enter reviews the choices, and q quits without changes.
EOF
}

# Expands a leading ~ the way the app does.
expand_home() {
    case "$1" in
        "~") printf '%s' "$HOME" ;;
        "~/"*) printf '%s/%s' "$HOME" "${1#~/}" ;;
        *) printf '%s' "$1" ;;
    esac
}

# Where the app keeps config, state, and its socket. These follow the app's own rules.
config_dir() {
    if [[ -n "${KADOMO_MENU_CONFIG_DIR:-}" ]]; then expand_home "$KADOMO_MENU_CONFIG_DIR"
    elif [[ -n "${XDG_CONFIG_HOME:-}" ]]; then expand_home "$XDG_CONFIG_HOME/kadomo-menu"
    else printf '%s' "$HOME/.config/kadomo-menu"; fi
}

state_dir() {
    if [[ -n "${KADOMO_MENU_STATE_DIR:-}" ]]; then expand_home "$KADOMO_MENU_STATE_DIR"
    else printf '%s' "$HOME/Library/Application Support/kadomo-menu"; fi
}

running() { pgrep -x "$APP_NAME" >/dev/null 2>&1; }

# The installed copies, without duplicates. The first one is the launcher we talk to.
find_bundles() {
    local app seen=""
    BUNDLES=()
    for app in "$PREFIX/$APP_NAME.app" "$HOME/Applications/$APP_NAME.app" "/Applications/$APP_NAME.app"; do
        [[ -d "$app" && "$seen" != *"|$app|"* ]] || continue
        seen="$seen|$app|"
        BUNDLES+=("$app")
    done
    LAUNCHER_APP=""; LAUNCHER_BIN=""
    if [[ ${#BUNDLES[@]} -gt 0 ]]; then
        LAUNCHER_APP="${BUNDLES[0]}"
        LAUNCHER_BIN="$LAUNCHER_APP/Contents/MacOS/$APP_NAME"
    fi
}

# True when the command symlink points into an app bundle, so a file we did not make is left alone.
command_linked() { [[ -L "$BIN" && "$(readlink "$BIN")" == *"/$APP_NAME.app/"* ]]; }

# Removes a path, refusing the home folder, the root, and empty paths.
remove_path() {
    case "$1" in
        ""|/|"$HOME"|"$HOME/") echo "refusing to remove '$1'"; return 1 ;;
    esac
    if [[ -e "$1" || -L "$1" ]]; then rm -rf -- "$1"; fi
}

wait_for_launcher() {
    local i
    for ((i=0; i<40; i++)); do
        "$LAUNCHER_BIN" status >/dev/null 2>&1 && return 0
        sleep 0.25
    done
    echo "the launcher did not answer on its socket"
    return 1
}

quit_launcher() {
    local i
    running || return 0
    [[ -z "$LAUNCHER_BIN" ]] || "$LAUNCHER_BIN" quit >/dev/null 2>&1 || true
    for ((i=0; i<20; i++)); do running || return 0; sleep 0.25; done
    pkill -x "$APP_NAME" || true
    sleep 0.5
    ! running
}

# Turns the launch-at-login item off while the app can still answer, then quits it.
# The app must be running for that, so a stopped copy is started in the background first.
# A login item that cannot be turned off is reported, and the app is quit regardless.
stop_launcher() {
    local status=0
    if [[ -n "$LAUNCHER_BIN" ]]; then
        running || open -g "$LAUNCHER_APP"
        if ! { wait_for_launcher && "$LAUNCHER_BIN" login off; }; then
            echo "could not turn off launch at login. Remove KadomoMenu in System Settings › General › Login Items."
            status=1
        fi
    fi
    quit_launcher || status=1
    return "$status"
}

remove_command() {
    command_linked || return 0
    rm -f -- "$BIN"
}

remove_bundles() {
    local app failed=0
    for app in "${BUNDLES[@]}"; do
        if [[ -e "$app" ]] && ! rm -rf -- "$app"; then
            echo "could not remove $app. Remove it with: sudo rm -rf \"$app\""
            failed=1
        fi
    done
    return "$failed"
}

# Only the files install.sh recorded, read at scan time, before the state dir can go.
remove_fonts() {
    local name
    for name in "${FONT_FILES[@]}"; do
        case "$name" in */*|""|.|..) continue ;; esac
        rm -f -- "$HOME/Library/Fonts/$name"
    done
    rm -f -- "$FONT_MANIFEST"
}

remove_leftovers() {
    local path
    for path in "${LEFTOVERS[@]}"; do remove_path "$path"; done
}

# Clears the Accessibility and Automation grants macOS recorded for this app's bundle ID.
reset_permissions() {
    tccutil reset All "$BUNDLE_ID" >/dev/null 2>&1 || true
}

# Adds a checklist row. When the row is selected, its function runs as a step with its argument.
add_item() {
    ITEM_LABEL+=("$1"); ITEM_DETAIL+=("$2"); ITEM_ON+=(1); ITEM_FN+=("$3"); ITEM_ARG+=("${4:-}")
}

scan() {
    local config state count path build_cache detail
    find_bundles
    config="$(config_dir)"; state="$(state_dir)"
    build_cache="$HOME/Library/Developer/$APP_NAME"
    LEFTOVERS=(
        "$HOME/Library/Preferences/$BUNDLE_ID.plist"
        "$HOME/Library/Caches/$BUNDLE_ID"
        "$HOME/Library/Saved Application State/$BUNDLE_ID.savedState"
        "$HOME/Library/HTTPStorages/$BUNDLE_ID"
        "$HOME/Library/Logs/kadomo-menu"
    )
    ITEM_LABEL=(); ITEM_DETAIL=(); ITEM_ON=(); ITEM_FN=(); ITEM_ARG=()
    FONT_MANIFEST="$state/installed-fonts.txt"
    FONT_FILES=()
    if [[ -f "$FONT_MANIFEST" ]]; then
        while IFS= read -r path; do
            [[ -n "$path" && -e "$HOME/Library/Fonts/$path" ]] && FONT_FILES+=("$path")
        done <"$FONT_MANIFEST"
    fi

    if [[ -n "$LAUNCHER_APP" ]] || running; then
        add_item "Stop the launcher" "quits it and turns off launch at login" stop_launcher
    fi
    if command_linked; then
        add_item "kadomo-menu command" "$(short_path "$BIN")" remove_command
    fi
    if [[ ${#BUNDLES[@]} -gt 0 ]]; then
        detail=""
        for path in "${BUNDLES[@]}"; do detail="${detail:+$detail, }$(short_path "$path")"; done
        add_item "KadomoMenu.app" "$detail" remove_bundles
    fi
    if [[ ${#FONT_FILES[@]} -gt 0 ]]; then
        add_item "JetBrainsMono Nerd Font" "${#FONT_FILES[@]} file(s) install.sh added to ~/Library/Fonts" remove_fonts
    fi
    if [[ -e "$config" ]]; then
        add_item "Config and themes" "$(short_path "$config") · your edits are deleted" remove_path "$config"
    fi
    if [[ -e "$state" ]]; then
        add_item "Usage history and socket" "$(short_path "$state")" remove_path "$state"
    fi
    count=0
    for path in "${LEFTOVERS[@]}"; do [[ -e "$path" ]] && count=$((count+1)); done
    if ((count)); then
        add_item "Preferences, caches, logs" "$count item(s) under ~/Library" remove_leftovers
    fi
    if [[ -e "$build_cache" ]]; then
        add_item "Build cache" "$(short_path "$build_cache")" remove_path "$build_cache"
    fi
    if [[ ${#BUNDLES[@]} -gt 0 ]]; then
        add_item "Privacy grants" "Accessibility and Automation for $BUNDLE_ID" reset_permissions
    fi
}

# Shows what will be removed. The login item is only unregistered when the app is stopped first.
review() {
    local i stop_selected=0 app_selected=0
    for ((i=0; i<${#ITEM_LABEL[@]}; i++)); do
        ((ITEM_ON[i])) || continue
        [[ "${ITEM_FN[i]}" != stop_launcher ]] || stop_selected=1
        [[ "${ITEM_FN[i]}" != remove_bundles ]] || app_selected=1
    done
    printf '\033[2J\033[H'
    logo
    printf '  %sReview%s\n\n' "$BOLD" "$RESET"
    for ((i=0; i<${#ITEM_LABEL[@]}; i++)); do
        ((ITEM_ON[i])) || continue
        printf '  %s·%s %s  %s%s%s\n' "$CYAN" "$RESET" "${ITEM_LABEL[i]}" "$DIM" "${ITEM_DETAIL[i]}" "$RESET"
    done
    if ((app_selected && !stop_selected)); then
        printf '\n  %sThe launch-at-login item stays until you turn it off in System Settings › General › Login Items.%s\n' "$DIM" "$RESET"
    fi
    printf '\n  %sThis cannot be undone. Your checkout of this repo is not touched.%s\n\n' "$DIM" "$RESET"
    confirm "Yes, remove" "No, change it"
}

finish() {
    if ((FAILED)); then
        printf '\n  %s✗ %d step(s) failed.%s Full output: %s\n\n' "$RED" "$FAILED" "$RESET" "$LOG"
        exit 1
    fi
    rm -f -- "$LOG"
    printf '\n  %s✓ Kadomo Menu is removed%s\n\n' "$CYAN" "$RESET"
    printf '  %sThe checkout at %s was left in place. Delete it yourself if you want it gone.%s\n\n' "$DIM" "$(short_path "$ROOT")" "$RESET"
}

for arg in "$@"; do
    case "$arg" in
        --yes|-y) ASSUME_YES=1 ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown option: $arg (try --help)" ;;
    esac
done

[[ "$(uname -s)" == Darwin ]] || die "Kadomo Menu is for macOS."
((EUID != 0)) || die "run this as your own user, not with sudo."

scan
if [[ ${#ITEM_LABEL[@]} -eq 0 ]]; then
    printf '\n  Nothing to remove. Kadomo Menu is not installed.\n\n'
    exit 0
fi

if ((ASSUME_YES == 0)); then
    [[ -t 0 ]] || die "run this in a terminal, or pass --yes."
    while :; do
        checklist || { printf '\n  Nothing changed.\n\n'; exit 0; }
        selected=0
        for ((i=0; i<${#ITEM_ON[@]}; i++)); do selected=$((selected+ITEM_ON[i])); done
        ((selected)) || { printf '\n  Nothing selected. Nothing changed.\n\n'; exit 0; }
        review && break
    done
fi

printf '\n'
for ((i=0; i<${#ITEM_LABEL[@]}; i++)); do
    ((ITEM_ON[i])) || continue
    run_step "${ITEM_LABEL[i]}" "${ITEM_FN[i]}" "${ITEM_ARG[i]}"
done
finish
