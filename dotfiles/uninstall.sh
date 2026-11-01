#!/bin/bash
# Removes the configs install.sh placed and puts back the files they replaced.
# A config you edited after installing is kept as <name>.bak.<timestamp>
# instead of being deleted. Formulae older installs added (JankyBorders) are
# stopped and uninstalled; ones you installed yourself are left alone.
# (The btop theme that older dotfiles set up is now the theme manager's:
# kadomo-theme-manager/uninstall.sh removes it.)
#
# Usage: ./uninstall.sh [--dry-run] [--stop | --retired]
#   --dry-run   show what would change without touching anything
#   --stop      only stop the formulae Kadomo installed (JankyBorders); remove nothing
#   --retired   only remove what this checkout no longer ships (AeroSpace's config,
#               JankyBorders and its bordersrc); install.sh runs it
#
# Runs on the Bash 3.2 that ships with macOS.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/files.sh"
STAMP="$(date +%Y%m%d-%H%M%S)"
DRY_RUN=0
STOP_ONLY=0
RETIRED_ONLY=0

while (($#)); do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        --stop) STOP_ONLY=1 ;;
        --retired) RETIRED_ONLY=1 ;;
        -h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
    esac
    shift
done

run() { if ((DRY_RUN)); then echo "    would run: $*"; else "$@"; fi; }

if [[ ! -s "$MANIFEST" && ! -s "$PACKAGE_MANIFEST" ]]; then
    ((RETIRED_ONLY)) || echo "  =  no dotfiles installed"
    exit 0
fi

# The FILES entry for a destination, or nothing when this checkout no longer
# ships that file. Its repo copy tells an untouched install from one you edited
# when the record has no checksum.
entry_for() {
    local entry
    for entry in "${FILES[@]}"; do
        [[ "${entry#*|}" == "$1" ]] && { printf '%s' "$entry"; return 0; }
    done
    return 0
}

# The tool a destination belongs to: its FILES folder, else its ~/.config folder.
tool_for() {
    local entry rest
    entry="$(entry_for "$1")"
    if [[ -n "$entry" ]]; then printf '%s' "${entry%%/*}"; return 0; fi
    rest="${1#"$HOME/.config/"}"
    [[ "$rest" == "$1" ]] || printf '%s' "${rest%%/*}"
}

# Whether dest is still the copy Kadomo placed: by recorded checksum, else by the repo copy.
untouched() {
    local dest="$1" sha="$2" entry
    [[ -f "$dest" && ! -L "$dest" ]] || return 1
    if [[ -n "$sha" ]]; then [[ "$(sha256 "$dest")" == "$sha" ]]; return; fi
    entry="$(entry_for "$dest")"
    [[ -n "$entry" ]] && cmp -s "$HERE/${entry%%|*}" "$dest"
}

# The command a recorded formula provides, so its process can be stopped
# (felixkratz/formulae/borders runs borders).
command_for() { printf '%s' "${1##*/}"; }

# The formulae Kadomo installed stop first, so nothing is removed while it runs.
stop_packages() {
    local formula tap cmd
    [[ -s "$PACKAGE_MANIFEST" ]] || return 0
    while IFS='|' read -r formula tap; do
        [[ -n "$formula" ]] || continue
        cmd="$(command_for "$formula")"
        if pgrep -xq "$cmd" 2>/dev/null; then
            echo "  ■  stopping $cmd"
            run pkill -x "$cmd" || true
        fi
    done <"$PACKAGE_MANIFEST"
}
stop_packages
((STOP_ONLY == 0)) || exit 0

tools=()
unconfigured=()
# With --retired, the records of files this checkout still ships stay as they are.
still_shipped=()
[[ -s "$MANIFEST" ]] && while IFS='|' read -r dest backup sha; do
    [[ -n "$dest" ]] || continue
    if ((RETIRED_ONLY)) && [[ -n "$(entry_for "$dest")" ]]; then
        still_shipped+=("$dest|$backup|$sha")
        continue
    fi
    label="${dest/#$HOME/~}"
    tool="$(tool_for "$dest")"

    if [[ -e "$dest" || -L "$dest" ]]; then
        if untouched "$dest" "$sha"; then
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
        # Nothing to put back: drop the folders install.sh made, once empty
        # (~/.vim/plugin, then ~/.vim), stopping at ~/.config and ~.
        dir="$(dirname "$dest")"
        while [[ "$dir" != "$HOME" && "$dir" != "$HOME/.config" && "$dir" == "$HOME"/* ]]; do
            if ((DRY_RUN)); then run rmdir "$dir"; break; fi
            rmdir "$dir" 2>/dev/null || break
            dir="$(dirname "$dir")"
        done
        [[ -z "$tool" ]] || unconfigured+=("$tool")
    fi
    [[ -z "$tool" ]] || tools+=("$tool")
done <"$MANIFEST"

for tool in ${unconfigured[@]+"${unconfigured[@]}"}; do unload "$tool"; done
reload_each ${tools[@]+"${tools[@]}"}

if [[ -s "$PACKAGE_MANIFEST" ]]; then
    if brew="$(find_brew)"; then
        while IFS='|' read -r formula tap; do
            [[ -n "$formula" ]] || continue
            cmd="$(command_for "$formula")"
            if "$brew" list --formula "${formula##*/}" >/dev/null 2>&1; then
                echo "  -  $cmd (brew uninstall $formula)"
                run "$brew" uninstall --formula "$formula" || echo "  !  brew uninstall $formula failed" >&2
            fi
            if [[ -n "$tap" ]] && grep -qixF "$tap" <<<"$("$brew" tap)"; then
                echo "  -  tap $tap"
                # Refuses while other formulae from the tap are still installed; those keep it.
                run "$brew" untap "$tap" 2>/dev/null || echo "  =  tap $tap kept (other formulae still use it)"
            fi
        done <"$PACKAGE_MANIFEST"
    else
        echo "  !  Homebrew not found; left these formulae installed:" >&2
        cut -d'|' -f1 "$PACKAGE_MANIFEST" | sed 's/^/       /' >&2
        # Keep the record so a later run, with Homebrew back, can finish the job.
        PACKAGE_MANIFEST=""
    fi
fi

if ((${#still_shipped[@]})); then
    # --retired: only the records of what is gone go.
    ((DRY_RUN)) || printf '%s\n' "${still_shipped[@]}" >"$MANIFEST"
    [[ -z "$PACKAGE_MANIFEST" || ! -e "$PACKAGE_MANIFEST" ]] || run rm -f -- "$PACKAGE_MANIFEST"
else
    run rm -f -- "$MANIFEST" ${PACKAGE_MANIFEST:+"$PACKAGE_MANIFEST"}
    run rmdir "$STATE_DIR" 2>/dev/null || true
fi

((DRY_RUN && !RETIRED_ONLY)) && echo "Dry run: nothing was changed."
exit 0
