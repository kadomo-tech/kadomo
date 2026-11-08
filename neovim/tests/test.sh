#!/bin/bash
# Checks neovim/install.sh and uninstall.sh in a throwaway HOME, with a
# stand-in brew that "installs" into the test folder and a stand-in nvim that
# only logs how it was run. Nothing is installed on this Mac and no real
# Neovim config is read or changed.
#
# Usage: neovim/tests/test.sh
set -uo pipefail

NV="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$NV/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/kadomo-neovim-test.XXXXXX")"
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

# The stand-ins. Formulae put their command in $W/brewbin; the claude-code
# cask puts claude there too. FAIL_INSTALL=<name> makes that install fail.
setup_fakes() {
    W="$WORK/$1"
    rm -rf -- "$W"; mkdir -p "$W/brewbin" "$W/brew-state" "$W/home" "$W/bin"
    cat >"$W/brew" <<FAKE
#!/bin/bash
W='$W'
echo "brew \$*" >>"\$W/brew.log"
cmd="\$1" kind="\${2#--}" name="\$3"
case "\$name" in ripgrep) bin=rg ;; tree-sitter-cli) bin=tree-sitter ;; claude-code) bin=claude ;; *) bin="\$name" ;; esac
case "\$cmd" in
    list) [[ -e "\$W/brew-state/\$kind-\$name" ]] ;;
    install)
        [[ "\${FAIL_INSTALL:-}" != "\$name" ]] || { echo "curl: (6) Could not resolve host" >&2; exit 1; }
        touch "\$W/brew-state/\$kind-\$name"
        printf '#!/bin/bash\necho "%s 1.0"\n' "\$bin" >"\$W/brewbin/\$bin"; chmod +x "\$W/brewbin/\$bin" ;;
    uninstall) rm -f "\$W/brew-state/\$kind-\$name" "\$W/brewbin/\$bin" ;;
esac
FAKE
    printf '#!/bin/bash\necho "nvim $*" >>"%s/nvim.log"\n' "$W" >"$W/bin/nvim"
    printf '#!/bin/bash\necho v24.0.0\n' >"$W/bin/node"
    chmod +x "$W/brew" "$W/bin/nvim" "$W/bin/node"
    printf '#!/bin/bash\n[[ -n "${JDK:-}" ]] && echo /jdk\n' >"$W/java_home"; chmod +x "$W/java_home"
    export HOME="$W/home" KADOMO_STATE_DIR="$W/home/app-support" KADOMO_BREW="$W/brew"
    export KADOMO_EXTRA_PATH="$W/brewbin" KADOMO_JAVA_HOME="$W/java_home" KADOMO_APP_DIRS="$W/Apps"
    export PATH="$W/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    unset KADOMO_NVIM_CONFIG FAIL_INSTALL JDK
    CFG="$HOME/.config/nvim"
}
manifest() { cat "$KADOMO_STATE_DIR/neovim-installed.txt" 2>/dev/null; }
record_file() { printf '%s' "$KADOMO_STATE_DIR/neovim-installed.txt"; }

echo "The config's Lua parses"
if command -v texlua >/dev/null || command -v luac >/dev/null; then
    printf 'assert(loadfile(arg[1]))\n' >"$WORK/parse.lua"
    while IFS= read -r f; do
        if command -v luac >/dev/null; then check "${f#$NV/}" luac -p "$f"
        else check "${f#$NV/}" texlua "$WORK/parse.lua" "$f"; fi
    done < <(find "$NV/config" -name '*.lua' | sort)
else
    echo "  (no Lua here to check with; skipped)"
fi

echo "A first install, with no Neovim config yet"
setup_fakes fresh
"$NV/install.sh" --only ide >"$WORK/out" 2>&1; st=$?
check "exits 0" same "$st" 0
for f in init.lua lua/config/lazy.lua lua/plugins/kadomo-aws.lua; do
    check "  places $f" cmp -s "$NV/config/$f" "$CFG/$f"
done
# The formulae this machine lacks (on a Mac, all four; a test box may have ripgrep).
missing=0
for c in rg fd tree-sitter lazygit; do command -v "$c" >/dev/null || missing=$((missing+1)); done
check "  installs the missing formulae" bash -c "grep -c '^brew install' '$W/brew.log' | grep -qx $missing"
check "  records them" bash -c "grep -q '^formula|tree-sitter-cli$' '$(record_file)' && grep -q '^formula|lazygit$' '$(record_file)'"
check "  records the folders it made" has "$(record_file)" "dir|$CFG"
check "  downloads the plugins headless" has "$W/nvim.log" "--headless +Lazy! sync +qa"
check "  reminds about Java (no JDK)" has "$WORK/out" "Java 25"
check "  no AI file" [ ! -e "$CFG/kadomo-ai.lua" ]

echo "Running it again"
: >"$W/brew.log"
"$NV/install.sh" --only ide --no-sync >"$WORK/out" 2>&1
check "  leaves the files unchanged" has "$WORK/out" "init.lua (unchanged)"
check "  installs nothing" [ ! -s "$W/brew.log" ]
check "  --no-sync skips the download" bash -c "[ \$(grep -c headless '$W/nvim.log') -eq 1 ]"

echo "An edited Kadomo file"
echo "-- mine" >>"$CFG/lua/plugins/kadomo-aws.lua"
"$NV/install.sh" --only ide --no-sync >"$WORK/out" 2>&1
check "  is kept on reinstall" bash -c "ls '$CFG/lua/plugins/' | grep -q 'kadomo-aws.lua.bak.'"
check "  and replaced" cmp -s "$NV/config/lua/plugins/kadomo-aws.lua" "$CFG/lua/plugins/kadomo-aws.lua"

echo "Uninstalling"
"$NV/uninstall.sh" --dry-run >"$WORK/plan" 2>&1
check "  the dry run lists the files" has "$WORK/plan" "~/.config/nvim/init.lua"
check "  and changes nothing" [ -f "$CFG/init.lua" ]
echo '{}' >"$CFG/lazy-lock.json"
"$NV/uninstall.sh" >"$WORK/out" 2>&1; st=$?
check "exits 0" same "$st" 0
check "  removes the config" [ ! -e "$CFG/init.lua" ]
check "  removes lazy-lock.json" [ ! -e "$CFG/lazy-lock.json" ]
check "  keeps the edited copy" bash -c "ls '$CFG/lua/plugins/' | grep -q 'kadomo-aws.lua.bak.'"
check "  uninstalls them" bash -c "grep -c '^brew uninstall' '$W/brew.log' | grep -qx $missing"
check "  the record is gone" [ ! -e "$(record_file)" ]
"$NV/uninstall.sh" >"$WORK/out" 2>&1
check "  again: nothing to do" has "$WORK/out" "no neovim installed"

echo "Over a config of yours"
setup_fakes yours
mkdir -p "$CFG/lua/custom" "$CFG/plugin"
echo "-- my init" >"$CFG/init.lua"
echo "return {}" >"$CFG/lua/custom/thing.lua"
echo "-- my plugin" >"$CFG/plugin/mine.lua"
echo '{"x":1}' >"$CFG/lazy-lock.json"
"$NV/install.sh" --only ide --no-sync >"$WORK/out" 2>&1
check "  sets init.lua aside" bash -c "grep -qx -- '-- my init' '$CFG'/init.lua.bak.*"
check "  sets lua/ aside" bash -c "[ -f \"\$(ls -d '$CFG'/lua.bak.* | head -1)/custom/thing.lua\" ]"
check "  sets lazy-lock.json aside" bash -c "ls '$CFG' | grep -q '^lazy-lock.json.bak.'"
check "  leaves plugin/ where it is" [ -f "$CFG/plugin/mine.lua" ]
check "  Kadomo's init.lua is in place" cmp -s "$NV/config/init.lua" "$CFG/init.lua"
echo "return {}" >"$CFG/lua/plugins/extra.lua"
echo '{"y":2}' >"$CFG/lazy-lock.json"
"$NV/uninstall.sh" >"$WORK/out" 2>&1
check "  uninstall puts init.lua back" bash -c "grep -qx -- '-- my init' '$CFG/init.lua'"
check "  and lua/" [ -f "$CFG/lua/custom/thing.lua" ]
check "  and lazy-lock.json" bash -c "grep -q '\"x\"' '$CFG/lazy-lock.json'"
check "  keeps what you added to Kadomo's" bash -c "[ -f \"\$(ls -d '$CFG'/lua.bak.* | head -1)/plugins/extra.lua\" ]"
check "  plugin/ untouched" [ -f "$CFG/plugin/mine.lua" ]
check "  no backups left of yours" bash -c "! ls '$CFG' | grep -q '^init.lua.bak\\|^lazy-lock.json.bak'"

echo "A config folder that is a link"
setup_fakes linked
mkdir -p "$W/dotfiles/nvim" "$HOME/.config"
ln -s "$W/dotfiles/nvim" "$CFG"
"$NV/install.sh" --only ide --no-sync >"$WORK/out" 2>&1; st=$?
check "  fails" same "$st" 1
check "  puts nothing there" [ -z "$(ls -A "$W/dotfiles/nvim")" ]
check "  says why" has "$WORK/out" "is a link"

echo "The AI tools"
setup_fakes ai
"$NV/install.sh" --only ide --no-sync >/dev/null 2>&1
"$NV/install.sh" --only copilot,claude >"$WORK/out" 2>&1; st=$?
check "exits 0" same "$st" 0
check "  writes the AI file" has "$CFG/kadomo-ai.lua" "return { copilot = true, claude_code = true }"
check "  installs Claude Code" has "$W/brew.log" "install --cask claude-code"
check "  says how to sign in to Copilot" has "$WORK/out" ":Copilot auth"
check "  and to Claude Code" has "$WORK/out" "run claude in a terminal"
"$NV/install.sh" --only claude >"$WORK/out" 2>&1
check "  again: already on" has "$WORK/out" "Claude Code in Neovim (already on)"
check "  no second sign-in reminder" lacks "$WORK/out" "run claude in a terminal"
"$NV/uninstall.sh" >"$WORK/out" 2>&1
check "  uninstall removes the AI file" [ ! -e "$CFG/kadomo-ai.lua" ]
check "  and Claude Code" has "$W/brew.log" "uninstall --cask claude-code"
check "  and the config folder it made" [ ! -e "$CFG" ]

echo "A Claude Code you installed yourself"
setup_fakes ownclaude
mkdir -p "$HOME/.local/bin"; printf '#!/bin/bash\n' >"$HOME/.local/bin/claude"; chmod +x "$HOME/.local/bin/claude"
"$NV/install.sh" --only claude >"$WORK/out" 2>&1
check "  is used as it is" has "$WORK/out" "Claude Code (already installed"
check "  not installed again" lacks "$W/brew.log" "claude-code"
check "  AI tools without the IDE: a reminder" has "$WORK/out" "Neovim IDE"
"$NV/uninstall.sh" >/dev/null 2>&1
check "  stays after uninstall" [ -x "$HOME/.local/bin/claude" ]

echo "A failed download"
setup_fakes offline
export FAIL_INSTALL=fd
"$NV/install.sh" --only ide --no-sync >"$WORK/out" 2>&1; st=$?
check "  exits 1" same "$st" 1
check "  fd not recorded" lacks "$(record_file)" "formula|fd"
unset FAIL_INSTALL
"$NV/install.sh" --only ide --no-sync >"$WORK/out" 2>&1; st=$?
check "  a retry finishes it" bash -c "[ $st -eq 0 ] && grep -q '^formula|fd$' '$(record_file)'"

echo "The top-level installer and uninstaller"
check "  Developer row for the IDE" grep -q 'Developer|neovim|ide|' "$REPO/install.sh"
check "  AI rows" bash -c "grep -q 'AI|neovim|copilot|' '$REPO/install.sh' && grep -q 'AI|neovim|claude|' '$REPO/install.sh'"
check "  --only knows ai" grep -q 'CAT_KEYS=(core developer ai gaming other)' "$REPO/install.sh"
check "  uninstall lists it" grep -q 'COMPONENTS=(.*neovim' "$REPO/uninstall.sh"

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
((FAIL == 0))
