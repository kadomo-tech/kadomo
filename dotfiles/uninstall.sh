#!/bin/bash
# Removes the configs install.sh placed and puts back the files they replaced.
# A config you edited after installing is kept as <name>.bak.<timestamp>
# instead of being deleted.
#
# Usage: ./uninstall.sh [--dry-run]
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
    -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
esac

run() { if ((DRY_RUN)); then echo "    would run: $*"; else "$@"; fi; }

if [[ ! -s "$MANIFEST" ]]; then
    echo "  =  no dotfiles installed"
    exit 0
fi

# The FILES entry for a destination: its repo copy tells an untouched install
# from one you edited, and its folder names the tool to reload.
entry_for() {
    local entry
    for entry in "${FILES[@]}"; do
        [[ "${entry#*|}" == "$1" ]] && { printf '%s' "$entry"; return; }
    done
}

tools=()
while IFS='|' read -r dest backup; do
    [[ -n "$dest" ]] || continue
    label="${dest/#$HOME/~}"
    entry="$(entry_for "$dest")"
    src="${entry:+$HERE/${entry%%|*}}"

    if [[ -e "$dest" || -L "$dest" ]]; then
        if [[ -n "$src" && -f "$dest" && ! -L "$dest" ]] && cmp -s "$src" "$dest"; then
            echo "  -  $label"
            run rm -f -- "$dest"
        else
            kept="$(backup_path "$dest")"
            echo "  ~  $label (edited since install; kept as $(basename "$kept"))"
            run mv "$dest" "$kept"
        fi
    fi
    if [[ -n "$backup" && -e "$backup" ]]; then
        echo "  ↩  $label (restored from $(basename "$backup"))"
        run mv "$backup" "$dest"
    else
        # Nothing to put back: drop the folder too if install.sh left it empty.
        run rmdir "$(dirname "$dest")" 2>/dev/null || true
    fi
    [[ -z "$entry" ]] || tools+=("${entry%%/*}")
done <"$MANIFEST"

run rm -f -- "$MANIFEST"
run rmdir "$STATE_DIR" 2>/dev/null || true
reload_each ${tools[@]+"${tools[@]}"}

((DRY_RUN)) && echo "Dry run: nothing was changed."
exit 0
