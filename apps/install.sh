#!/bin/bash
# Installs apps with Homebrew: Ghostty, kitty, Moonlight, Neovim, btop, htop,
# and Firefox.
# An app that is already on this Mac, however it got there, is left alone.
# Each app Kadomo installs is recorded so uninstall.sh removes exactly those.
#
# Usage: ./install.sh [--dry-run] [--only LIST]
#   --dry-run     show what would change without touching anything
#   --only LIST   install only these apps, comma-separated
#                 (ghostty,kitty,moonlight,neovim,btop,htop,firefox)
#
# Runs on the Bash 3.2 that ships with macOS.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/apps.sh"
DRY_RUN=0
ONLY=""

while (($#)); do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        --only)
            shift; [[ $# -gt 0 ]] || { echo "--only needs a list (try --help)" >&2; exit 2; }
            ONLY="$1"
            for key in ${ONLY//,/ }; do
                app_entry "$key" >/dev/null || { echo "Unknown app for --only: $key (known: $(app_keys))" >&2; exit 2; }
            done
            ;;
        -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
    esac
    shift
done

selected() { [[ -z "$ONLY" || ",$ONLY," == *",$1,"* ]]; }

record() {
    ((DRY_RUN)) && return 0
    [[ -f "$APPS_MANIFEST" ]] && grep -qxF "$1|$2" "$APPS_MANIFEST" && return 0
    mkdir -p "$(dirname "$APPS_MANIFEST")"
    printf '%s|%s\n' "$1" "$2" >>"$APPS_MANIFEST"
}

brew=""
failed=0
for entry in "${APPS[@]}"; do
    key="$(app_field "$entry" 1)"
    kind="$(app_field "$entry" 2)"
    name="$(app_field "$entry" 3)"
    selected "$key" || continue

    if app_present "$entry"; then
        echo "  =  $key (already installed)"
        continue
    fi
    if [[ -z "$brew" ]] && ! brew="$(find_brew)"; then
        echo "  !  $key needs Homebrew (https://brew.sh); skipping it" >&2
        brew=""; failed=1
        continue
    fi
    if "$brew" list "--$kind" "$name" >/dev/null 2>&1; then
        echo "  =  $key (already installed)"
        continue
    fi

    echo "  +  $key (brew install --$kind $name)"
    if ((DRY_RUN)); then
        echo "    would run: $brew install --$kind $name"
    else
        "$brew" install "--$kind" "$name" || { echo "  !  brew install --$kind $name failed" >&2; failed=1; }
        # Recorded whenever Homebrew now has it, even after a failure part way,
        # so uninstall.sh still removes it.
        if "$brew" list "--$kind" "$name" >/dev/null 2>&1; then record "$kind" "$name"; fi
    fi
done

((DRY_RUN)) && echo "Dry run: nothing was changed."
exit "$failed"
