#!/bin/bash
# Copies the configs in this folder to where each tool reads them. A file that
# is already identical is skipped; one that differs is backed up next to itself
# as <name>.bak.<timestamp> before being replaced. Every file placed, and the
# backup of whatever was there before Kadomo first replaced it, is recorded so
# uninstall.sh can remove the one and restore the other.
#
# Usage: ./install.sh [--dry-run]
#   --dry-run   show what would change without touching anything
#
# Runs on the Bash 3.2 that ships with macOS.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/files.sh"
STAMP="$(date +%Y%m%d-%H%M%S)"
DRY_RUN=0

case "${1:-}" in
    "") ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
esac

run() { if ((DRY_RUN)); then echo "    would run: $*"; else "$@"; fi; }

# Records dest once, with the backup of the file Kadomo first replaced (empty when there was none).
record() {
    ((DRY_RUN)) && return 0
    manifest_has "$1" && return 0
    mkdir -p "$(dirname "$MANIFEST")"
    printf '%s|%s\n' "$1" "$2" >>"$MANIFEST"
}

changed=()
for entry in "${FILES[@]}"; do
    src="$HERE/${entry%%|*}"
    dest="${entry#*|}"
    label="${dest/#$HOME/~}"

    if [[ ! -f "$src" ]]; then echo "  !  missing dotfiles/${entry%%|*}" >&2; exit 1; fi

    if [[ -f "$dest" && ! -L "$dest" ]] && cmp -s "$src" "$dest"; then
        echo "  =  $label (unchanged)"
        record "$dest" ""
        continue
    fi

    backup=""
    if [[ -e "$dest" || -L "$dest" ]]; then
        backup="$(backup_path "$dest")"
        echo "  ~  $label (backed up to $(basename "$backup"))"
        run mv "$dest" "$backup"
    else
        echo "  +  $label"
    fi
    run mkdir -p "$(dirname "$dest")"
    run cp "$src" "$dest"
    record "$dest" "$backup"
    changed+=("${entry%%/*}")
done

for tool in ${changed[@]+"${changed[@]}"}; do reload "$tool"; done

((DRY_RUN)) && echo "Dry run: nothing was changed."
exit 0
