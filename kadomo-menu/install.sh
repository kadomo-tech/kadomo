#!/bin/bash
# Installs Kadomo Menu from the prebuilt app that ships in this repo, in
# release/ (one build for Apple silicon and Intel, macOS 14 or later). It checks
# the zip against a SHA-256, puts KadomoMenu.app in ~/Applications, links the
# kadomo-menu command into ~/.local/bin, installs the JetBrainsMono Nerd Font
# the default theme uses, and starts the launcher. No Xcode or compiler is
# needed. Your config in ~/.config/kadomo-menu is never touched.
#
# Usage: ./install.sh [--yes] [--only LIST] [--zip PATH]
#   --yes         skip the checklist and review, and install the defaults
#   --only LIST   skip the checklist and review, and install just these items,
#                 comma-separated: app, font, start
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
RELEASE_SHA256="30f9665b74762c2961626ebfe3e8e594dcf5077598fc3e956717e507546f3f8b"
ZIP_PATH="$RELEASE_ZIP"

# The default theme's font, pinned to a Nerd Fonts release and checked against its SHA-256.
FONT_VERSION="3.5.1"
FONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/v$FONT_VERSION/JetBrainsMono.tar.xz"
FONT_SHA256="04d5e8f903693f9dd13e16f867e994834e681eb3c72c0d337a770dcda09010cf"
# Both variants: "Nerd Font" for the launcher and Terminal, and the strictly
# monospaced "Nerd Font Mono" for kitty, which lists only fixed-pitch fonts.
FONT_GLOBS=("JetBrainsMonoNerdFont-*.ttf" "JetBrainsMonoNerdFontMono-*.ttf")
FONT_DIR="$HOME/Library/Fonts"
# Files this script added, so uninstall.sh removes only those. Follows the app's state dir.
STATE_DIR="${KADOMO_MENU_STATE_DIR:-$HOME/Library/Application Support/kadomo-menu}"
FONT_MANIFEST="$STATE_DIR/installed-fonts.txt"

source "$ROOT/lib/tui.sh"

# Installed when both variants are, in your Fonts folder or the system one.
font_installed() {
    local name
    for name in JetBrainsMonoNerdFont-Regular.ttf JetBrainsMonoNerdFontMono-Regular.ttf; do
        [[ -e "$FONT_DIR/$name" || -e "/Library/Fonts/$name" ]] || return 1
    done
}

ITEM_LABEL=("Install Kadomo Menu" "Install JetBrainsMono Nerd Font" "Start the launcher")
ITEM_DETAIL=(
    "~/Applications/KadomoMenu.app and ~/.local/bin/kadomo-menu"
    "for the launcher, Terminal, and kitty; ~/Library/Fonts, 7 MB download from GitHub"
    "opens it now; it starts at login by default"
)
ITEM_ON=(1 1 1)
I_INSTALL=0; I_FONT=1; I_START=2
if font_installed; then ITEM_DETAIL[I_FONT]="already installed"; ITEM_ON[I_FONT]=0; fi

usage() {
    cat <<EOF
Usage: ./install.sh [--yes] [--only LIST] [--zip PATH]

  --yes         Skip the checklist and review; install the defaults.
  --only LIST   Skip the checklist and review; install just these items,
                comma-separated: app, font, start.
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
    [[ "$ZIP_PATH" != "$RELEASE_ZIP" ]] || check_fresh
}

# Refuses a release/ build that is older than the source it ships, so a fix that was
# committed without rebuilding the zip cannot quietly install the old app.
check_fresh() {
    local built newer
    git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || return 0
    # An uncommitted zip was just rebuilt from the working tree.
    [[ -z "$(git -C "$ROOT" status --porcelain -- release)" ]] || return 0
    built="$(git -C "$ROOT" log -1 --format=%H -- release)"
    [[ -n "$built" ]] || return 0
    newer="$(git -C "$ROOT" rev-list --count "$built..HEAD" -- Sources Package.swift Info.plist.in)"
    ((newer == 0)) || die "the app in release/ is older than the source ($newer newer commit(s)). Rebuild it with ./build.sh --universal --package, then run this again."
}

# Turns on exactly the items named in a comma-separated list of app, font, start.
select_only() {
    local key
    ITEM_ON=(0 0 0)
    for key in ${1//,/ }; do
        case "$key" in
            app) ITEM_ON[I_INSTALL]=1 ;;
            font) ITEM_ON[I_FONT]=1 ;;
            start) ITEM_ON[I_START]=1 ;;
            *) die "unknown item for --only: $key (known: app, font, start)" ;;
        esac
    done
}

any_selected() { ((ITEM_ON[I_INSTALL] + ITEM_ON[I_FONT] + ITEM_ON[I_START])); }

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

# Downloads the pinned release, checks it, and copies in the files that are not there yet.
# Each file it adds is recorded in the manifest; fonts you installed yourself are never listed.
install_font() {
    local archive="$WORK/font.tar.xz" unpacked="$WORK/font" actual file name
    mkdir -p "$unpacked" "$FONT_DIR" "$STATE_DIR"
    curl -fsSL --retry 2 -o "$archive" "$FONT_URL"
    actual="$(shasum -a 256 "$archive" | cut -d' ' -f1)"
    if [[ "$actual" != "$FONT_SHA256" ]]; then
        echo "font checksum mismatch: expected $FONT_SHA256, got $actual"
        return 1
    fi
    tar -xf "$archive" -C "$unpacked" "${FONT_GLOBS[@]}"
    for file in "$unpacked"/${FONT_GLOBS[0]} "$unpacked"/${FONT_GLOBS[1]}; do
        name="$(basename "$file")"
        [[ ! -e "$FONT_DIR/$name" ]] || continue
        cp "$file" "$FONT_DIR/$name"
        echo "$name" >>"$FONT_MANIFEST"
    done
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
        --only) shift; [[ $# -gt 0 ]] || die "--only needs a list"; select_only "$1"; ASSUME_YES=1 ;;
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
APP_FAILED=$FAILED
# A failed font download leaves the app on SF Mono; it still starts.
if ((ITEM_ON[I_FONT])); then run_step "Install JetBrainsMono Nerd Font" install_font; fi
if ((ITEM_ON[I_START] && APP_FAILED == 0)); then run_step "Start the launcher" start_app; fi
finish
