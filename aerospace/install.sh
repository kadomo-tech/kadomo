#!/bin/bash
# Installs AeroSpace Kadomo, Kadomo's default window manager (tiles, accordion,
# dwindle and scrolling layouts), with JankyBorders around its windows, and
# makes it the window manager:
#   /Applications/AeroSpace Kadomo.app   from the fork's release that release.txt pins
#                                        (checksum verified); its aerospace command
#                                        comes from the same build
#   ~/.local/bin/aerospace               a link to that command (one of yours there is
#                                        set aside, and put back by uninstall.sh)
#   ~/.local/bin/kadomo-aerospace, kadomo-borders, kadomo-wm
#                                        commands, not background processes
#   ~/.config/aerospace/aerospace.toml   Kadomo's config; a different one of yours is set
#   ~/.config/borders/bordersrc          aside as <name>.before-kadomo and comes back on
#                                        uninstall (so does ~/.aerospace.toml)
#   borders                              JankyBorders, from Homebrew, unless it is here
#   ~/Library/LaunchAgents/tech.kadomo.window-manager.plist
#                                        starts the chosen window manager at login
#   ~/.config/kadomo/menu/commands/aerospace-kadomo.toml
#                                        Kadomo Menu › Services › AeroSpace, and its keys
#                                        under Keybinds
# Then kadomo-wm makes AeroSpace the window manager: OmniWM, if it runs, is quit
# and no longer started at login (it stays installed). If AeroSpace does not
# start, what ran before runs again. macOS asks once to allow AeroSpace Kadomo
# in Privacy & Security › Accessibility.
#
# Usage: ./install.sh [--dry-run] [--install-only]
#   --install-only   install, but leave the window manager choice as it is
#
# KADOMO_AEROSPACE_ZIP=<zip> installs from a local build instead of the release
# (for development; the checksum is not checked then).
# Runs on the Bash 3.2 that ships with macOS. Undo it with ./uninstall.sh.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
source "$HERE/aerospace.sh"
source "$ROOT/wm/wm.sh"
DRY_RUN=0
ACTIVATE=1

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        --install-only) ACTIVATE=0 ;;
        -h|--help) sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $arg (try --help)" >&2; exit 2 ;;
    esac
done

run() { if ((DRY_RUN)); then echo "    would run: $*"; else "$@"; fi; }
short() { printf '%s' "${1/#$HOME/~}"; }

((EUID != 0)) || { echo "  !  run this as your own user, not with sudo" >&2; exit 1; }
aerospace_supported || { echo "  !  AeroSpace $(aerospace_requirement)" >&2; exit 1; }

find_brew() {
    local path
    for path in "$(command -v brew 2>/dev/null)" /opt/homebrew/bin/brew /usr/local/bin/brew; do
        [[ -n "$path" && -x "$path" ]] && { printf '%s' "$path"; return 0; }
    done
    return 1
}

todo=()
RELEASE="${KADOMO_AEROSPACE_RELEASE:-$HERE/release.txt}"
VERSION="$(aerospace_release_field "$RELEASE" version)"
URL="$(aerospace_release_field "$RELEASE" url)"
SHA256="$(aerospace_release_field "$RELEASE" sha256)"
LOCAL_ZIP="${KADOMO_AEROSPACE_ZIP:-}"

# --- the app ---------------------------------------------------------------------

# Checks an unpacked build: Kadomo's bundle id, the pinned version, and a
# command from the same build.
check_build() { # <app>
    local app="$1" id version cli_version
    id="$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$app/Contents/Info.plist" 2>/dev/null || true)"
    [[ "$id" == "$AEROSPACE_ID" ]] || { echo "  !  the download is not AeroSpace Kadomo (bundle id ${id:-missing})" >&2; return 1; }
    version="$(aerospace_app_version "$app")"
    if [[ -z "$LOCAL_ZIP" && "$version" != "$VERSION" ]]; then
        echo "  !  the download is version $version, release.txt pins $VERSION" >&2; return 1
    fi
    aerospace_renewed_version "$version" || { echo "  !  $version is not a renewed Kadomo build (-kadomo.3 or later)" >&2; return 1; }
    [[ -x "$app/Contents/Helpers/aerospace" ]] || { echo "  !  the build has no aerospace command (Contents/Helpers/aerospace)" >&2; return 1; }
    cli_version="$("$app/Contents/Helpers/aerospace" --version 2>/dev/null | head -n 1 || true)"
    [[ "$cli_version" == *"$version"* ]] || { echo "  !  the aerospace command is not from the same build ($cli_version)" >&2; return 1; }
}

# Downloads, checks and unpacks the build into $1. Nothing outside it changes.
fetch_build() { # <staging dir>
    local stage="$1" zip="$1/build.zip" sum
    if [[ -n "$LOCAL_ZIP" ]]; then
        [[ -f "$LOCAL_ZIP" ]] || { echo "  !  KADOMO_AEROSPACE_ZIP: no such file: $LOCAL_ZIP" >&2; return 1; }
        echo "  !  installing from a local build, without a checksum: $LOCAL_ZIP" >&2
        cp "$LOCAL_ZIP" "$zip"
    else
        [[ -n "$SHA256" ]] || { echo "  !  AeroSpace Kadomo $VERSION is not released yet (release.txt has no sha256)" >&2; return 1; }
        curl -fsSL --retry 2 -o "$zip" "$URL" || { echo "  !  could not download $URL" >&2; return 1; }
        sum="$(shasum -a 256 "$zip" | awk '{ print $1 }')"
        [[ "$sum" == "$SHA256" ]] || { echo "  !  the download's checksum is wrong ($sum); nothing was changed" >&2; return 1; }
    fi
    ditto -x -k "$zip" "$stage/unpacked" || { echo "  !  could not unpack the build" >&2; return 1; }
    [[ -d "$stage/unpacked/AeroSpace Kadomo.app" ]] || { echo "  !  the zip has no AeroSpace Kadomo.app" >&2; return 1; }
    check_build "$stage/unpacked/AeroSpace Kadomo.app"
}

# Puts the checked build in place. The app that was there comes back if that fails.
swap_app() { # <new app>
    local old="$AEROSPACE_APP.kadomo-old.$$"
    if [[ -e "$AEROSPACE_APP" ]]; then mv "$AEROSPACE_APP" "$old" || return 1; fi
    if ! mv "$1" "$AEROSPACE_APP"; then
        [[ ! -e "$old" ]] || mv "$old" "$AEROSPACE_APP"
        return 1
    fi
    rm -rf -- "$old"
}

installed_version="$(aerospace_app_version)"
if [[ -d "$AEROSPACE_APP" && -z "$LOCAL_ZIP" && "$installed_version" == "$VERSION" ]]; then
    echo "  =  AeroSpace Kadomo $VERSION (already installed)"
else
    if [[ -d "$AEROSPACE_APP" ]]; then echo "  +  AeroSpace Kadomo ${LOCAL_ZIP:+(local build) }${VERSION} (replaces ${installed_version:-the app there})"
    else echo "  +  AeroSpace Kadomo ${LOCAL_ZIP:+(local build) }$VERSION ($(short "$AEROSPACE_APP"))"; fi
    if ((DRY_RUN)); then
        echo "    would run: download and check ${LOCAL_ZIP:-$URL}, then put it in $(short "$AEROSPACE_APP")"
    else
        stage="$(mktemp -d "${TMPDIR:-/tmp}/kadomo-aerospace.XXXXXX")"
        trap 'rm -rf -- "$stage"' EXIT
        # A running AeroSpace Kadomo keeps working until the new build is checked.
        fetch_build "$stage" || exit 1
        was_running=0
        if pgrep -f "^$AEROSPACE_APP/Contents/MacOS/" >/dev/null 2>&1; then
            was_running=1
            [[ ! -x "$AEROSPACE_BIN" ]] || "$AEROSPACE_BIN" stop || true
        fi
        if ! swap_app "$stage/unpacked/AeroSpace Kadomo.app"; then
            echo "  !  could not put the new build in $(short "$AEROSPACE_APP"); the one there stays" >&2
            ((was_running == 0)) || open "$AEROSPACE_APP" || true
            exit 1
        fi
        aerospace_record version "$(aerospace_app_version)"
        aerospace_record app "$AEROSPACE_APP"
        # The new build is new to macOS: its Accessibility grant is asked for again.
        todo+=("Allow \"AeroSpace Kadomo\" in System Settings › Privacy & Security › Accessibility if macOS asks.")
    fi
fi

# --- the aerospace command -----------------------------------------------------

# Sets a file of yours aside as <file>.before-kadomo (once: an earlier one stays).
set_aside() { # <path>
    local path="$1" backup="$1$AEROSPACE_BACKUP_SUFFIX"
    [[ ! -e "$backup" && ! -L "$backup" ]] || backup="$1$AEROSPACE_BACKUP_SUFFIX.$(date +%Y%m%d%H%M%S)"
    echo "  ↪  $(short "$path") set aside as $(short "$backup")"
    run mv "$path" "$backup"
    ((DRY_RUN)) || aerospace_record_also backup "$path"
}

if [[ -L "$AEROSPACE_CLI_LINK" && "$(readlink "$AEROSPACE_CLI_LINK")" == "$AEROSPACE_APP_CLI" ]]; then
    echo "  =  $(short "$AEROSPACE_CLI_LINK")"
else
    [[ ! -e "$AEROSPACE_CLI_LINK" && ! -L "$AEROSPACE_CLI_LINK" ]] || set_aside "$AEROSPACE_CLI_LINK"
    echo "  +  $(short "$AEROSPACE_CLI_LINK") (AeroSpace Kadomo's command)"
    run mkdir -p "$(dirname "$AEROSPACE_CLI_LINK")"
    run ln -s "$AEROSPACE_APP_CLI" "$AEROSPACE_CLI_LINK"
fi

for helper in kadomo-aerospace kadomo-borders; do
    if cmp -s "$HERE/bin/$helper" "$HOME/.local/bin/$helper"; then continue; fi
    echo "  +  ~/.local/bin/$helper"
    run mkdir -p "$HOME/.local/bin"
    run install -m 755 "$HERE/bin/$helper" "$HOME/.local/bin/$helper"
done
wm_install_switcher "$ROOT/wm/bin" "$DRY_RUN"

# --- configs -------------------------------------------------------------------

# Puts Kadomo's file at <dest>. Same content: nothing to do. Kadomo's own file
# that you edited: a copy of your edit is kept as <dest>.kadomo-edited. Anything
# else of yours is set aside, and uninstall.sh puts it back.
place_config() { # <source> <dest> <marker> <mode>
    local src="$1" dest="$2" marker="$3" mode="$4"
    if [[ -f "$dest" ]] && cmp -s "$src" "$dest"; then echo "  =  $(short "$dest")"; return 0; fi
    if [[ -f "$dest" && ! -L "$dest" ]] && head -n 2 "$dest" | grep -qF "$marker"; then
        echo "  ↪  your edits to $(short "$dest") kept as $(short "$dest").kadomo-edited"
        run cp -p "$dest" "$dest.kadomo-edited"
    elif [[ -e "$dest" || -L "$dest" ]]; then
        set_aside "$dest"
    fi
    echo "  +  $(short "$dest")"
    run mkdir -p "$(dirname "$dest")"
    run install -m "$mode" "$src" "$dest"
}

# AeroSpace refuses to start with both config files; yours goes aside, not away.
[[ ! -e "$AEROSPACE_DOT_CONFIG" && ! -L "$AEROSPACE_DOT_CONFIG" ]] || set_aside "$AEROSPACE_DOT_CONFIG"
place_config "$HERE/aerospace.toml" "$AEROSPACE_CONFIG" "# Kadomo's AeroSpace config" 644
place_config "$HERE/bordersrc" "$BORDERS_RC" "# Kadomo's JankyBorders config" 755

# --- JankyBorders ----------------------------------------------------------------

if PATH="$PATH:/opt/homebrew/bin:/usr/local/bin" command -v borders >/dev/null 2>&1; then
    echo "  =  borders (JankyBorders, already installed)"
elif brew="$(find_brew)"; then
    echo "  +  borders (brew install $BORDERS_FORMULA)"
    if run "$brew" install "$BORDERS_FORMULA"; then
        ((DRY_RUN)) || aerospace_record formula "$BORDERS_FORMULA"
    else
        echo "  !  could not install JankyBorders; AeroSpace works without its borders" >&2
        todo+=("Install JankyBorders for the window borders: brew install $BORDERS_FORMULA")
    fi
else
    todo+=("Install Homebrew (https://brew.sh), then JankyBorders for the window borders: brew install $BORDERS_FORMULA")
fi

# --- menu, theme, and making it the window manager ---------------------------------

if ((DRY_RUN)); then
    echo "    would run: $(short "$AEROSPACE_BIN") menu"
else
    "$AEROSPACE_BIN" menu || echo "  !  could not write the Kadomo Menu entries" >&2
    # The theme's colors, if the theme manager has rendered them.
    "$BORDERS_BIN" theme || echo "  !  could not put the theme's colors on the borders" >&2
fi

if ((ACTIVATE)); then
    if ((DRY_RUN)); then
        echo "  ▶  would make AeroSpace Kadomo the window manager (OmniWM is quit if it runs)"
        echo "    would run: $(short "$KADOMO_WM_BIN") use aerospace"
    else
        echo "  ▶  making AeroSpace Kadomo the window manager (allow it in Privacy & Security › Accessibility if macOS asks)"
        if ! "$KADOMO_WM_BIN" use aerospace; then
            echo "  !  AeroSpace Kadomo did not start; the window manager that ran before runs again" >&2
            todo+=("Start AeroSpace from Kadomo Menu › Services › AeroSpace › Start, after allowing it in Privacy & Security › Accessibility.")
            exit_status=1
        fi
    fi
else
    echo "  =  the window manager stays $(wm_label "$(wm_choice || echo none)")"
fi

if ((${#todo[@]})); then
    printf '\n  Still needs you:\n'
    for ((i=0; i<${#todo[@]}; i++)); do
        printf '%s\n' "${todo[i]}" | fold -s -w 76 | sed "s/ *$//; 1s/^/  $((i+1)). /; 1!s/^/     /"
    done
fi
((DRY_RUN)) && echo "Dry run: nothing was changed."
exit "${exit_status:-0}"
