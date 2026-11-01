#!/bin/bash
# Installs developer tools with Homebrew and turns on a themed prompt:
#   node       Node.js with npm                    brew install node
#   java       Java 25 LTS, the Temurin JDK        brew install --cask temurin@25
#              (macOS asks for your password: it goes in /Library/Java)
#   rancher    Rancher Desktop: containers and     brew install --cask rancher
#              Kubernetes (docker, nerdctl, kubectl)
#   vscode     Visual Studio Code, in the Kadomo   brew install --cask visual-studio-code,
#              theme's colors                      then theme-vscode enable
#   starship   the Starship prompt for zsh, in     brew install starship, then
#              the Kadomo theme's colors           theme-starship enable
# A tool already on this Mac, however it got there, is used as it is. Each
# tool Kadomo installs is recorded, so uninstall.sh removes exactly those.
# VS Code and Starship need the theme manager (kadomo-theme-manager/) for
# their colors.
#
# Usage: ./install.sh [--dry-run] [--only LIST] [--yes] [--use-kadomo-prompt]
#                     [--starship-script]
#   --dry-run            show what would change without touching anything
#   --only LIST          only these, comma-separated (node,java,rancher,vscode,starship)
#   --yes                ask nothing; a prompt setup of yours is left alone
#   --use-kadomo-prompt  turn on Kadomo's prompt even over a prompt setup of yours
#   --starship-script    without Homebrew, install Starship with its official
#                        script (https://starship.rs/install.sh) into ~/.local/bin
#
# Runs on the Bash 3.2 that ships with macOS.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/dev.sh"
DRY_RUN=0
ONLY=""
ASSUME_YES=0
USE_KADOMO=0
STARSHIP_SCRIPT=0

while (($#)); do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        --yes|-y) ASSUME_YES=1 ;;
        --use-kadomo-prompt) USE_KADOMO=1 ;;
        --starship-script) STARSHIP_SCRIPT=1 ;;
        --only)
            shift; [[ $# -gt 0 ]] || { echo "--only needs a list (try --help)" >&2; exit 2; }
            ONLY="$1"
            for key in ${ONLY//,/ }; do
                dev_entry "$key" >/dev/null || { echo "Unknown item for --only: $key (known: $(dev_keys))" >&2; exit 2; }
            done
            ;;
        -h|--help) sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
    esac
    shift
done

selected() { [[ -z "$ONLY" || ",$ONLY," == *",$1,"* ]]; }

record() {
    ((DRY_RUN)) && return 0
    dev_recorded "$1" && return 0
    mkdir -p "$(dirname "$DEV_MANIFEST")"
    printf '%s\n' "$1" >>"$DEV_MANIFEST"
}

# What still needs you, printed together at the end.
todo=()
failed=0
brew=""

# Starship from its official script, into ~/.local/bin (no sudo). Downloaded to
# a file first, so a cut-off download never runs half a script.
starship_from_script() {
    local tmp dir="$HOME/.local/bin"
    echo "  +  Starship (official installer into $(short_path "$dir"))"
    if ((DRY_RUN)); then echo "    would run: curl -fsSL https://starship.rs/install.sh | sh -s -- --yes --bin-dir $dir"; return 0; fi
    tmp="$(mktemp "${TMPDIR:-/tmp}/starship-install.XXXXXX")"
    if ! curl -fsSL --retry 2 https://starship.rs/install.sh -o "$tmp"; then
        rm -f -- "$tmp"
        echo "  !  could not download https://starship.rs/install.sh (offline?); run this again later" >&2
        return 1
    fi
    mkdir -p "$dir"
    sh "$tmp" --yes --bin-dir "$dir" || { rm -f -- "$tmp"; echo "  !  Starship's installer failed" >&2; return 1; }
    rm -f -- "$tmp"
    [[ -x "$dir/starship" ]] && record "script|$dir/starship"
}

# Installs one tool. Returns 1 when it could not be installed.
install_tool() {
    local key="$1" kind="$2" name="$3" label="$4"
    if [[ -z "$brew" ]] && ! brew="$(find_brew)"; then
        brew=""
        if [[ "$key" == starship ]] && ((STARSHIP_SCRIPT)); then starship_from_script; return; fi
        echo "  !  $label needs Homebrew, which is not installed; Kadomo does not install it for you" >&2
        if [[ "$key" == starship ]]; then
            todo+=("Starship: install Homebrew (https://brew.sh) and run this again, or run it with --starship-script to use Starship's official installer (no Homebrew, into ~/.local/bin).")
        else
            todo+=("$label: install Homebrew (https://brew.sh), then run this again.")
        fi
        return 1
    fi
    if "$brew" list "--$kind" "$name" >/dev/null 2>&1; then
        echo "  =  $label (already installed with Homebrew)"
        return 0
    fi
    echo "  +  $label (brew install --$kind $name)"
    if ((DRY_RUN)); then echo "    would run: $brew install --$kind $name"; return 0; fi
    [[ "$key" != java ]] || echo "     macOS asks for your password: the JDK installs in /Library/Java/JavaVirtualMachines"
    if ! "$brew" install "--$kind" "$name"; then
        echo "  !  brew install --$kind $name failed (offline, or out of space?); run this again to retry" >&2
    fi
    # Recorded whenever Homebrew now has it, even after a failure part way, so
    # uninstall.sh still removes it.
    if "$brew" list "--$kind" "$name" >/dev/null 2>&1; then record "$kind|$name"; else return 1; fi
}

for entry in "${DEV_ITEMS[@]}"; do
    IFS='|' read -r key kind name label <<<"$entry"
    selected "$key" || continue
    if dev_present "$key"; then
        echo "  =  $label (already installed: $(dev_version "$key" || echo "version unknown"))"
    else
        install_tool "$key" "$kind" "$name" "$label" || { failed=1; continue; }
        ((DRY_RUN)) && continue
        # Checked again, the way the checklist checks: on this Mac and answering.
        if dev_present "$key"; then
            echo "  ✓  $label $(dev_version "$key" || true)"
        else
            echo "  !  $label was installed but is not found; open a new terminal and run this again" >&2
            failed=1
            continue
        fi
    fi
    case "$key" in
        rancher)
            if app_path "Docker.app" >/dev/null; then
                todo+=("Docker Desktop is installed too. Both provide the docker command and the Docker socket: run one at a time.")
            fi
            ((DRY_RUN)) || todo+=("Open Rancher Desktop once to finish setting it up: it asks for the container engine and whether to run Kubernetes, and puts docker, nerdctl, and kubectl in ~/.rd/bin (it can add that to your PATH itself).")
            ;;
    esac
done

# --- Starship: on for zsh, in the theme's colors --------------------------

enable_starship() {
    local ts args=() out status tries=0 flag question answer
    if ! ts="$(theme_starship_cmd)"; then
        echo "  !  Starship needs the theme manager for its colors; it is not installed" >&2
        todo+=("Install the theme manager (${KADOMO_INSTALL_CMD:-./install.sh}, \"Theme manager and themes\"), then run: theme-starship enable")
        return 0
    fi
    ((USE_KADOMO)) && args+=(--use-kadomo)
    if ((DRY_RUN)); then echo "  ▶  would run: theme-starship enable ${args[*]:-}"; return 0; fi
    echo "  ▶  theme-starship enable ${args[*]:-}"
    while :; do
        status=0
        out="$("$ts" enable ${args[@]+"${args[@]}"} 2>&1)" || status=$?
        printf '%s\n' "$out"
        ((status == 3 && tries < 2)) || break
        tries=$((tries + 1))
        # Your setup needs a decision: ask, unless told not to.
        if [[ "$out" == *--edit-symlinked* ]]; then
            flag=--edit-symlinked question="Add Kadomo's block to the file your .zshrc symlink points to?"
        else
            flag=--use-kadomo question="Use Kadomo's prompt anyway?"
        fi
        if ((ASSUME_YES)) || [[ ! -r /dev/tty ]] || ! { : </dev/tty; } 2>/dev/null; then break; fi
        read -r -p "  $question [y/N] " answer </dev/tty || answer=""
        [[ "$answer" == [yY]* ]] || { echo "  =  your prompt setup is left as it is"; break; }
        args+=("$flag")
        [[ "$flag" == --use-kadomo ]] || [[ " ${args[*]} " == *" --use-kadomo "* ]] || args+=(--use-kadomo)
    done
    case "$status" in
        0) record "enabled|starship" ;;
        3) todo+=("Starship is installed but not on for zsh, to keep your prompt setup (see above). To use Kadomo's: theme-starship enable --use-kadomo") ;;
        *) todo+=("Starship could not be turned on (see above). See theme-starship status, then run theme-starship enable.") ; failed=1 ;;
    esac
}

if selected starship && { dev_present starship || ((DRY_RUN)); }; then
    enable_starship
fi

# --- VS Code: in the theme's colors -----------------------------------------
# Each theme shows as Kadomo's own VS Code theme, drawn from its colors, or
# the Marketplace theme an Omarchy theme names (see theme-vscode).

enable_vscode() {
    local tv
    if ! tv="$(theme_vscode_cmd)"; then
        echo "  !  VS Code takes its colors from the theme manager; it is not installed" >&2
        todo+=("Install the theme manager (${KADOMO_INSTALL_CMD:-./install.sh}, \"Theme manager and themes\"), then run: theme-vscode enable")
        return 0
    fi
    if ((DRY_RUN)); then echo "  ▶  would run: theme-vscode enable"; return 0; fi
    echo "  ▶  theme-vscode enable"
    if "$tv" enable; then
        record "enabled|vscode"
    else
        todo+=("VS Code is installed but not in the theme's colors (see above). Run theme-vscode enable to retry.")
        failed=1
    fi
}

if selected vscode && { dev_present vscode || ((DRY_RUN)); }; then
    enable_vscode
fi

if ((${#todo[@]})); then
    printf '\n  Still needs you:\n'
    for ((i=0; i<${#todo[@]}; i++)); do
        printf '%s\n' "${todo[i]}" | fold -s -w 76 | sed "s/ *$//; 1s/^/  $((i+1)). /; 1!s/^/     /"
    done
fi

((DRY_RUN)) && echo "Dry run: nothing was changed."
exit "$failed"
