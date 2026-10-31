#!/bin/bash
# Installs every Kadomo component, each with its own installer:
#   dotfiles/      configs copied to where each tool reads them
#   kadomo-menu/   the launcher app, its command, and its font
# Remove everything again with ./uninstall.sh.
#
# Usage: ./install.sh [--yes]
#   --yes   skip each component's prompts and install its defaults
#
# Runs on the Bash 3.2 that ships with macOS.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
YES=()

case "${1:-}" in
    "") ;;
    --yes|-y) YES=(--yes) ;;
    -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
esac

failed=()
step() {
    local name="$1"; shift
    printf '\n== %s\n' "$name"
    "$@" || failed+=("$name")
}

step dotfiles "$ROOT/dotfiles/install.sh"
step kadomo-menu "$ROOT/kadomo-menu/install.sh" ${YES[@]+"${YES[@]}"}

if [[ ${#failed[@]} -gt 0 ]]; then
    printf '\nFailed: %s\n' "${failed[*]}" >&2
    exit 1
fi
printf '\nKadomo is installed. Remove it with ./uninstall.sh\n'
