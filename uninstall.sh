#!/bin/bash
# Removes everything ./install.sh put in place, newest component first:
#   kadomo-menu/   the app, its command, the font it added, its config and state
#   dotfiles/      the configs it placed; the files they replaced are restored
#
# Usage: ./uninstall.sh [--yes]
#   --yes   skip the prompts and remove everything found
#
# Runs on the Bash 3.2 that ships with macOS.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
YES=()

case "${1:-}" in
    "") ;;
    --yes|-y) YES=(--yes) ;;
    -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
esac

failed=()
step() {
    local name="$1"; shift
    printf '\n== %s\n' "$name"
    "$@" || failed+=("$name")
}

# Shows what the dotfiles uninstaller would do and asks before doing it.
dotfiles() {
    if [[ ${#YES[@]} -eq 0 ]]; then
        local plan answer
        plan="$("$ROOT/dotfiles/uninstall.sh" --dry-run | grep -v '^    would run:\|^Dry run:')"
        echo "$plan"
        [[ "$plan" != *"no dotfiles installed"* ]] || return 0
        read -r -p "Remove these dotfiles? [y/N] " answer </dev/tty || answer=""
        [[ "$answer" == [yY]* ]] || { echo "  dotfiles left in place"; return 0; }
    fi
    "$ROOT/dotfiles/uninstall.sh"
}

step kadomo-menu "$ROOT/kadomo-menu/uninstall.sh" ${YES[@]+"${YES[@]}"}
step dotfiles dotfiles

if [[ ${#failed[@]} -gt 0 ]]; then
    printf '\nFailed: %s\n' "${failed[*]}" >&2
    exit 1
fi
printf '\nDone. This checkout was left in place.\n'
