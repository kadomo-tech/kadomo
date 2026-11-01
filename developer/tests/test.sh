#!/bin/bash
# Checks developer/install.sh and uninstall.sh in a throwaway HOME, with a
# stand-in brew that "installs" into the test folder. Nothing is installed on
# this Mac and no real shell config is read or changed.
#
# Usage: developer/tests/test.sh
set -uo pipefail

DEV="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$DEV/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/kadomo-dev-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
PASS=0
FAIL=0

check() {
    local what="$1"; shift
    if "$@"; then PASS=$((PASS + 1)); printf '  ✓ %s\n' "$what"
    else FAIL=$((FAIL + 1)); printf '  ✗ %s\n' "$what"; fi
}
has() { grep -qF -- "$2" "$1" 2>/dev/null; }
lacks() { ! grep -qF -- "$2" "$1" 2>/dev/null; }
same() { [[ "$1" == "$2" ]] || { printf '      got "%s", wanted "%s"\n' "$1" "$2"; return 1; }; }

# The stand-in brew. Formulae land in $W/brewbin, the JDK is a marker the
# stand-in java_home looks for, Rancher Desktop and VS Code app bundles in $W/Apps.
# FAIL_INSTALL=<name> makes that install fail (as when offline).
setup_fakes() {
    W="$WORK/$1"
    rm -rf -- "$W"; mkdir -p "$W/brewbin" "$W/Apps" "$W/brew-state" "$W/home"
    cat >"$W/brew" <<EOF
#!/bin/bash
W='$W'
echo "brew \$*" >>"\$W/brew.log"
cmd="\$1" kind="\${2#--}" name="\$3"
case "\$cmd" in
    list) [[ -e "\$W/brew-state/\$kind-\$name" ]] ;;
    install)
        [[ "\${FAIL_INSTALL:-}" != "\$name" ]] || { echo "curl: (6) Could not resolve host" >&2; exit 1; }
        touch "\$W/brew-state/\$kind-\$name"
        case "\$name" in
            node) printf '#!/bin/bash\necho v26.13.0\n' >"\$W/brewbin/node"; chmod +x "\$W/brewbin/node" ;;
            starship) cp "$WORK/starship-stub" "\$W/brewbin/starship" ;;
            temurin@25) mkdir -p "\$W/jdk/bin"; printf '#!/bin/bash\necho "openjdk version \\"25.0.5\\"" >&2\n' >"\$W/jdk/bin/java"; chmod +x "\$W/jdk/bin/java" ;;
            rancher) mkdir -p "\$W/Apps/Rancher Desktop.app/Contents"
                     printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict><key>CFBundleShortVersionString</key><string>1.24.0</string></dict></plist>\n' >"\$W/Apps/Rancher Desktop.app/Contents/Info.plist" ;;
            visual-studio-code) mkdir -p "\$W/Apps/Visual Studio Code.app/Contents/Resources/app/bin"
                     printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict><key>CFBundleShortVersionString</key><string>1.106.0</string></dict></plist>\n' >"\$W/Apps/Visual Studio Code.app/Contents/Info.plist"
                     printf '#!/bin/bash\necho "code \$*" >>"%s/code.log"\n' "\$W" >"\$W/Apps/Visual Studio Code.app/Contents/Resources/app/bin/code"
                     chmod +x "\$W/Apps/Visual Studio Code.app/Contents/Resources/app/bin/code" ;;
        esac ;;
    uninstall)
        rm -f "\$W/brew-state/\$kind-\$name"
        case "\$name" in
            node|starship) rm -f "\$W/brewbin/\$name" ;;
            temurin@25) rm -rf "\$W/jdk" ;;
            rancher) rm -rf "\$W/Apps/Rancher Desktop.app" ;;
            visual-studio-code) rm -rf "\$W/Apps/Visual Studio Code.app" ;;
        esac ;;
esac
EOF
    printf '#!/bin/bash\n[[ -d "%s/jdk" ]] && echo "%s/jdk"\n' "$W" "$W" >"$W/java_home"
    chmod +x "$W/brew" "$W/java_home"
    export HOME="$W/home" KADOMO_STATE_DIR="$W/home/app-support" KADOMO_BREW="$W/brew"
    export KADOMO_EXTRA_PATH="$W/brewbin" KADOMO_JAVA_HOME="$W/java_home" KADOMO_APP_DIRS="$W/Apps"
    export KADOMO_STARSHIP_SEARCH="$W/brewbin/starship" KADOMO_THEME_APPS="" KADOMO_FONT_DIRS=""
    export KADOMO_VSCODE_CLI="$W/Apps/Visual Studio Code.app/Contents/Resources/app/bin/code"
    export PATH="$W/brewbin:/usr/bin:/bin:/usr/sbin:/sbin"
    unset ZDOTDIR FAIL_INSTALL
}
cat >"$WORK/starship-stub" <<'EOF'
#!/bin/bash
case "$1" in --version) echo "starship 1.27.0" ;; init) echo "prompt_starship_precmd() { :; }; PROMPT='STAR> '" ;; prompt) echo "> " ;; esac
EOF
chmod +x "$WORK/starship-stub"
manifest() { cat "$KADOMO_STATE_DIR/developer-installed.txt" 2>/dev/null; }
theme_manager() { "$REPO/kadomo-theme-manager/install.sh" --only themes >/dev/null 2>&1; }

echo "Without Homebrew"
setup_fakes nobrew
export KADOMO_BREW=""
"$DEV/install.sh" --yes >"$WORK/out" 2>&1; st=$?
check "exits 1" same "$st" 1
check "  says Homebrew is needed, and is not installed for you" has "$WORK/out" "Kadomo does not install it for you"
check "  offers Starship's own installer" has "$WORK/out" "--starship-script"
check "  records nothing" same "$(manifest)" ""
"$DEV/install.sh" --dry-run --starship-script --only starship >"$WORK/out" 2>&1
check "--starship-script: the official installer, into ~/.local/bin" has "$WORK/out" "https://starship.rs/install.sh"

echo "A dry run changes nothing"
setup_fakes dry
"$DEV/install.sh" --dry-run >"$WORK/out" 2>&1
check "shows each brew install" bash -c "grep -q 'brew install --formula node' '$WORK/out' && grep -q 'install --cask temurin@25' '$WORK/out' && grep -q 'install --cask rancher' '$WORK/out' && grep -q 'install --cask visual-studio-code' '$WORK/out' && grep -q 'install --formula starship' '$WORK/out'"
check "  and turning on VS Code's colors" has "$WORK/out" "theme-vscode enable"
check "  runs none" lacks "$W/brew.log" "install"
check "  records nothing" same "$(manifest)" ""

echo "Install everything"
setup_fakes all
theme_manager
printf 'export E=5\n' >"$HOME/.zshrc"
"$DEV/install.sh" --yes >"$WORK/out" 2>&1; st=$?
check "exits 0" same "$st" 0
check "  Node.js, with its version" has "$WORK/out" "✓  Node.js v26.13.0"
check "  Java 25" has "$WORK/out" 'openjdk version 25.0.5'
check "  Rancher Desktop 1.24.0" has "$WORK/out" "✓  Rancher Desktop 1.24.0"
check "  VS Code 1.106.0" has "$WORK/out" "✓  Visual Studio Code 1.106.0"
check "  in the theme's colors" same "$(osascript -l JavaScript "$REPO/kadomo-theme-manager/lib/vscode.js" get "$HOME/Library/Application Support/Code/User/settings.json" 2>/dev/null)" Kadomo
check "  the Kadomo theme extension in place" [ -f "$HOME/.vscode/extensions/kadomo.kadomo-theme/package.json" ]
check "  and it follows each theme" bash -c "grep '^apps' '$HOME/.config/kadomo/theme.conf' | grep -qw vscode"
check "  and what to do in it" has "$WORK/out" "Open Rancher Desktop once"
check "  Starship, on for zsh" has "$HOME/.zshrc" ">>> kadomo starship"
check "  all recorded" same "$(manifest | LC_ALL=C sort | paste -sd' ' -)" "cask|rancher cask|temurin@25 cask|visual-studio-code enabled|starship enabled|vscode formula|node formula|starship"
"$DEV/install.sh" --yes >"$WORK/out" 2>&1
check "again: all already installed" same "$(grep -c 'already installed' "$WORK/out")" 5
check "  no second block" same "$(grep -c '>>> kadomo starship' "$HOME/.zshrc")" 1
check "  no double records" same "$(manifest | wc -l | tr -d ' ')" 7
"$DEV/uninstall.sh" --dry-run >"$WORK/out" 2>&1
check "uninstall --dry-run lists it all" bash -c "grep -q 'Starship for zsh' '$WORK/out' && grep -q 'theme-vscode disable' '$WORK/out' && grep -q 'uninstall --cask rancher' '$WORK/out' && grep -q 'uninstall --cask visual-studio-code' '$WORK/out'"
check "  and changes nothing" same "$(manifest | wc -l | tr -d ' ')" 7
"$DEV/uninstall.sh" >"$WORK/out" 2>&1; st=$?
check "uninstall exits 0" same "$st" 0
check "  .zshrc as before" same "$(cat "$HOME/.zshrc")" "export E=5"
check "  every tool gone" same "$(ls "$W/brew-state" | wc -l | tr -d ' ')" 0
check "  VS Code's Kadomo theme gone with it" [ ! -e "$HOME/.vscode" -a ! -e "$HOME/Library/Application Support/Code" ]
check "  and VS Code no longer follows the theme" bash -c "! grep '^apps' '$HOME/.config/kadomo/theme.conf' | grep -qw vscode"
check "  the record gone" [ ! -e "$KADOMO_STATE_DIR/developer-installed.txt" ]
"$DEV/uninstall.sh" >"$WORK/out" 2>&1
check "  again: nothing to do" has "$WORK/out" "no developer installed"

echo "Tools already on the Mac are used and never removed"
setup_fakes existing
theme_manager
printf '#!/bin/bash\necho v24.1.0\n' >"$W/brewbin/node"
cp "$WORK/starship-stub" "$W/brewbin/starship"
chmod +x "$W/brewbin/node"
"$DEV/install.sh" --yes --only node,starship >"$WORK/out" 2>&1
check "node and starship: already installed" bash -c "grep -q 'Node.js (already installed: v24.1.0)' '$WORK/out' && grep -q 'Starship (already installed' '$WORK/out'"
check "  brew not asked to install" lacks "$W/brew.log" "install"
check "  only the prompt recorded" same "$(manifest)" "enabled|starship"
"$DEV/uninstall.sh" >/dev/null 2>&1
check "  uninstall turns the prompt off" lacks "$HOME/.zshrc" "kadomo starship"
check "  and leaves both tools" bash -c "[ -x '$W/brewbin/node' ] && [ -x '$W/brewbin/starship' ]"

echo "A failed download"
setup_fakes offline
FAIL_INSTALL=node "$DEV/install.sh" --yes --only node,java >"$WORK/out" 2>&1; st=$?
check "exits 1, says so" bash -c "[ $st -eq 1 ] && grep -q 'run this again to retry' '$WORK/out'"
check "  the rest still installs" has "$WORK/out" "✓  Java 25"
check "  node not recorded" same "$(manifest)" "cask|temurin@25"
"$DEV/install.sh" --yes --only node,java >/dev/null 2>&1; st=$?
check "  a retry finishes it" bash -c "[ $st -eq 0 ] && [ \"\$(cat '$KADOMO_STATE_DIR/developer-installed.txt' | wc -l | tr -d ' ')\" = 2 ]"

echo "Your own prompt setup is left alone with --yes"
setup_fakes prompt
theme_manager
printf 'eval "$(starship init zsh)"\n' >"$HOME/.zshrc"
"$DEV/install.sh" --yes --only starship >"$WORK/out" 2>&1; st=$?
check "exits 0, with the way to switch" bash -c "[ $st -eq 0 ] && grep -q 'theme-starship enable --use-kadomo' '$WORK/out'"
check "  .zshrc untouched" same "$(cat "$HOME/.zshrc")" 'eval "$(starship init zsh)"'
check "  not recorded as on" lacks "$KADOMO_STATE_DIR/developer-installed.txt" "enabled|starship"
"$DEV/install.sh" --yes --use-kadomo-prompt --only starship >/dev/null 2>&1
check "--use-kadomo-prompt turns it on" has "$HOME/.zshrc" ">>> kadomo starship"

echo "Starship without the theme manager"
setup_fakes notheme
"$DEV/install.sh" --yes --only starship >"$WORK/out" 2>&1; st=$?
check "installs Starship, says what is missing" bash -c "[ $st -eq 0 ] && grep -q 'Install the theme manager' '$WORK/out'"
check "  .zshrc not made" [ ! -e "$HOME/.zshrc" ]

echo "VS Code already on the Mac"
setup_fakes vscode-existing
theme_manager
"$W/brew" install --cask visual-studio-code >/dev/null
rm -f "$W/brew-state/cask-visual-studio-code" "$W/brew.log"
"$DEV/install.sh" --yes --only vscode >"$WORK/out" 2>&1; st=$?
check "is used as it is, in the theme's colors" bash -c "[ $st -eq 0 ] && grep -q 'Visual Studio Code (already installed: 1.106.0)' '$WORK/out' && [ -d '$HOME/.vscode/extensions/kadomo.kadomo-theme' ]"
check "  only its colors recorded" same "$(manifest)" "enabled|vscode"
"$DEV/uninstall.sh" >/dev/null 2>&1
check "  uninstall takes the colors out and leaves VS Code" bash -c "[ ! -e '$HOME/.vscode' ] && [ -d '$W/Apps/Visual Studio Code.app' ] && ! grep -qs uninstall '$W/brew.log'"

echo "VS Code without the theme manager"
setup_fakes vscode-notheme
"$DEV/install.sh" --yes --only vscode >"$WORK/out" 2>&1; st=$?
check "installs VS Code, says what is missing" bash -c "[ $st -eq 0 ] && grep -q 'Install the theme manager' '$WORK/out'"
check "  only VS Code recorded" same "$(manifest)" "cask|visual-studio-code"

echo "Docker Desktop next to Rancher Desktop"
setup_fakes docker
mkdir -p "$W/Apps/Docker.app"
"$DEV/install.sh" --yes --only rancher >"$WORK/out" 2>&1
check "the note about both" has "$WORK/out" "Docker Desktop is installed too"

echo "The top-level installer lists the developer tools"
check "install.sh has the five rows, off by default" bash -c "grep -q 'developer|node|Node.js' '$REPO/install.sh' && grep -q 'developer|vscode|Visual Studio Code' '$REPO/install.sh' && grep -q 'labels_for developer' '$REPO/install.sh' && grep -q 'developer' '$REPO/uninstall.sh'"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
((FAIL == 0))
