#!/bin/bash
# Installs Kadomo. Pick what to set up by category, or go through every item
# under Advanced; nothing is installed until you confirm the review.
#   Kadomo Core   Homebrew (when it is not here yet), Kadomo Menu and its
#                 font, the OmniWM window manager, Ghostty, kitty, btop, htop,
#                 the Starship prompt, and the theme manager with its themes
#                                                             (on by default)
#   Developer     Neovim and Kadomo's Vim and Neovim settings, Node.js,
#                 Java 25, Rancher Desktop, and VS Code in the theme's colors
#   Gaming        Moonlight, and a Windows-style mouse in it (LinearMouse)
#   Other         Firefox
# Each component's own installer does the work: homebrew/, kadomo-menu/, omniwm/,
# dotfiles/, apps/, moonlight-mouse/, kadomo-theme-manager/, developer/. What an
# older Kadomo installed for AeroSpace (Kadomo uses OmniWM only now) is removed
# first. Remove everything again with ./uninstall.sh.
#
# Usage: ./install.sh [--yes | --only LIST | --version]
#   --yes         ask nothing, and install Kadomo Core
#   --only LIST   ask nothing, and install these categories, comma-separated:
#                 core, developer, gaming, other
#   --version     print the Kadomo version (from VERSION) and exit
#
# Without a checkout, like Homebrew's installer (KADOMO_REF picks a released
# version such as 0.1.1; the default is the latest release, and there is no
# installing from a branch):
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/kadomo-tech/kadomo-alpha/main/install.sh)"
# It downloads Kadomo to ~/.local/share/kadomo/source and runs this from
# there; that copy's uninstall.sh removes everything again, the copy too.
#
# Runs on the Bash 3.2 that ships with macOS.
set -euo pipefail

KADOMO_REPO="kadomo-tech/kadomo-alpha"
KADOMO_SOURCE_DIR="${KADOMO_SOURCE_DIR:-$HOME/.local/share/kadomo/source}"

# Run from curl rather than a checkout: there is nothing next to this script,
# so download Kadomo into KADOMO_SOURCE_DIR and run the install.sh in it.
# Everything happens in this function, called on its last line, so a
# download of this script cut off partway runs nothing.
kadomo_fetch_and_run() {
    local ref="${KADOMO_REF:-}" latest url dir="$KADOMO_SOURCE_DIR" short tty=/dev/stdin
    fail() { printf '\n  ✗ %s\n\n' "$*" >&2; exit 1; }
    [[ "$(uname -s)" == Darwin ]] || fail "Kadomo is for macOS."
    ((EUID != 0)) || fail "run this as your own user, not with sudo."
    case "$dir" in /|"$HOME"|"$HOME"/|"") fail "KADOMO_SOURCE_DIR cannot be $dir." ;; esac
    [[ ! -e "$dir/.git" ]] || fail "$dir is a git checkout; run its ./install.sh instead."
    if [[ -z "$ref" ]]; then
        # The latest release redirects to its tag; without one, to the releases page.
        latest="$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$KADOMO_REPO/releases/latest" 2>/dev/null || true)"
        case "$latest" in
            */releases/tag/*) ref="${latest##*/releases/tag/}" ;;
            *) fail "could not find a Kadomo release to install (offline, or none published yet)." ;;
        esac
    fi
    # Releases only: a version tag, never a branch.
    [[ "$ref" =~ ^v?[0-9]+(\.[0-9]+)*$ ]] || fail "KADOMO_REF must be a released version, such as 0.1.1 (got $ref)."
    url="https://github.com/$KADOMO_REPO/archive/refs/tags/v${ref#v}.tar.gz"
    printf '\n  Downloading Kadomo (%s)...\n' "$ref"
    mkdir -p "$(dirname "$dir")"
    rm -rf -- "$dir.download"
    mkdir "$dir.download"
    if ! curl -fsSL "$url" | tar -xzf - -C "$dir.download" --strip-components 1; then
        rm -rf -- "$dir.download"
        fail "could not download Kadomo $ref from $url"
    fi
    [[ -f "$dir.download/install.sh" && -f "$dir.download/VERSION" ]] || { rm -rf -- "$dir.download"; fail "the download of Kadomo $ref is not complete."; }
    # Replaces the copy an earlier install left, so its uninstall.sh matches what is installed.
    rm -rf -- "$dir.old"
    [[ ! -e "$dir" ]] || mv "$dir" "$dir.old"
    mv "$dir.download" "$dir"
    rm -rf -- "$dir.old"
    short="$dir"; [[ "$dir" != "$HOME"/* ]] || short="~${dir#"$HOME"}"
    printf '  Kadomo %s is in %s\n' "$(cat "$dir/VERSION")" "$short"
    export KADOMO_INSTALL_CMD="/bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/$KADOMO_REPO/main/install.sh)\""
    export KADOMO_UNINSTALL_CMD="$short/uninstall.sh"
    # Piped to bash, stdin is this script: the menus read the terminal instead.
    if [[ ! -t 0 ]] && { : </dev/tty; } 2>/dev/null; then tty=/dev/tty; fi
    exec /bin/bash "$dir/install.sh" ${1+"$@"} <"$tty"
}
if [[ -z "${BASH_SOURCE[0]:-}" || ! -f "$(dirname "${BASH_SOURCE[0]}")/lib/tui.sh" ]]; then kadomo_fetch_and_run ${1+"$@"}; fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export KADOMO_INSTALL_CMD="${KADOMO_INSTALL_CMD:-./install.sh}" KADOMO_UNINSTALL_CMD="${KADOMO_UNINSTALL_CMD:-./uninstall.sh}"
KADOMO_VERSION="$(cat "$ROOT/VERSION")"
ASSUME_YES=0
ONLY_CATS=""

source "$ROOT/lib/tui.sh"
source "$ROOT/apps/apps.sh"
source "$ROOT/developer/dev.sh"
source "$ROOT/homebrew/homebrew.sh"
OMNIWM_SOURCE_BIN="$ROOT/omniwm/bin"
source "$ROOT/omniwm/omniwm.sh"

CATS=("Kadomo Core" Developer Gaming Other)
CAT_KEYS=(core developer gaming other)
CAT_BLURB=(
    "Homebrew, Kadomo Menu, OmniWM, Ghostty, kitty, themes, Starship"
    "Neovim, Node.js, Java 25, Rancher Desktop, VS Code"
    "Moonlight, with a Windows-style mouse in it"
    "Firefox"
)

case "${1:-}" in
    "") ;;
    --yes|-y) ASSUME_YES=1 ;;
    --only)
        [[ -n "${2:-}" ]] || die "--only needs a list: core, developer, gaming, other"
        ONLY_CATS="$2"; ASSUME_YES=1
        for key in ${ONLY_CATS//,/ }; do
            [[ " ${CAT_KEYS[*]} " == *" $key "* ]] || die "unknown category for --only: $key (known: ${CAT_KEYS[*]})"
        done
        ;;
    --version|-v) echo "$KADOMO_VERSION"; exit 0 ;;
    -h|--help) sed -n '2,29p' "$ROOT/install.sh" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown option: $1 (try --help)" ;;
esac

[[ "$(uname -s)" == Darwin ]] || die "Kadomo is for macOS."
((EUID != 0)) || die "run this as your own user, not with sudo."

# --- the items -----------------------------------------------------------------

# One row per item: category | component | the component's --only key | label | detail.
# The components install in their own order (see install_selected), whatever the order here.
ITEMS=(
    "Kadomo Core|homebrew|homebrew|Homebrew|the package manager the apps come from; asks for your password"
    "Kadomo Core|kadomo-menu|app|Kadomo Menu|the launcher, in ~/Applications, and the kadomo-menu command"
    "Kadomo Core|kadomo-menu|font|JetBrainsMono Nerd Font|for the launcher and kitty; 7 MB from GitHub"
    "Kadomo Core|kadomo-menu|start|Start Kadomo Menu|opens it now; it starts at login by default"
    "Kadomo Core|omniwm|omniwm|OmniWM|window manager: scrolling and tiling, its border in the theme's colors"
    "Kadomo Core|apps|ghostty|Ghostty|terminal app, from Homebrew"
    "Kadomo Core|dotfiles|ghostty|Ghostty config|~/.config/ghostty; a different file there is backed up"
    "Kadomo Core|apps|kitty|kitty|terminal app, from Homebrew"
    "Kadomo Core|dotfiles|kitty|kitty config|~/.config/kitty; a different file there is backed up"
    "Kadomo Core|apps|btop|btop|system monitor, from Homebrew"
    "Kadomo Core|apps|htop|htop|process viewer, from Homebrew"
    "Kadomo Core|developer|starship|Starship prompt|zsh prompt in the theme's colors; a marked block in .zshrc"
    "Kadomo Core|kadomo-theme-manager|themes|Theme manager and themes|theme-set and 5 themes; Ghostty, kitty, OmniWM, and editors follow it"
    "Kadomo Core|kadomo-theme-manager|btop|btop follows the theme|btop's color theme follows Kadomo's"
    "Kadomo Core|kadomo-theme-manager|desktop|Wallpaper and light/dark|each theme sets the desktop picture and light or dark mode"
    "Developer|apps|neovim|Neovim|the nvim editor, from Homebrew"
    "Developer|dotfiles|editors|Vim and Neovim settings|line numbers on; your vimrc and init.lua are left alone"
    "Developer|developer|node|Node.js|JavaScript runtime with npm, from Homebrew"
    "Developer|developer|java|Java 25 (Temurin JDK)|from Homebrew, into /Library/Java; asks for your password"
    "Developer|developer|rancher|Rancher Desktop|containers and Kubernetes: docker, nerdctl, kubectl"
    "Developer|developer|vscode|Visual Studio Code|editor from Homebrew; its colors follow the theme, Omarchy's too"
    "Gaming|apps|moonlight|Moonlight|game streaming client, from Homebrew"
    "Gaming|moonlight-mouse|linearmouse|Moonlight Mouse Optimization|in Moonlight only: no acceleration, Windows-style scrolling (LinearMouse)"
    "Other|apps|firefox|Firefox|web browser, from Homebrew"
)
ITEM_CAT=(); ITEM_COMPONENT=(); ITEM_KEY=(); ITEM_LABEL=(); ITEM_DETAIL=(); ITEM_ON=(); ITEM_PRESENT=()
for row in "${ITEMS[@]}"; do
    IFS='|' read -r cat component key label detail <<<"$row"
    for ((c=0; c<${#CATS[@]}; c++)); do [[ "${CATS[c]}" != "$cat" ]] || break; done
    ITEM_CAT+=("$c"); ITEM_COMPONENT+=("$component"); ITEM_KEY+=("$key")
    ITEM_LABEL+=("$label"); ITEM_DETAIL+=("$detail"); ITEM_ON+=(0); ITEM_PRESENT+=(0)
done
N=${#ITEM_KEY[@]}

# Both variants: the launcher's Nerd Font and the fixed-pitch Nerd Font Mono kitty uses.
font_installed() {
    local name
    for name in JetBrainsMonoNerdFont-Regular.ttf JetBrainsMonoNerdFontMono-Regular.ttf; do
        [[ -e "$HOME/Library/Fonts/$name" || -e "/Library/Fonts/$name" ]] || return 1
    done
}

# Items already on this Mac with nothing left to do. Picking their category
# leaves them off; Advanced can still turn them on.
for ((i=0; i<N; i++)); do
    present=0
    case "${ITEM_COMPONENT[i]}:${ITEM_KEY[i]}" in
        homebrew:homebrew)
            if find_brew >/dev/null; then present=1
            elif ! is_admin; then present=1; ITEM_DETAIL[i]="needs an administrator account: ask one to install it (https://brew.sh)"; fi
            ;;
        kadomo-menu:font) font_installed && present=1 ;;
        omniwm:omniwm)
            if ! omniwm_supported; then present=1; ITEM_DETAIL[i]="not on this Mac: OmniWM $(omniwm_requirement)"
            elif omniwm_up_to_date; then present=1
            elif omniwm_app >/dev/null; then ITEM_DETAIL[i]="OmniWM is already installed; makes it Kadomo's window manager"; fi
            ;;
        apps:*) app_present "$(app_entry "${ITEM_KEY[i]}")" && present=1 ;;
        developer:starship) dev_present starship && ITEM_DETAIL[i]="already installed; turns it on for zsh, in the theme's colors" ;;
        developer:*) dev_present "${ITEM_KEY[i]}" && present=1 ;;
    esac
    if ((present)); then
        ITEM_PRESENT[i]=1
        [[ "${ITEM_COMPONENT[i]}:${ITEM_DETAIL[i]}" == "omniwm:not on this Mac"* \
            || "${ITEM_COMPONENT[i]}:${ITEM_DETAIL[i]}" == "homebrew:needs an administrator"* ]] \
            || ITEM_DETAIL[i]="already installed"
    fi
done

# Whether an item installs something with Homebrew that is not here yet.
needs_brew() {
    ((ITEM_PRESENT[$1] == 0)) || return 1
    case "${ITEM_COMPONENT[$1]}:${ITEM_KEY[$1]}" in
        apps:*|developer:node|developer:java|developer:rancher|developer:vscode) return 0 ;;
        developer:starship) ! dev_present starship ;;
        omniwm:*) ! omniwm_app >/dev/null ;;
        moonlight-mouse:*) ! app_path LinearMouse.app >/dev/null ;;
        *) return 1 ;;
    esac
}
BREW_PATH="$(find_brew || true)"

# --- choosing --------------------------------------------------------------------

# Turns a category on (its items that are not installed yet; all of them when
# every one is) or off.
set_category() {
    local c="$1" on="$2" i n=0
    for ((i=0; i<N; i++)); do
        ((ITEM_CAT[i] == c)) || continue
        if ((on && ITEM_PRESENT[i] == 0)); then ITEM_ON[i]=1; n=$((n+1)); else ITEM_ON[i]=0; fi
    done
    ((on && n == 0)) || return 0
    for ((i=0; i<N; i++)); do ((ITEM_CAT[i] != c)) || ITEM_ON[i]=1; done
}

# x when a category's items are on, - when only some are, a space when none are.
category_mark() {
    local c="$1" i on=0 total=0 need=0 need_on=0
    for ((i=0; i<N; i++)); do
        ((ITEM_CAT[i] == c)) || continue
        total=$((total+1)); ((ITEM_ON[i] == 0)) || on=$((on+1))
        if ((ITEM_PRESENT[i] == 0)); then need=$((need+1)); ((ITEM_ON[i] == 0)) || need_on=$((need_on+1)); fi
    done
    if ((on == 0)); then printf ' '
    elif ((need > 0 && need_on == need)) || ((need == 0 && on == total)); then printf x
    else printf -- -; fi
}

category_detail() {
    local c="$1" i on=0 total=0 need=0
    for ((i=0; i<N; i++)); do
        ((ITEM_CAT[i] == c)) || continue
        total=$((total+1)); ((ITEM_ON[i] == 0)) || on=$((on+1)); ((ITEM_PRESENT[i])) || need=$((need+1))
    done
    if [[ "$(category_mark "$c")" == - ]]; then printf 'your choice: %s of %s items' "$on" "$total"
    elif ((need == 0)); then printf 'already installed'
    else printf '%s' "${CAT_BLURB[c]}"; fi
}

selected_count() { local i n=0; for ((i=0; i<N; i++)); do n=$((n+ITEM_ON[i])); done; printf '%s' "$n"; }

# The title and status lines over each screen; "compact" leaves out the logo.
banner() {
    if [[ "${1:-}" == compact ]]; then printf '\n'; else logo; fi
    printf '  %sInstall Kadomo %s%s\n\n' "$BOLD" "$KADOMO_VERSION" "$RESET"
    if [[ -n "$BREW_PATH" ]]; then printf '  %sHomebrew%s  %s\n' "$DIM" "$RESET" "$(dirname "$(dirname "$BREW_PATH")")"
    elif item_on homebrew homebrew; then printf '  %sHomebrew%s  not installed yet: Kadomo Core installs it first\n' "$DIM" "$RESET"
    else printf '  %sHomebrew%s  %snot installed: apps need it (Kadomo Core › Homebrew)%s\n' "$DIM" "$RESET" "$RED" "$RESET"; fi
    printf '  %sSelected%s  %s of %s items\n\n' "$DIM" "$RESET" "$(selected_count)" "$N"
}

draw_main() {
    local cursor="$1" c mark
    clear_screen; banner
    printf '  What should Kadomo set up?\n\n'
    for ((c=0; c<${#CATS[@]}; c++)); do
        mark="$(category_mark "$c")"
        if ((c == cursor)); then printf '%s > [%s] %-12s %s%s\n' "$CYAN" "$mark" "${CATS[c]}" "$(category_detail "$c")" "$RESET"
        else printf '   [%s] %-12s %s%s%s\n' "$mark" "${CATS[c]}" "$DIM" "$(category_detail "$c")" "$RESET"; fi
    done
    printf '\n'
    if ((cursor == ${#CATS[@]})); then printf '%s >     %-12s %s%s\n' "$CYAN" "Advanced" "go through every item and turn each on or off" "$RESET"
    else printf '       %-12s %s%s%s\n' "Advanced" "$DIM" "go through every item and turn each on or off" "$RESET"; fi
    printf '\n  %s↑/↓ move · Space toggle · Enter review (on Advanced: open it) · q quit%s\n' "$DIM" "$RESET"
}

# The first screen. Returns 0 to review, 1 to quit.
main_menu() {
    local cursor=0 n=$((${#CATS[@]} + 1))
    while :; do
        draw_main "$cursor"
        read_key
        case "$KEY" in
            up) cursor=$(((cursor+n-1)%n)) ;;
            down) cursor=$(((cursor+1)%n)) ;;
            space)
                if ((cursor == n-1)); then advanced && return 0
                elif [[ "$(category_mark "$cursor")" == x ]]; then set_category "$cursor" 0
                else set_category "$cursor" 1; fi
                ;;
            enter|right) if ((cursor == n-1)); then advanced && return 0; elif [[ "$KEY" == enter ]]; then return 0; fi ;;
            a|A) advanced && return 0 ;;
            q|Q|escape) return 1 ;;
        esac
    done
}

# Advanced: every item under its category. LINE_ROWS holds each line's item,
# -1 for a heading (its text in LINE_TEXT), or -2 for a blank line.
LINE_ROWS=(); LINE_TEXT=(); LABEL_WIDTH=0
prev=-1
for ((i=0; i<N; i++)); do
    if ((ITEM_CAT[i] != prev)); then
        ((prev < 0)) || { LINE_ROWS+=(-2); LINE_TEXT+=(""); }
        prev=${ITEM_CAT[i]}
        LINE_ROWS+=(-1); LINE_TEXT+=("${CATS[ITEM_CAT[i]]}")
    fi
    LINE_ROWS+=("$i"); LINE_TEXT+=("")
    ((${#ITEM_LABEL[i]} <= LABEL_WIDTH)) || LABEL_WIDTH=${#ITEM_LABEL[i]}
done

draw_advanced() {
    local cursor="$1" total=${#LINE_ROWS[@]} rows cols height start=0 end n r line=0 check detail
    rows="$(term_rows)"; cols="$(term_cols)"
    clear_screen
    # Logo 8 lines, title and status 5, scroll marks 2, key hints 2.
    height=$((rows - 18))
    if ((height < total && height < 14)); then banner compact; height=$((rows - 10)); else banner; fi
    ((height >= 4)) || height=4
    for ((n=0; n<total; n++)); do [[ "${LINE_ROWS[n]}" != "$cursor" ]] || line=$n; done
    if ((total > height)); then
        start=$((line - height / 2)); ((start >= 0)) || start=0
        ((start <= total - height)) || start=$((total - height))
    fi
    end=$((start + height)); ((end <= total)) || end=$total
    if ((start > 0)); then printf '  %s↑ more%s\n' "$DIM" "$RESET"; else printf '\n'; fi
    for ((n=start; n<end; n++)); do
        r="${LINE_ROWS[n]}"
        if ((r == -2)); then printf '\n'; continue; fi
        if ((r == -1)); then printf '  %s%s%s\n' "$BOLD" "${LINE_TEXT[n]}" "$RESET"; continue; fi
        check=' '; ((ITEM_ON[r] == 0)) || check=x
        # One line each, so the list scrolls right.
        detail="${ITEM_DETAIL[r]}"
        ((cols - LABEL_WIDTH - 9 > 10)) && detail="${detail:0:$((cols - LABEL_WIDTH - 9))}"
        if ((r == cursor)); then printf '%s > [%s] %-*s  %s%s\n' "$CYAN" "$check" "$LABEL_WIDTH" "${ITEM_LABEL[r]}" "$detail" "$RESET"
        else printf '   [%s] %-*s  %s%s%s\n' "$check" "$LABEL_WIDTH" "${ITEM_LABEL[r]}" "$DIM" "$detail" "$RESET"; fi
    done
    if ((end < total)); then printf '  %s↓ more%s\n' "$DIM" "$RESET"; else printf '\n'; fi
    printf '\n  %s↑/↓ move · Space toggle · g category on/off · a all/none · Enter review · Esc back%s\n' "$DIM" "$RESET"
}

# Turns every item on, or off when all are on already. With a category, only its items.
toggle_items() {
    local i all=1 c="${1:--1}"
    for ((i=0; i<N; i++)); do ((c >= 0 && ITEM_CAT[i] != c)) || ((ITEM_ON[i])) || all=0; done
    for ((i=0; i<N; i++)); do ((c >= 0 && ITEM_CAT[i] != c)) || ITEM_ON[i]=$((1-all)); done
}

# Returns 0 to review, 1 to go back to the categories.
advanced() {
    local cursor=0
    while :; do
        draw_advanced "$cursor"
        read_key
        case "$KEY" in
            up) cursor=$(((cursor+N-1)%N)) ;;
            down) cursor=$(((cursor+1)%N)) ;;
            space) ITEM_ON[cursor]=$((1-ITEM_ON[cursor])) ;;
            g|G) toggle_items "${ITEM_CAT[cursor]}" ;;
            a|A) toggle_items ;;
            enter) return 0 ;;
            escape|left|q|Q) return 1 ;;
        esac
    done
}

# --- the review --------------------------------------------------------------------

item_on() { # <component> <key>
    local i
    for ((i=0; i<N; i++)); do
        [[ "${ITEM_COMPONENT[i]}" == "$1" && "${ITEM_KEY[i]}" == "$2" ]] && { ((ITEM_ON[i])); return; }
    done
    return 1
}
component_on() { local i; for ((i=0; i<N; i++)); do [[ "${ITEM_COMPONENT[i]}" != "$1" ]] || ((ITEM_ON[i] == 0)) || return 0; done; return 1; }

# The --only list for one component, from the items that are on.
keys_for() {
    local i keys=""
    for ((i=0; i<N; i++)); do
        [[ "${ITEM_COMPONENT[i]}" == "$1" ]] && ((ITEM_ON[i])) && keys="$keys,${ITEM_KEY[i]}"
    done
    printf '%s' "${keys#,}"
}

# The labels of the items that are on in one component, joined.
labels_for() {
    local i out=""
    for ((i=0; i<N; i++)); do
        [[ "${ITEM_COMPONENT[i]}" == "$1" ]] && ((ITEM_ON[i])) && out="${out:+$out, }${ITEM_LABEL[i]}"
    done
    printf '%s' "$out"
}

details() {
    local i shown=-1
    clear_screen; logo
    printf '  %sWhat each selected item does%s\n' "$BOLD" "$RESET"
    for ((i=0; i<N; i++)); do
        ((ITEM_ON[i])) || continue
        ((ITEM_CAT[i] == shown)) || printf '\n  %s%s%s\n' "$DIM" "${CATS[ITEM_CAT[i]]}" "$RESET"
        shown=${ITEM_CAT[i]}
        printf '  %s·%s %s  %s%s%s\n' "$CYAN" "$RESET" "${ITEM_LABEL[i]}" "$DIM" "${ITEM_DETAIL[i]}" "$RESET"
    done
    pause review
}

# A summary of what will happen, then Yes or "No, change it". Returns 0 to install.
review() {
    local c i width names fields=() present=() brew_needed=() asks=() off=0 answer
    width=$(($(term_cols) - 22)); ((width <= 64)) || width=64; ((width >= 30)) || width=30
    for ((c=0; c<${#CATS[@]}; c++)); do
        names=()
        for ((i=0; i<N; i++)); do
            ((ITEM_CAT[i] == c)) || continue
            if ((ITEM_ON[i])); then names+=("${ITEM_LABEL[i]}"); needs_brew "$i" && brew_needed+=("${ITEM_LABEL[i]}")
            else off=$((off+1)); fi
        done
        ((${#names[@]} == 0)) || fields+=("${CATS[c]}${TAB}$(wrap_list "$width" "${names[@]}")")
        # What is here already in a category you picked, and so left off.
        if ((${#names[@]})); then
            for ((i=0; i<N; i++)); do ((ITEM_CAT[i] != c || ITEM_ON[i] || ITEM_PRESENT[i] == 0)) || present+=("${ITEM_LABEL[i]}"); done
        fi
    done
    ((${#present[@]} == 0)) || fields+=("Already here${TAB}$(wrap_list "$width" "${present[@]}")"$'\n'"(left as they are)")
    if [[ -z "$BREW_PATH" && ${#brew_needed[@]} -gt 0 ]] && ! item_on homebrew homebrew; then
        fields+=("No Homebrew${TAB}$(wrap_list "$width" "${brew_needed[@]}")"$'\n'"need Homebrew and are skipped: turn on Kadomo Core › Homebrew")
    fi
    if aerospace_leftovers; then
        fields+=("Removes${TAB}what an older Kadomo installed for AeroSpace"$'\n'"(Kadomo uses OmniWM only now)")
    fi
    asks=()
    ! item_on homebrew homebrew || asks+=("Homebrew")
    ! item_on developer java || asks+=("Java 25 (it installs in /Library/Java)")
    ((${#asks[@]} == 0)) || fields+=("Asks you${TAB}your Mac password, for $(wrap_list "$width" "${asks[@]}" | sed 's/, \([^,]*\)$/ and \1/')")
    ! item_on homebrew homebrew || fields+=("Homebrew${TAB}installs first; it adds the Xcode Command Line Tools"$'\n'"if they are missing, which can take a few minutes")
    ! component_on dotfiles || fields+=("Backups${TAB}a config that differs is backed up next to itself;"$'\n'"$KADOMO_UNINSTALL_CMD puts it back")
    ((off == 0)) || fields+=("Not selected${TAB}$off $( ((off == 1)) && echo item || echo items)")
    while :; do
        clear_screen; logo
        printf "  Let's set up Kadomo...\n\n"
        summary_table "${fields[@]}"
        printf '\n  %sDoes this look right?%s\n\n' "$CYAN" "$RESET"
        buttons "Yes, install" "No, change it" && answer=0 || answer=$?
        case "$answer" in
            0) return 0 ;;
            3) details ;;
            *) return 1 ;;
        esac
    done
}

# --- installing ------------------------------------------------------------------

failed=()
todos=()
run_component() { # <label> <step or step_open> <component> [args...]
    local label="$1" how="$2" component="$3" line
    shift 3
    "$how" "$label" "$ROOT/$component/install.sh" ${1+"$@"} || failed+=("$label")
    while IFS= read -r line; do [[ -z "$line" ]] || todos+=("$line"); done < <(step_todos)
}

install_selected() {
    local keys dev_args=()
    # First: everything after it installs with Homebrew. It asks for your password, so it runs in the open.
    if component_on homebrew; then
        if [[ -t 0 ]]; then run_component "Homebrew" step_open homebrew; else run_component "Homebrew" step homebrew; fi
        BREW_PATH="$(find_brew || true)"
    fi
    # Kadomo uses OmniWM only now: AeroSpace from an older Kadomo goes, with its
    # config and JankyBorders, whatever else is picked.
    if aerospace_leftovers; then
        step "Removing AeroSpace from an older Kadomo" "$ROOT/omniwm/remove-aerospace.sh" || failed+=("Removing AeroSpace")
        step "Removing AeroSpace's config and JankyBorders" "$ROOT/dotfiles/uninstall.sh" --retired || failed+=("Removing AeroSpace's config")
    fi
    keys="$(keys_for kadomo-menu)"
    [[ -z "$keys" ]] || run_component "Kadomo Menu" step kadomo-menu --only "$keys"
    keys="$(keys_for dotfiles)"
    [[ -z "$keys" ]] || run_component "Configs" step dotfiles --only "$keys"
    keys="$(keys_for apps)"
    [[ -z "$keys" ]] || run_component "Apps: $(labels_for apps)" step apps --only "$keys"
    ! component_on moonlight-mouse || run_component "Moonlight Mouse Optimization" step moonlight-mouse
    ! component_on omniwm || run_component "OmniWM" step omniwm
    # After the configs and apps it wires.
    keys="$(keys_for kadomo-theme-manager)"
    [[ -z "$keys" ]] || run_component "Theme manager and themes" step kadomo-theme-manager --only "$keys"
    # Last: Starship takes its colors from the theme manager. Java asks for your
    # password, and a prompt setup of yours gets a question, so with a terminal
    # this runs in the open.
    keys="$(keys_for developer)"
    if [[ -n "$keys" ]]; then
        dev_args=(--only "$keys")
        if ((ASSUME_YES == 0)) && item_on developer java; then
            run_component "$(labels_for developer)" step_open developer "${dev_args[@]}"
        else
            run_component "$(labels_for developer)" step developer "${dev_args[@]}" --yes
        fi
    fi
}

finish() {
    local i
    printf '\n'
    if ((${#failed[@]})); then
        printf '  %s✗ %s of the steps failed:%s %s\n' "$RED" "${#failed[@]}" "$RESET" "$(IFS=';'; echo "${failed[*]}" | sed 's/;/; /g')"
        printf '  %sRun %s again to retry; what is done already is skipped.%s\n' "$DIM" "$KADOMO_INSTALL_CMD" "$RESET"
    else
        printf '  %s✓ Kadomo is set up%s\n' "$CYAN" "$RESET"
    fi
    if { item_on kadomo-menu app || item_on kadomo-menu start; } && [[ " ${failed[*]-} " != *" Kadomo Menu "* ]]; then
        printf '\n  %sLaunch%s    press ⌥Space (Option-Space) for Kadomo Menu\n' "$DIM" "$RESET"
    fi
    printf '  %sLog%s       %s\n' "$DIM" "$RESET" "$(short_path "$STEP_LOG")"
    printf '  %sRemove%s    %s\n' "$DIM" "$RESET" "$KADOMO_UNINSTALL_CMD"
    if ((${#todos[@]})); then
        printf '\n  %sStill needs you%s\n' "$BOLD" "$RESET"
        for ((i=0; i<${#todos[@]}; i++)); do
            wrap_text 74 "${todos[i]}" | sed "1s/^/  $((i+1)). /; 1!s/^/     /"
        done
    fi
    if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        printf '\n  %sAdd ~/.local/bin to PATH to run kadomo-menu and theme-set from a shell:%s\n' "$DIM" "$RESET"
        printf '      echo '\''export PATH="$HOME/.local/bin:$PATH"'\'' >> ~/.zshrc\n'
    fi
    printf '\n'
    ((${#failed[@]} == 0))
}

if ((ASSUME_YES)); then
    [[ -n "$ONLY_CATS" ]] || ONLY_CATS=core
    for key in ${ONLY_CATS//,/ }; do
        for ((c=0; c<${#CATS[@]}; c++)); do [[ "${CAT_KEYS[c]}" != "$key" ]] || set_category "$c" 1; done
    done
    printf '\n  %sInstalling Kadomo %s:%s %s\n\n' "$BOLD" "$KADOMO_VERSION" "$RESET" "${ONLY_CATS//,/, }"
else
    [[ -t 0 && -t 1 ]] || die "run this in a terminal, or pass --yes or --only."
    set_category 0 1
    while :; do
        main_menu || { clear_screen; printf '\n  Nothing changed.\n\n'; exit 0; }
        if (($(selected_count) == 0)); then continue; fi
        review && break
    done
    clear_screen; logo
    printf '  Setting up Kadomo...\n\n'
fi
(($(selected_count))) || { printf '\n  Nothing selected. Nothing changed.\n\n'; exit 0; }

STEP_LOG="$(mktemp "${TMPDIR:-/tmp}/kadomo-install.XXXXXX")"
trap stop_tail EXIT

# brew's PATH block in ~/.zprofile and the Starship block in .zshrc only take
# effect in a shell that starts after them. Sourcing them from here would not
# help: this script is a child process and cannot change the shell that
# started it. So, run from zsh in a terminal, it ends by handing the window to
# a new zsh that reads them, and nobody has to open a new window.
new_shell=0
parent_shell="$(ps -o comm= -p "$PPID" 2>/dev/null | tr -d ' ' || true)"
if [[ -t 0 && -t 1 && "${parent_shell##*/}" == *zsh ]] && zsh_bin="$(command -v zsh)" \
    && { component_on homebrew || item_on developer starship; }; then
    new_shell=1
    # Decided before anything installs, so the Homebrew step knows not to ask
    # you to open a new window: the new shell does that.
    export KADOMO_NEW_SHELL=1
fi
install_selected

status=0
finish || status=$?
if ((new_shell)); then
    printf '  %sStarting a new zsh in this window, so brew and the new prompt work right away.%s\n' "$DIM" "$RESET"
    printf '  %sWindows that were already open get them once you open a new one; exit here returns to the old shell.%s\n\n' "$DIM" "$RESET"
    trap - EXIT
    stop_tail
    exec "$zsh_bin" -l
fi
exit "$status"
