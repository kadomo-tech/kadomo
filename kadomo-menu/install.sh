#!/bin/bash
# Installs Kadomo Menu from the prebuilt app that ships in this repo, in
# release/ (one build for Apple silicon and Intel, macOS 14 or later). It checks
# the zip against a SHA-256, puts KadomoMenu.app in ~/Applications, links the
# kadomo-menu command into ~/.local/bin, and starts the launcher. No Xcode or
# compiler is needed. Your config in ~/.config/kadomo-menu is never touched.
#
# Usage: ./install.sh [--yes] [--zip PATH]
#   --yes         skip the checklist and review, and install the defaults
#   --zip PATH    install from another zip instead of release/ (the checksum is still checked)
#
# Runs on the Bash 3.2 that ships with macOS. Uninstall with ./uninstall.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="KadomoMenu"
PREFIX="${PREFIX:-$HOME/Applications}"
APP="$PREFIX/$APP_NAME.app"
BIN="$HOME/.local/bin/kadomo-menu"
LOG_DIR="$HOME/Library/Logs/kadomo-menu"
LOG="$LOG_DIR/install.log"
TITLE="Install"
ASSUME_YES=0
FAILED=0
WORK=""

# The bundled build. Update these together when a new version is built into release/.
RELEASE_VERSION="0.1.0"
RELEASE_ZIP="$ROOT/release/KadomoMenu-$RELEASE_VERSION-x86_64-arm64.zip"
RELEASE_SHA256="0ab29e38f9ee9f2580626f6eccb56f3974da12a081fc34a419f76bede540cd01"
ZIP_PATH="$RELEASE_ZIP"

source "$ROOT/lib/tui.sh"

ITEM_LABEL=("Install Kadomo Menu" "Start the launcher")
ITEM_DETAIL=(
    "~/Applications/KadomoMenu.app and ~/.local/bin/kadomo-menu"
    "opens it now; it starts at login by default"
)
ITEM_ON=(1 1)
I_INSTALL=0; I_START=1

usage() {
    cat <<EOF
Usage: ./install.sh [--yes] [--zip PATH]

  --yes         Skip the checklist and review; install the defaults.
  --zip PATH    Install from another zip instead of the one in release/.
  --help        Show this help.

Without --yes, a checklist opens. Space toggles an item, Enter reviews the
choices, and q quits without changes.
EOF
}

preflight() {
    [[ "$(uname -s)" == Darwin ]] || die "Kadomo Menu is for macOS."
    local macos
    macos="$(sw_vers -productVersion)"
    ((${macos%%.*} >= 14)) || die "macOS 14 or later is required (this Mac runs $macos)."
    ((EUID != 0)) || die "run this as your own user, not with sudo."
    [[ -f "$ZIP_PATH" ]] || die "no app zip at $(short_path "$ZIP_PATH"). Is this a complete clone of the repo?"
}

any_selected() { ((ITEM_ON[I_INSTALL] + ITEM_ON[I_START])); }

review() {
    local i
    printf '\033[2J\033[H'
    logo
    printf '  %sReview%s\n\n' "$BOLD" "$RESET"
    for ((i=0; i<${#ITEM_LABEL[@]}; i++)); do
        ((ITEM_ON[i])) || continue
        printf '  %s·%s %s  %s%s%s\n' "$CYAN" "$RESET" "${ITEM_LABEL[i]}" "$DIM" "${ITEM_DETAIL[i]}" "$RESET"
    done
    printf '\n  %sAn existing install is replaced. Your config is kept.%s\n\n' "$DIM" "$RESET"
    confirm "Yes, install" "No, change it"
}

check_zip() {
    local actual
    actual="$(shasum -a 256 "$ZIP_PATH" | cut -d' ' -f1)"
    if [[ "$actual" != "$RELEASE_SHA256" ]]; then
        echo "checksum mismatch: expected $RELEASE_SHA256, got $actual"
        return 1
    fi
}

# Unpacks the app into a scratch folder, checks its signature, then swaps it in.
install_app() {
    local unpacked="$WORK/unpacked"
    mkdir -p "$unpacked" "$PREFIX"
    ditto -x -k "$ZIP_PATH" "$unpacked"
    codesign --verify --strict "$unpacked/$APP_NAME.app"
    # A zip that was downloaded in a browser carries a quarantine flag; a fresh install should not.
    xattr -dr com.apple.quarantine "$unpacked/$APP_NAME.app" 2>/dev/null || true
    rm -rf -- "$APP"
    mv "$unpacked/$APP_NAME.app" "$APP"
}

link_command() {
    mkdir -p "$(dirname "$BIN")"
    ln -sf "$APP/Contents/MacOS/$APP_NAME" "$BIN"
}

start_app() {
    local bin="$APP/Contents/MacOS/$APP_NAME"
    [[ -x "$bin" ]] || { echo "$APP is not installed."; return 1; }
    "$bin" quit >/dev/null 2>&1 || true
    sleep 0.5
    open "$APP"
}

install_steps() {
    run_step "Check the app zip" check_zip
    if ((FAILED)); then return; fi
    run_step "Install KadomoMenu.app" install_app
    if ((FAILED)); then return; fi
    run_step "Link the kadomo-menu command" link_command
}

finish() {
    if ((FAILED)); then
        printf '\n  %s✗ %d step(s) failed.%s Full output: %s\n\n' "$RED" "$FAILED" "$RESET" "$(short_path "$LOG")"
        exit 1
    fi
    printf '\n  %s✓ Kadomo Menu is installed%s\n\n' "$CYAN" "$RESET"
    printf '  %sApp%s      %s\n' "$DIM" "$RESET" "$(short_path "$APP")"
    [[ -e "$BIN" ]] && printf '  %sCommand%s  kadomo-menu\n' "$DIM" "$RESET"
    printf '  %sLaunch%s   press ⌥Space (Option-Space)\n' "$DIM" "$RESET"
    printf '  %sLog%s      %s\n' "$DIM" "$RESET" "$(short_path "$LOG")"
    if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        printf '\n  %sAdd ~/.local/bin to PATH to run kadomo-menu from a shell:%s\n' "$DIM" "$RESET"
        printf '      echo '\''export PATH="$HOME/.local/bin:$PATH"'\'' >> ~/.zshrc\n'
    fi
    printf '\n  %sRemove it later with ./uninstall.sh%s\n\n' "$DIM" "$RESET"
}

cleanup() { [[ -z "$WORK" ]] || rm -rf -- "$WORK"; }
trap cleanup EXIT

while (($#)); do
    case "$1" in
        --yes|-y) ASSUME_YES=1 ;;
        --zip) shift; [[ $# -gt 0 ]] || die "--zip needs a path"; ZIP_PATH="$1" ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown option: $1 (try --help)" ;;
    esac
    shift
done

preflight

if ((ASSUME_YES == 0)); then
    [[ -t 0 ]] || die "run this in a terminal, or pass --yes."
    while :; do
        checklist || { printf '\n  Nothing changed.\n\n'; exit 0; }
        any_selected || { printf '\n  Nothing selected. Nothing changed.\n\n'; exit 0; }
        review && break
    done
fi

mkdir -p "$LOG_DIR"
: >"$LOG"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/kadomo-menu-install.XXXXXX")"
printf '\n'
if ((ITEM_ON[I_INSTALL])); then install_steps; fi
if ((ITEM_ON[I_START] && FAILED == 0)); then run_step "Start the launcher" start_app; fi
finish
