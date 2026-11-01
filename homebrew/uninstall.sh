#!/bin/bash
# Removes the Homebrew that Kadomo's installer put on this Mac, with Homebrew's
# own uninstaller, and the PATH block it added to ~/.zprofile. When Homebrew's
# installer added the Xcode Command Line Tools for it, they go too. A Homebrew
# that was here before Kadomo is never touched, and neither is one you have
# installed your own packages with since: it stays, with its PATH block, and
# only Kadomo's record of it goes. Run it after Kadomo's other parts, which
# use Homebrew to remove what they installed. It asks for your password.
#
# Usage: ./uninstall.sh [--dry-run]
#   --dry-run   show what would change without touching anything
#
# Runs on the Bash 3.2 that ships with macOS.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/homebrew.sh"
DRY_RUN=0

case "${1:-}" in
    "") ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
esac

run() { if ((DRY_RUN)); then echo "    would run: $*"; else "$@"; fi; }

if [[ ! -s "$HOMEBREW_RECORD" ]]; then
    echo "  =  no homebrew installed"
    exit 0
fi

prefix="$(hb_recorded prefix || true)"
zprofile="$(hb_recorded zprofile || true)"
brew=""
[[ -n "$prefix" && -x "$prefix/bin/brew" ]] && brew="$prefix/bin/brew"

# Kadomo's block out of ~/.zprofile, and the blank line before it; a file Kadomo
# made and nothing else is in goes.
remove_block() {
    local file="$1"
    hb_has_block "$file" || return 0
    echo "  -  Kadomo's Homebrew block in $(short_path "$file")"
    ((DRY_RUN)) && return 0
    awk -v b="$HOMEBREW_BEGIN" -v e="$HOMEBREW_END" '
        $0 == b { skip = 1; held = ""; next }
        skip { if ($0 == e) skip = 0; next }
        /^$/ { held = held $0 "\n"; next }
        { printf "%s", held; held = ""; print }
        END { printf "%s", held }' "$file" >"$file.kadomo-tmp" && mv "$file.kadomo-tmp" "$file"
    if [[ -n "$(hb_recorded zprofile-created || true)" && -z "$(tr -d '[:space:]' <"$file")" ]]; then
        echo "  -  $(short_path "$file") (Kadomo made it, and nothing else is in it)"
        rm -f -- "$file"
    fi
}

# Your password, once, for Homebrew's uninstaller and the Command Line Tools.
need_sudo() {
    ((DRY_RUN)) && return 0
    sudo -n true 2>/dev/null && return 0
    if ! { : </dev/tty; } 2>/dev/null; then
        echo "  !  removing Homebrew asks for your password: run this in a terminal" >&2
        return 1
    fi
    echo "  Removing Homebrew needs your Mac password: its folder, and the Command Line"
    echo "  Tools when it added them, are in system folders only an administrator can change."
    sudo -v -p "  Password for $(id -un): " </dev/tty
}

if [[ -n "$brew" ]]; then
    # In a dry run Kadomo's own packages are still there; the parts before this one remove them.
    if ((DRY_RUN)); then left="$(hb_other_packages "$brew")"; else left="$(hb_packages "$brew")"; fi
    if [[ -n "$left" ]]; then
        others="$(hb_other_packages "$brew")"
        list="$(printf '%s\n' "$left" | paste -sd, - | sed 's/,/, /g')"
        if [[ -z "$others" ]]; then
            # Only Kadomo's are left: a part that was not selected, or one that could not remove them.
            echo "  =  Homebrew left in place: Kadomo's $list is still installed with it"
            printf '\n  Still needs you:\n'
            printf '  1. Homebrew was left in place too, since Kadomo'\''s %s still uses it. Running ./uninstall.sh again once %s can go (from Terminal, say) removes both.\n' "$list" "$list"
            exit 0
        fi
        list="$(printf '%s\n' "$others" | paste -sd, - | sed 's/,/, /g')"
        echo "  =  Homebrew stays: you installed $list with it (its PATH block stays too)"
        run rm -f -- "$HOMEBREW_RECORD"
        run rmdir "$STATE_DIR" 2>/dev/null || true
        ((DRY_RUN)) && echo "Dry run: nothing was changed."
        exit 0
    fi
fi

clt="$(hb_recorded clt || true)"
if [[ -n "$brew" || ( "$clt" == added && -d "$CLT_DIR" ) ]]; then need_sudo || exit 1; fi
keep_alive=""
if ((DRY_RUN == 0)); then
    ( while kill -0 "$$" 2>/dev/null; do sudo -n true 2>/dev/null; sleep 30; done ) &
    keep_alive=$!
fi
WORK="$(mktemp -d "${TMPDIR:-/tmp}/kadomo-homebrew.XXXXXX")"
cleanup() {
    if [[ -n "$keep_alive" ]]; then { kill "$keep_alive"; wait "$keep_alive"; } 2>/dev/null || true; fi
    rm -rf -- "$WORK"
}
trap cleanup EXIT

failed=0
if [[ -n "$brew" ]]; then
    echo "  -  Homebrew in $prefix (Homebrew's own uninstaller)"
    if ((DRY_RUN == 0)); then
        if ! curl -fsSL --retry 2 -o "$WORK/uninstall.sh" "$HOMEBREW_UNINSTALL_URL" || [[ ! -s "$WORK/uninstall.sh" ]]; then
            echo "  !  could not download Homebrew's uninstaller; check the network and run this again" >&2
            exit 1
        fi
        NONINTERACTIVE=1 /bin/bash "$WORK/uninstall.sh" --force --path="$prefix" || failed=1
    fi
    # Its uninstaller leaves folders it did not make itself; /opt/homebrew is
    # all Homebrew's, so it goes. /usr/local is shared with other software, so
    # what is left there stays.
    if [[ "$prefix" == /opt/homebrew && -d "$prefix" ]] && ((failed == 0)); then
        echo "  -  $prefix (what Homebrew's uninstaller left)"
        run sudo rm -rf -- /opt/homebrew
    fi
    if ((DRY_RUN == 0)) && [[ -x "$prefix/bin/brew" ]]; then
        echo "  !  Homebrew is still in $prefix; see above" >&2
        failed=1
    fi
else
    echo "  =  Homebrew (already removed)"
fi

if ((failed == 0)); then
    if [[ "$clt" == added && -d "$CLT_DIR" ]]; then
        echo "  -  Xcode Command Line Tools (Homebrew's installer added them for Kadomo)"
        run sudo rm -rf -- "$CLT_DIR"
        run sudo xcode-select --reset 2>/dev/null || true
    fi
    for file in "$zprofile" "$HOMEBREW_ZPROFILE"; do [[ -z "$file" ]] || remove_block "$file"; done
    run rm -f -- "$HOMEBREW_RECORD"
    run rmdir "$STATE_DIR" 2>/dev/null || true
fi

((DRY_RUN)) && echo "Dry run: nothing was changed."
exit "$failed"
