#!/bin/bash
# Copies the configs in dotfiles/ to where each tool reads them. A file that is
# already identical is skipped; one that differs is backed up next to itself as
# <name>.bak.<timestamp> before being replaced.
#
# Usage: ./install.sh [--dry-run]
#   --dry-run   show what would change without touching anything
#
# Runs on the Bash 3.2 that ships with macOS.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES="$ROOT/dotfiles"
STAMP="$(date +%Y%m%d-%H%M%S)"
DRY_RUN=0

# Source (relative to dotfiles/) and destination, one pair per line.
FILES=(
    "aerospace/aerospace.toml|$HOME/.config/aerospace/aerospace.toml"
)

case "${1:-}" in
    "") ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
esac

run() { if ((DRY_RUN)); then echo "    would run: $*"; else "$@"; fi; }

changed=()
for entry in "${FILES[@]}"; do
    src="$DOTFILES/${entry%%|*}"
    dest="${entry#*|}"
    label="${dest/#$HOME/~}"

    if [[ ! -f "$src" ]]; then echo "  !  missing ${src#$ROOT/}" >&2; exit 1; fi

    if [[ -f "$dest" ]] && cmp -s "$src" "$dest"; then
        echo "  =  $label (unchanged)"
        continue
    fi

    if [[ -e "$dest" || -L "$dest" ]]; then
        echo "  ~  $label (backed up to $(basename "$dest").bak.$STAMP)"
        run mv "$dest" "$dest.bak.$STAMP"
    else
        echo "  +  $label"
    fi
    run mkdir -p "$(dirname "$dest")"
    run cp "$src" "$dest"
    changed+=("${entry%%/*}")
done

# Tell running tools to pick up their new config.
for tool in ${changed[@]+"${changed[@]}"}; do
    case "$tool" in
        aerospace)
            if command -v aerospace >/dev/null && pgrep -xq AeroSpace 2>/dev/null; then
                echo "  ↻  reloading AeroSpace"
                run aerospace reload-config || echo "  !  aerospace reload-config failed" >&2
            fi
            ;;
    esac
done

((DRY_RUN)) && echo "Dry run: nothing was changed."
echo "Done."
