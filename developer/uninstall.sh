#!/bin/bash
# Undoes developer/install.sh: turns Kadomo's Starship prompt off again (when
# install.sh turned it on) and VS Code's Kadomo colors (its color theme from
# before comes back), then uninstalls the tools install.sh installed
# with Homebrew (or Starship's own installer). Tools that were on this Mac
# before are left alone, and so is each tool's own data (npm packages,
# Rancher Desktop's VM and images), as with a plain `brew uninstall`.
#
# Rancher Desktop and VS Code are quit first (Rancher Desktop stops its VM
# cleanly; VS Code keeps unsaved work for next time).
#
# Usage: ./uninstall.sh [--dry-run | --stop]
#   --dry-run   show what would change without touching anything
#   --stop      only quit Rancher Desktop and VS Code when Kadomo installed
#               them; remove nothing
#
# Runs on the Bash 3.2 that ships with macOS.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/dev.sh"
DRY_RUN=0
STOP_ONLY=0

case "${1:-}" in
    "") ;;
    --dry-run) DRY_RUN=1 ;;
    --stop) STOP_ONLY=1 ;;
    -h|--help) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
esac

run() { if ((DRY_RUN)); then echo "    would run: $*"; else "$@"; fi; }

if [[ ! -s "$DEV_MANIFEST" ]]; then
    echo "  =  no developer installed"
    exit 0
fi

# Rancher Desktop and VS Code first, so nothing is removed while they run.
if grep -qx 'cask|rancher' "$DEV_MANIFEST" && app="$(app_path "$RANCHER_APP")"; then
    stop_app "$app" 60 || true
fi
if grep -qx 'cask|visual-studio-code' "$DEV_MANIFEST" && app="$(app_path "$VSCODE_APP")"; then
    stop_app "$app" 20 || true
fi
((STOP_ONLY == 0)) || exit 0

failed=0

# VS Code's colors first, while VS Code is still there to uninstall the
# Marketplace themes Kadomo installed for a theme.
if dev_recorded "enabled|vscode"; then
    if tv="$(theme_vscode_cmd)"; then
        if ((DRY_RUN)); then echo "  -  VS Code's Kadomo colors (theme-vscode disable)"
        else "$tv" disable || failed=1; fi
    else
        echo "  =  VS Code's Kadomo colors (already gone with the theme manager)"
    fi
fi

# The prompt first, while Starship is still there.
if dev_recorded "enabled|starship"; then
    if ts="$(theme_starship_cmd)"; then
        if ((DRY_RUN)); then echo "  -  Starship for zsh (theme-starship disable)"
        else "$ts" disable || failed=1; fi
    else
        echo "  =  Starship for zsh (already off: the theme manager is gone)"
    fi
fi

brew=""
needs_brew=0
grep -qE '^(formula|cask)\|' "$DEV_MANIFEST" && needs_brew=1
if ((needs_brew)) && ! brew="$(find_brew)"; then
    echo "  !  Homebrew not found; left these installed:" >&2
    grep -E '^(formula|cask)\|' "$DEV_MANIFEST" | sed 's/^[^|]*|/       /' >&2
    # The record stays, so a later run with Homebrew back can finish the job.
    exit 1
fi

while IFS='|' read -r kind name; do
    case "$kind" in
        formula|cask)
            if ! "$brew" list "--$kind" "$name" >/dev/null 2>&1; then
                echo "  =  $name (already removed)"
                continue
            fi
            echo "  -  $name (brew uninstall --$kind $name)"
            [[ "$name" != temurin@25 ]] || ((DRY_RUN)) || echo "     (needs your Mac password, if not given already: the JDK is in /Library/Java/JavaVirtualMachines, a system folder only an administrator can change)"
            run "$brew" uninstall "--$kind" "$name" || { echo "  !  brew uninstall --$kind $name failed" >&2; failed=1; }
            ;;
        script)
            [[ -f "$name" ]] || continue
            echo "  -  $(short_path "$name") (Starship, from its installer)"
            run rm -f -- "$name"
            ;;
    esac
done <"$DEV_MANIFEST"

if ((failed == 0)); then
    run rm -f -- "$DEV_MANIFEST"
    run rmdir "$STATE_DIR" 2>/dev/null || true
fi

((DRY_RUN)) && echo "Dry run: nothing was changed."
exit "$failed"
