#!/bin/bash
# Copies the configs in this folder to where each tool reads them. A file that
# is already identical is skipped; one that differs is backed up next to itself
# as <name>.bak.<timestamp> before being replaced. Every file placed and the
# backup of whatever was there before Kadomo first replaced it are recorded so
# uninstall.sh can undo exactly that. First, what older installs placed that
# this checkout no longer ships (kitty's config, AeroSpace's config,
# JankyBorders and its bordersrc) is removed: uninstall.sh --retired.
# Colors are not here: Ghostty reads them from the current Kadomo theme,
# which kadomo-theme-manager installs and switches.
#
# Usage: ./install.sh [--dry-run] [--only LIST]
#   --dry-run     show what would change without touching anything
#   --only LIST   install only these tools, comma-separated
#                 (ghostty,editors)
#
# Runs on the Bash 3.2 that ships with macOS.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/files.sh"
STAMP="$(date +%Y%m%d-%H%M%S)"
DRY_RUN=0
ONLY=""

while (($#)); do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        --only)
            shift; [[ $# -gt 0 ]] || { echo "--only needs a list (try --help)" >&2; exit 2; }
            ONLY="$1"
            for tool in ${ONLY//,/ }; do
                tool_known "$tool" || { echo "Unknown tool for --only: $tool (known: $(tool_names))" >&2; exit 2; }
            done
            ;;
        -h|--help) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
    esac
    shift
done

# Whether --only, when given, includes this tool.
selected() { [[ -z "$ONLY" || ",$ONLY," == *",$1,"* ]]; }

run() { if ((DRY_RUN)); then echo "    would run: $*"; else "$@"; fi; }

# Records dest with the checksum of the copy just placed. The backup is kept
# from the first install only: it is the file that was there before Kadomo.
record() {
    ((DRY_RUN)) && return 0
    mkdir -p "$(dirname "$MANIFEST")"
    if manifest_has "$1"; then
        awk -F'|' -v OFS='|' -v d="$1" -v h="$3" '$1 == d { $3 = h } { print }' "$MANIFEST" >"$MANIFEST.tmp"
        mv "$MANIFEST.tmp" "$MANIFEST"
    else
        printf '%s|%s|%s\n' "$1" "$2" "$3" >>"$MANIFEST"
    fi
}

# What older installs placed that this checkout no longer ships.
retired_args=(--retired)
((DRY_RUN == 0)) || retired_args+=(--dry-run)
"$HERE/uninstall.sh" "${retired_args[@]}"

changed=()
for entry in "${FILES[@]}"; do
    src="$HERE/${entry%%|*}"
    dest="${entry#*|}"
    label="${dest/#$HOME/~}"
    selected "${entry%%/*}" || continue

    if [[ ! -f "$src" ]]; then echo "  !  missing dotfiles/${entry%%|*}" >&2; exit 1; fi

    if [[ -f "$dest" && ! -L "$dest" ]] && cmp -s "$src" "$dest"; then
        echo "  =  $label (unchanged)"
        record "$dest" "" "$(sha256 "$src")"
        continue
    fi

    backup=""
    last="$(recorded_sha "$dest")"
    if [[ -n "$last" && -f "$dest" && ! -L "$dest" && "$(sha256 "$dest")" == "$last" ]]; then
        # Kadomo's own older copy, untouched since: replace it, nothing to keep.
        echo "  ~  $label (updated)"
    elif [[ -e "$dest" || -L "$dest" ]]; then
        backup="$(backup_path "$dest")"
        echo "  ~  $label (backed up to $(basename "$backup"))"
        run mv "$dest" "$backup"
    else
        echo "  +  $label"
    fi
    run mkdir -p "$(dirname "$dest")"
    run cp "$src" "$dest"
    record "$dest" "$backup" "$(sha256 "$src")"
    changed+=("${entry%%/*}")
done

reload_each ${changed[@]+"${changed[@]}"}

((DRY_RUN)) && echo "Dry run: nothing was changed."
exit 0
