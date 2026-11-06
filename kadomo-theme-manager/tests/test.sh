#!/bin/bash
# Checks the theme manager against its spec, in a throwaway HOME: the eight
# acceptance tests, tmac2k against the files the dotfiles used to ship, the
# rules for themes from git, and an install/uninstall round trip.
# No app is signalled and the desktop is left alone (KADOMO_THEME_APPS is
# empty), so it is safe to run on your own Mac.
#
# Usage: tests/test.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$ROOT/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/kadomo-theme-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
export HOME="$WORK/home" KADOMO_THEME_APPS="" KADOMO_STATE_DIR="$WORK/app-support" NVIM_LOG_FILE="$WORK/nvim.log"
# No VS Code, unless a test brings its stand-in: yours is never reached.
export KADOMO_VSCODE_CLI=""
mkdir -p "$HOME"
BIN="$ROOT/bin"
CUR="$HOME/.config/kadomo/current"
THEME="$CUR/theme"
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
bg() { basename "$(readlink "$CUR/background")"; }
key() { awk -F'\t' -v k="$2" '$1 == k { print $2 }' "$1/palette.tsv"; }
# Lines that set something: no comments, no blank lines.
settings() { grep -v '^#' "$1" | grep -v '^$'; }

echo "tmac2k matches the theme the dotfiles carried"
"$BIN/theme-set" tmac2k >/dev/null 2>"$WORK/err"
check "applies without warnings" [ ! -s "$WORK/err" ]
for pair in "ghostty.conf:dotfiles/ghostty/themes/tmac2k" "btop.theme:dotfiles/btop/themes/tmac2k.theme" "kitty.conf:dotfiles/kitty/themes/tmac2k.conf"; do
    git -C "$REPO" show "main:${pair#*:}" >"$WORK/original" 2>/dev/null || continue
    settings "$THEME/${pair%%:*}" | grep -v '_border_color ' >"$WORK/now"
    settings "$WORK/original" >"$WORK/was"
    check "${pair%%:*} has the same colors" cmp -s "$WORK/now" "$WORK/was"
done
check "sketchybar: the bar is the background, see-through" has "$THEME/sketchybar-colors.sh" 'export BG_TRANS="0xc0000000"'
check "sketchybar: colors are 0xAARRGGBB" has "$THEME/sketchybar-colors.sh" 'export ACCENT="0xffba5aff"'
check "omniwm: the border runs violet to cyan" has "$THEME/omniwm.toml" 'direction = "topLeftToBottomRight"'
check "omniwm: violet first" bash -c "grep -A4 '^\[borders.gradient.start\]' '$THEME/omniwm.toml' | grep -qx 'red = 0.7294'"
check "omniwm: the solid color is the first stop" bash -c "grep -A4 '^\[borders.color\]' '$THEME/omniwm.toml' | grep -qx 'green = 0.3529'"
check "the launcher gets tmac2k too" has "$THEME/kadomo-menu.toml" 'border = ["#ba5aff", "#5ac8ff"]'

echo "1. theme-set catppuccin"
start=$(date +%s)
"$BIN/theme-set" catppuccin >"$WORK/out"
elapsed=$(($(date +%s) - start))
check "prints the display name" has "$WORK/out" "Theme: Catppuccin"
check "current/theme.name" same "$(cat "$CUR/theme.name")" catppuccin
check "Ghostty colors" has "$THEME/ghostty.conf" "background = #1e1e2e"
check "dark mode" same "$(key "$THEME" mode)" dark
check "wallpaper is the theme's first" same "$(bg)" 0-glow.png
check "takes about a second at most ($elapsed s)" [ "$elapsed" -le 1 ]

echo "2. theme-set catppuccin-latte flips to light"
"$BIN/theme-set" "Catppuccin Latte" >/dev/null
check "light mode" same "$(key "$THEME" mode)" light
check "Ghostty colors" has "$THEME/ghostty.conf" "background = #eff1f5"
check "the launcher goes light" has "$THEME/kadomo-menu.toml" 'appearance = "light"'
check "wallpaper" same "$(readlink "$CUR/background")" "$ROOT/themes/catppuccin-latte/backgrounds/0-glow.png"

echo "3. theme-bg-next cycles and wraps"
"$BIN/theme-bg-next" >/dev/null; check "second" same "$(bg)" 1-horizon.png
"$BIN/theme-bg-next" >/dev/null; check "third" same "$(bg)" 2-drift.png
"$BIN/theme-bg-next" >/dev/null; check "back to the first" same "$(bg)" 0-glow.png
check "theme-bg-set takes any image" "$BIN/theme-bg-set" "$ROOT/themes/gruvbox/backgrounds/1-horizon.png"
check "  and points current/background at it" same "$(readlink "$CUR/background")" "$ROOT/themes/gruvbox/backgrounds/1-horizon.png"

echo "4. your ghostty.conf in a theme wins, and theme-refresh keeps the wallpaper"
"$BIN/theme-set" catppuccin >/dev/null
"$BIN/theme-bg-next" >/dev/null
mkdir -p "$HOME/.config/kadomo/themes/catppuccin"
printf 'background = #123456\n' >"$HOME/.config/kadomo/themes/catppuccin/ghostty.conf"
"$BIN/theme-refresh" >/dev/null
check "Ghostty uses it" same "$(cat "$THEME/ghostty.conf")" "background = #123456"
check "wallpaper unchanged" same "$(bg)" 1-horizon.png
check "the other files are still the built-in theme's" has "$THEME/kitty.conf" "background #1e1e2e"

echo "5. your template overrides the built-in one for every theme"
mkdir -p "$HOME/.config/kadomo/themed"
printf '# mine\nbackground = {{ accent }}\nmixed = {{ mix background foreground 50%% }}\n' >"$HOME/.config/kadomo/themed/ghostty.conf.tpl"
"$BIN/theme-set" gruvbox >/dev/null
check "gruvbox's ghostty.conf comes from it" has "$THEME/ghostty.conf" "background = #d79921"
check "mix fills in" has "$THEME/ghostty.conf" "mixed = #8a826d"
"$BIN/theme-set" catppuccin >/dev/null
check "a theme's own ghostty.conf still wins over it" same "$(cat "$THEME/ghostty.conf")" "background = #123456"
rm "$HOME/.config/kadomo/themes/catppuccin/ghostty.conf"

echo "6. a theme cloned from git gives only colors and images"
repo="$WORK/omarchy-evil-theme"
mkdir -p "$repo/backgrounds" "$HOME/.ssh"
printf 'secret\n' >"$HOME/.ssh/id_ed25519"
cat >"$repo/colors.toml" <<'EOF'
background = "#101010"
foreground = "#e0e0e0"
accent = "#ff00aa"
red = "$(touch /tmp/kadomo-pwned)"
blue = "#fff\"; rm -rf ~; echo \""
EOF
printf 'vim.cmd("!touch /tmp/kadomo-pwned")\n' >"$repo/neovim.lua"
printf 'command = /bin/sh -c "touch /tmp/kadomo-pwned"\n' >"$repo/ghostty.conf"
printf '{"name": "Evil", "extension": "evil.extension"}\n' >"$repo/vscode.json"
printf 'options=(active_color=0xff000000)\n' >"$repo/borders.conf"
ln -s "$HOME/.ssh/id_ed25519" "$repo/unlock.png"
ln -s "$HOME/.ssh/id_ed25519" "$repo/backgrounds/0-key.png"
cp "$ROOT/themes/gruvbox/backgrounds/0-glow.png" "$repo/backgrounds/1-real.png"
(cd "$repo" && git init -q && git add -A && git -c user.name=t -c user.email=t@t commit -qm theme)
git clone -q "$repo" "$HOME/.config/kadomo/themes/evil"
"$BIN/theme-set" evil >"$WORK/out" 2>"$WORK/err"
check "applied as evil" same "$(cat "$CUR/theme.name")" evil
for name in neovim.lua ghostty.conf vscode.json borders.conf unlock.png backgrounds/0-key.png; do
    check "  reports $name as ignored" has "$WORK/err" "$name"
done
check "  no symlink in the current theme" [ -z "$(find "$THEME" -type l)" ]
check "  its vscode.json is not kept" [ ! -e "$THEME/vscode.json" ]
check "  its ghostty.conf is not used" lacks "$THEME/ghostty.conf" "command"
check "  its neovim.lua is not used" lacks "$THEME/neovim.lua" "kadomo-pwned"
check "  its colors are" has "$THEME/kitty.conf" "background #101010"
check "  values that are not colors are dropped" has "$WORK/err" "ignored red"
check "  the real wallpaper is used" same "$(bg)" 1-real.png
check "  nothing ran" [ ! -e /tmp/kadomo-pwned ]
check "there is no theme-install command (Kadomo Menu installs from git)" [ ! -e "$BIN/theme-install" ]

echo "7. five quick theme-sets: the last wins and nothing is half-applied"
for round in 1 2 3 4 5; do
    for name in gruvbox rose-pine sora tmac2k catppuccin catppuccin-latte; do
        "$BIN/theme-set" "$name" >/dev/null 2>&1 &
        sleep 0.05
    done
    wait
    [[ "$(cat "$CUR/theme.name")" == catppuccin-latte ]] || break
done
check "catppuccin-latte is current, five rounds running" same "$(cat "$CUR/theme.name")" catppuccin-latte
check "its files are in place" has "$THEME/kitty.conf" "background #eff1f5"
check "every generated file is there" bash -c "cd '$THEME' && ls btop.theme ghostty.conf kadomo-menu.toml kitty.conf omniwm.toml palette.tsv sketchybar-colors.sh >/dev/null"
check "no staging folder left" [ ! -e "$CUR/next-theme" -a ! -e "$CUR/old-theme" ]
check "the lock is released" [ ! -e "$HOME/.local/state/kadomo/theme.lock" ]

echo "8. hooks run with the theme name"
hooks="$HOME/.config/kadomo/hooks/theme-set.d"
mkdir -p "$hooks"
printf '#!/bin/bash\necho "$1" >"%s"\n' "$WORK/hook-ran" >"$hooks/record"
printf '#!/bin/bash\ntouch "%s"\n' "$WORK/sample-ran" >"$hooks/record.sample"
chmod +x "$hooks/record" "$hooks/record.sample"
"$BIN/theme-set" rose-pine >/dev/null
check "the hook got rose-pine" same "$(cat "$WORK/hook-ran" 2>/dev/null)" rose-pine
check ".sample files are skipped" [ ! -e "$WORK/sample-ran" ]

echo "Colors, names, and the other commands"
"$BIN/theme-list" >"$WORK/list"
check "theme-list shows display names" has "$WORK/list" "Catppuccin Latte"
check "  and your themes" has "$WORK/list" "Evil"
check "  once each" same "$(sort "$WORK/list" | uniq -d)" ""
check "theme-current" same "$("$BIN/theme-current")" "Rose Pine"
check "theme-color" same "$("$BIN/theme-color" accent)" "#d7827e"
check "theme-color aliases" same "$("$BIN/theme-color" purple)" "#907aa9"
check "theme-color --all has color15" bash -c "'$BIN/theme-color' --all | grep -q '^color15'"
check "names are normalized" "$BIN/theme-set" "<b>Catppuccin</b>" >/dev/null
check "a name with a slash is refused" bash -c "! '$BIN/theme-set' ../catppuccin 2>/dev/null"
check "a name starting with a dot is refused" bash -c "! '$BIN/theme-set' .hidden 2>/dev/null"
check "theme-osc writes 16 colors" same "$("$BIN/theme-osc" | tr '\a' '\n' | grep -c ']4;')" 16

echo "Legacy themes and section overrides"
mkdir -p "$HOME/.config/kadomo/themes/old-school"
cat >"$HOME/.config/kadomo/themes/old-school/alacritty.toml" <<'EOF'
[colors.primary]
background = "0x1c1c1c"
foreground = "0xc0c0c0"
[colors.normal]
black = "0x303030"
red = "0xcc4444"
[colors.bright]
red = "0xff6666"
EOF
"$BIN/theme-set" old-school >/dev/null 2>&1
check "alacritty.toml becomes colors.toml" has "$THEME/kitty.conf" "background #1c1c1c"
check "  with its ANSI colors" has "$THEME/kitty.conf" "color1 #cc4444"
check "  and color0 kept" has "$THEME/kitty.conf" "color0 #303030"
printf '[colors]\naccent = "#abcdef"\n' >"$HOME/.config/kadomo/themes/catppuccin/kadomo-menu.colors.toml"
"$BIN/theme-set" catppuccin >/dev/null
check "kadomo-menu.colors.toml replaces [colors]" has "$THEME/kadomo-menu.toml" 'accent = "#abcdef"'
check "  and only that section" same "$(grep -c '^\[colors\]' "$THEME/kadomo-menu.toml")" 1
check "  the rest stays" has "$THEME/kadomo-menu.toml" 'appearance = "dark"'

echo "Neovim and Vim"
nvim_run() { XDG_STATE_HOME="$WORK/nvim-state" XDG_DATA_HOME="$WORK/nvim-data" nvim "$@" 2>&1 | grep -v 'nice(5)'; }
for name in $("$BIN/theme-list" --names); do
    [[ "$name" == evil || "$name" == old-school ]] && continue
    "$BIN/theme-set" "$name" >/dev/null 2>"$WORK/err"
    check "$name: Neovim and Vim colors render cleanly" [ ! -s "$WORK/err" ]
    check "  Neovim loads them" same "$(nvim_run --clean --headless -c 'set termguicolors' -c "luafile $THEME/neovim-colors.lua" -c 'lua io.stdout:write(vim.g.colors_name .. " " .. vim.o.background)' -c q)" "kadomo $(key "$THEME" mode)"
    check "  Vim loads them" same "$(/usr/bin/vim -Nu NONE -i NONE -es -c 'set termguicolors' -c "source $THEME/vim-colors.vim" -c 'put =g:colors_name .. \" \" .. &background' -c '%p' -c 'q!' 2>&1 | tail -1)" "kadomo $(key "$THEME" mode)"
    check "  Neovim leaves the background to the terminal" same "$(nvim_run --clean --headless -c 'set termguicolors' -c "luafile $THEME/neovim-colors.lua" -c 'lua io.stdout:write(tostring(vim.api.nvim_get_hl(0, { name = "Normal" }).bg))' -c q)" "nil"
    check "  Neovim's solid background is one setting away" same "$(nvim_run --clean --headless -c 'set termguicolors' -c 'let g:kadomo_transparent = v:false' -c "luafile $THEME/neovim-colors.lua" -c 'lua io.stdout:write(tostring(vim.api.nvim_get_hl(0, { name = "Normal" }).bg ~= nil))' -c q)" "true"
    check "  Vim leaves the background to the terminal" same "$(/usr/bin/vim -Nu NONE -i NONE -es -c 'set termguicolors' -c "source $THEME/vim-colors.vim" -c 'put =\"bg=\" .. synIDattr(hlID(\"Normal\"), \"bg#\")' -c '%p' -c 'q!' 2>&1 | tail -1)" "bg="
    check "  Vim's solid background is one setting away" same "$(/usr/bin/vim -Nu NONE -i NONE -es -c 'set termguicolors' -c 'let g:kadomo_transparent = 0' -c "source $THEME/vim-colors.vim" -c 'put =\"bg=\" .. synIDattr(hlID(\"Normal\"), \"bg#\")' -c '%p' -c 'q!' 2>&1 | tail -1)" "bg=$(key "$THEME" background)"
done
original="$REPO/../macos-dev-setup/config"
if [[ -d "$original" ]]; then
    "$BIN/theme-set" tmac2k >/dev/null
    cat >"$WORK/dump.lua" <<'LUA'
local out = {}
for name, spec in pairs(vim.api.nvim_get_hl(0, {})) do
  local keys = {}
  for k, v in pairs(spec) do if k ~= "cterm" then keys[#keys + 1] = k .. "=" .. tostring(v) end end
  table.sort(keys)
  out[#out + 1] = name .. " " .. table.concat(keys, ",")
end
for i = 0, 15 do out[#out + 1] = "term" .. i .. " " .. tostring(vim.g["terminal_color_" .. i]) end
table.sort(out)
vim.fn.writefile(out, vim.env.DUMP)
LUA
    for file in "$original/nvim/colors/tmac2k.lua:was" "$THEME/neovim-colors.lua:now"; do
        # Line numbers are brighter than the original's on purpose (muted, not selection).
        DUMP="$WORK/${file##*:}" nvim_run --clean --headless -c 'set termguicolors' -c 'let g:tmac2k_transparent = v:false' -c "luafile ${file%:*}" -c "luafile $WORK/dump.lua" -c q
    done
    check "tmac2k in Neovim matches your original colorscheme" cmp -s <(grep -v '^LineNr ' "$WORK/was") <(grep -v '^LineNr ' "$WORK/now")
    check "  except for brighter line numbers" has "$WORK/now" "LineNr fg=$((16#$(key "$THEME" muted | tr -d '#')))"
    grep '^hi ' "$original/vim/colors/tmac2k.vim" | grep -v '^hi LineNr ' >"$WORK/was"; grep '^hi ' "$THEME/vim-colors.vim" | grep -v '^hi LineNr ' >"$WORK/now"
    check "tmac2k in Vim matches your original colorscheme" cmp -s "$WORK/was" "$WORK/now"
    check "  except for brighter line numbers" has "$THEME/vim-colors.vim" "hi LineNr           guifg=$(key "$THEME" muted) "
fi
# A running Neovim showing kadomo takes the new theme. TMPDIR points at the
# test's own folder, so no Neovim of yours is reached.
mkdir -p "$HOME/.config/nvim/colors" "$WORK/tmp/nvim.$USER/test"
ln -sfh "$THEME/neovim-colors.lua" "$HOME/.config/nvim/colors/kadomo.lua"
socket="$WORK/tmp/nvim.$USER/test/nvim.1.0"
XDG_STATE_HOME="$WORK/nvim-state" XDG_DATA_HOME="$WORK/nvim-data" nvim --clean --headless --listen "$socket" \
    -c "set termguicolors" -c "set rtp^=$HOME/.config/nvim" -c "colorscheme kadomo" >/dev/null 2>&1 &
nvim_pid=$!
for _ in $(seq 50); do [[ -S "$socket" ]] && break; sleep 0.1; done
normal_bg() { nvim --server "$socket" --remote-expr 'printf("#%06x", nvim_get_hl(0, {"name": "Normal"}).bg)' 2>/dev/null; }
if [[ -S "$socket" ]]; then
    check "a running Neovim shows tmac2k" same "$(normal_bg)" "#000000"
    TMPDIR="$WORK/tmp" KADOMO_THEME_APPS=neovim "$BIN/theme-set" gruvbox >/dev/null
    check "  and gruvbox after theme-set, without restarting" same "$(normal_bg)" "#282828"
else
    echo "  - skipped live Neovim reload: this environment cannot open a Neovim socket"
fi
kill "$nvim_pid" 2>/dev/null; wait "$nvim_pid" 2>/dev/null

mkdir -p "$HOME/.config/nvim/lua/plugins"
KADOMO_THEME_APPS=neovim "$BIN/theme-set" catppuccin >/dev/null
check "LazyVim: lua/plugins/theme.lua links to the theme" same "$(readlink "$HOME/.config/nvim/lua/plugins/theme.lua")" "$THEME/neovim.lua"
check "  catppuccin names its plugin" has "$HOME/.config/nvim/lua/plugins/theme.lua" catppuccin-mocha
KADOMO_THEME_APPS=neovim "$BIN/theme-set" tmac2k >/dev/null
check "  tmac2k uses the kadomo colorscheme" has "$HOME/.config/nvim/lua/plugins/theme.lua" 'colorscheme = "kadomo"'
rm -rf "$HOME/.config/nvim"

echo "Kadomo Menu lists the themes and wallpapers"
menu="$HOME/.config/kadomo/menu/commands/themes.toml"
check "a command per theme under Appearance > Themes" same "$(grep -c '^category = "appearance/themes"' "$menu")" "$(($("$BIN/theme-list" | wc -l) + 1))"
check "the current one is marked" bash -c "grep -A5 'title = \"tmac2k\"' '$menu' | grep -q 'hint = \"current\"'"
check "a command per wallpaper" same "$(grep -c 'theme-bg-set' "$menu")" 3

echo "theme-set --external: a theme folder kept elsewhere (Kadomo Menu's Omarchy themes)"
"$BIN/theme-set" gruvbox >/dev/null
ext="$WORK/app support/omarchy/themes/tokyo-test"
mkdir -p "$ext/backgrounds"
printf 'mode = "light"\naccent = "#1e66f5"\nbackground = "#eff1f5"\nforeground = "#4c4f69"\n' >"$ext/colors.toml"
printf 'theme[main_bg]="#010203"\n' >"$ext/btop.theme"
printf 'command = /tmp/kadomo-pwned\nbackground = #ff0000\n' >"$ext/ghostty.conf"
printf 'os.execute("touch /tmp/kadomo-pwned")\n' >"$ext/neovim.lua"
cp "$ROOT/themes/gruvbox/backgrounds/0-glow.png" "$ext/backgrounds/0-one.png"
cp "$ROOT/themes/gruvbox/backgrounds/1-horizon.png" "$ext/backgrounds/1-two.png"
"$BIN/theme-set" --external "$ext" omarchy-tokyo-test "Tokyo Test" >"$WORK/out" 2>"$WORK/err"
check "prints its label" has "$WORK/out" "Theme: Tokyo Test"
check "every app gets its palette" same "$(key "$THEME" background)" "#eff1f5"
check "  kitty too" has "$THEME/kitty.conf" "background #eff1f5"
check "  and the launcher, with its label" has "$THEME/kadomo-menu.toml" 'name = "Kadomo (Tokyo Test)"'
check "light mode" same "$(key "$THEME" mode)" light
check "its btop.theme is used" has "$THEME/btop.theme" '#010203'
check "its ghostty.conf is not" lacks "$THEME/ghostty.conf" "kadomo-pwned"
check "its neovim.lua is not" lacks "$THEME/neovim.lua" "kadomo-pwned"
check "Neovim gets the kadomo colorscheme in its colors" has "$THEME/neovim-colors.lua" "#eff1f5"
check "the wallpaper is its first, used in place" same "$(readlink "$CUR/background")" "$ext/backgrounds/0-one.png"
check "theme.external records it" same "$(cut -f1,2 "$CUR/theme.external")" "omarchy-tokyo-test	Tokyo Test"
check "theme-current shows the label" same "$("$BIN/theme-current")" "Tokyo Test"
"$BIN/theme-bg-next" >/dev/null
check "theme-bg-next uses its wallpapers" same "$(readlink "$CUR/background")" "$ext/backgrounds/1-two.png"
"$BIN/theme-refresh" >/dev/null 2>&1
check "theme-refresh keeps it" same "$(cat "$CUR/theme.name")" omarchy-tokyo-test
check "  and the wallpaper" same "$(readlink "$CUR/background")" "$ext/backgrounds/1-two.png"
check "it is not listed among Kadomo's themes" lacks "$HOME/.config/kadomo/menu/commands/themes.toml" "omarchy-tokyo-test"
check "a Kadomo theme name is refused" bash -c "! '$BIN/theme-set' --external '$ext' gruvbox 2>/dev/null"
check "a relative folder is refused" bash -c "! '$BIN/theme-set' --external relative/x omarchy-x 2>/dev/null"
ln -s "$ext" "$WORK/linked-theme"
check "a symlinked folder is refused" bash -c "! '$BIN/theme-set' --external '$WORK/linked-theme' omarchy-x 2>/dev/null"
"$BIN/theme-set" --native >/dev/null
check "--native goes back to the last Kadomo theme" same "$(cat "$CUR/theme.name")" gruvbox
check "  and forgets the external one" [ ! -e "$CUR/theme.external" ]
check "  with its wallpaper" same "$(dirname "$(readlink "$CUR/background")")" "$ROOT/themes/gruvbox/backgrounds"
"$BIN/theme-set" --native >"$WORK/out"
check "--native does nothing when a Kadomo theme shows" has "$WORK/out" "already"
check "nothing ran" [ ! -e /tmp/kadomo-pwned ]
lightonly="$WORK/app support/omarchy/themes/light-only"
mkdir -p "$lightonly"
printf 'background = "#fafafa"\nforeground = "#222222"\n' >"$lightonly/colors.toml"
: >"$lightonly/light.mode"
printf '[launcher]\ntext = "#000000"\n' >"$lightonly/shell.toml"
"$BIN/theme-set" --external "$lightonly" omarchy-light-only >/dev/null 2>"$WORK/err"
check "light.mode makes an external theme light" same "$(key "$THEME" mode)" light
check "  without warning about files its provider uses" lacks "$WORK/err" "shell.toml"
drawn="$(readlink "$CUR/background")"
check "a theme with no wallpapers gets one drawn from its colors" bash -c "[[ '$drawn' == '$HOME/.local/state/kadomo/wallpapers/omarchy-light-only-'*.png ]] && file '$drawn' | grep -q 'PNG image' && [ \$(stat -f %z '$drawn') -gt 200000 ]"
"$BIN/theme-set" gruvbox >/dev/null
"$BIN/theme-set" --external "$lightonly" omarchy-light-only >/dev/null 2>&1
check "  the same file next time" same "$(readlink "$CUR/background")" "$drawn"
"$BIN/theme-set" --native >/dev/null

echo "VS Code"
for name in $("$BIN/theme-list" --names); do
    [[ "$name" == evil || "$name" == old-school ]] && continue
    "$BIN/theme-set" "$name" >/dev/null 2>&1
    check "$name: vscode-theme.json is valid JSON" plutil -convert xml1 -o /dev/null "$THEME/vscode-theme.json"
    check "  every placeholder filled" lacks "$THEME/vscode-theme.json" "{{"
    check "  light or dark like the theme" has "$THEME/vscode-theme.json" "\"type\": \"$(key "$THEME" mode)\""
done
# A stand-in VS Code: its CLI installs an extension by adding it to the
# registry, as the real one does, and logs every call.
VS="$WORK/vscode"
VSUSER="$HOME/Library/Application Support/Code/User"
VSEXT="$HOME/.vscode/extensions"
mkdir -p "$VS"
cat >"$VS/code" <<EOF
#!/bin/bash
J='$ROOT/lib/vscode.js' E='$VSEXT'
echo "code \$*" >>'$VS/log'
case "\$1" in
    --install-extension) mkdir -p "\$E/\$2"; osascript -l JavaScript "\$J" register "\$E" "\$2" 1.0.0 ;;
    --uninstall-extension) osascript -l JavaScript "\$J" unregister "\$E" "\$2" >/dev/null; rm -rf "\$E/\$2" ;;
esac
EOF
chmod +x "$VS/code"
vs_theme() { osascript -l JavaScript "$ROOT/lib/vscode.js" get "$VSUSER/settings.json" 2>/dev/null; }
vs_log() { cat "$VS/log" 2>/dev/null; }
"$BIN/theme-set" catppuccin >/dev/null
check "without VS Code, theme-vscode apply says so" bash -c "'$BIN/theme-vscode' apply 2>&1 | grep -q 'VS Code is not installed'"
check "  and a switch leaves VS Code's files alone" bash -c "KADOMO_THEME_APPS=vscode '$BIN/theme-set' gruvbox >/dev/null 2>&1; [ ! -e '$HOME/.vscode' ]"
export KADOMO_VSCODE_CLI="$VS/code"
mkdir -p "$VSUSER" "$WORK/dotfiles"
printf '{\n    // my settings\n    "workbench.colorTheme": "Default Dark Modern",\n    "editor.fontSize": 13,\n}\n' >"$WORK/dotfiles/settings.json"
cp "$WORK/dotfiles/settings.json" "$WORK/vs-settings-before"
ln -s "$WORK/dotfiles/settings.json" "$VSUSER/settings.json"
"$BIN/theme-set" catppuccin >/dev/null
"$BIN/theme-vscode" enable >"$WORK/out" 2>&1
check "enable: VS Code shows Kadomo" same "$(vs_theme)" Kadomo
check "  the rest of settings.json stays as you wrote it" bash -c "grep -q '// my settings' '$VSUSER/settings.json' && grep -q '\"editor.fontSize\": 13,' '$VSUSER/settings.json'"
check "  settings.json is still your symlink" same "$(readlink "$VSUSER/settings.json")" "$WORK/dotfiles/settings.json"
check "  the Kadomo extension is registered" has "$VSEXT/extensions.json" '"id":"kadomo.kadomo-theme"'
check "  with Catppuccin's colors" cmp -s "$THEME/vscode-theme.json" "$VSEXT/kadomo.kadomo-theme/themes/kadomo-color-theme.json"
check "  as a dark theme" has "$VSEXT/kadomo.kadomo-theme/package.json" '"uiTheme": "vs-dark"'
check "  theme.conf now lists vscode" bash -c "grep '^apps' '$HOME/.config/kadomo/theme.conf' 2>/dev/null | grep -qw vscode || [ ! -e '$HOME/.config/kadomo/theme.conf' ]"
check "  nothing from the Marketplace" same "$(vs_log)" ""
KADOMO_THEME_APPS=vscode "$BIN/theme-set" catppuccin-latte >/dev/null
check "a switch updates the colors" cmp -s "$THEME/vscode-theme.json" "$VSEXT/kadomo.kadomo-theme/themes/kadomo-color-theme.json"
check "  light now" has "$VSEXT/kadomo.kadomo-theme/package.json" '"uiTheme": "vs"'

# An Omarchy theme whose vscode.json names a Marketplace theme: ignored.
om="$WORK/app support/omarchy/themes/tokyo-vs"
mkdir -p "$om"
cp "$ROOT/themes/catppuccin/colors.toml" "$om/"
printf '{\n  "name": "Tokyo Night",\n  "extension": "enkia.tokyo-night"\n}\n' >"$om/vscode.json"
: >"$VS/log"
KADOMO_THEME_APPS=vscode "$BIN/theme-set" --external "$om" omarchy-tokyo-vs "Tokyo VS" >/dev/null 2>&1
"$BIN/theme-vscode" apply >/dev/null 2>&1
check "a theme's vscode.json installs nothing" same "$(vs_log)" ""
check "  VS Code shows Kadomo's colors for it" same "$(vs_theme)" Kadomo
check "  its colors, not the last theme's" cmp -s "$THEME/vscode-theme.json" "$VSEXT/kadomo.kadomo-theme/themes/kadomo-color-theme.json"
check "  nothing recorded as installed" lacks "$HOME/.local/state/kadomo/vscode.txt" "extension|"
check "theme-vscode status" bash -c "'$BIN/theme-vscode' status | grep -q 'color theme: Kadomo'"
# A Marketplace theme an older Kadomo installed is still removed on disable.
"$VS/code" --install-extension enkia.tokyo-night >/dev/null
printf 'extension|enkia.tokyo-night\n' >>"$HOME/.local/state/kadomo/vscode.txt"
: >"$VS/log"
"$BIN/theme-set" --native >/dev/null

"$BIN/theme-vscode" disable >"$WORK/out" 2>&1
check "disable: your color theme from before comes back" bash -c "grep -q 'Default Dark Modern' '$WORK/out'"
check "  settings.json exactly as it was" cmp -s "$WORK/vs-settings-before" "$WORK/dotfiles/settings.json"
check "  still a symlink" [ -L "$VSUSER/settings.json" ]
check "  the Kadomo extension is gone" [ ! -e "$VSEXT/kadomo.kadomo-theme" ]
check "  the Marketplace theme an older Kadomo installed too" has "$VS/log" "code --uninstall-extension enkia.tokyo-night"
check "  and ~/.vscode, which Kadomo made" [ ! -e "$HOME/.vscode" ]
check "  and its record" [ ! -e "$HOME/.local/state/kadomo/vscode.txt" ]
check "  theme.conf no longer lists vscode" bash -c "! grep '^apps' '$HOME/.config/kadomo/theme.conf' 2>/dev/null | grep -qw vscode"
rm -rf "$HOME/Library/Application Support/Code"
"$BIN/theme-vscode" apply >/dev/null 2>&1
check "with no settings.json, one is made" same "$(vs_theme)" Kadomo
"$BIN/theme-vscode" disable >/dev/null 2>&1
check "  and removed again, with the folders Kadomo made" [ ! -e "$HOME/Library/Application Support/Code" ]
check "  ~/Library itself stays" [ -d "$HOME/Library" ]
export KADOMO_VSCODE_CLI=""
check "nothing ran" [ ! -e /tmp/kadomo-pwned ]

echo "theme-remove"
"$BIN/theme-set" evil >/dev/null 2>&1
"$BIN/theme-remove" evil >/dev/null 2>&1
check "removing the current theme falls back to tmac2k" same "$(cat "$CUR/theme.name")" tmac2k
check "  and the folder is gone" [ ! -e "$HOME/.config/kadomo/themes/evil" ]
check "built-in themes cannot be removed" bash -c "! '$BIN/theme-remove' gruvbox 2>/dev/null"

echo "The wallpaper from before install comes back on every Space"
store="$WORK/Index.plist"
python3 - "$store" <<'EOF'
import plistlib, sys, datetime
def pic(url, day, provider='com.apple.wallpaper.choice.image'):
    return {'Content': {'Choices': [{'Provider': provider, 'Files': [{'relative': url}] if url else [], 'Configuration': b''}]},
            'LastSet': datetime.datetime(2026, 1, day)}
plistlib.dump({'AllSpacesAndDisplays': {'Desktop': pic(None, 5, 'com.apple.wallpaper.choice.aerials'), 'Idle': {'saver': 'before'}},
               'Spaces': {'S1': {'Default': {'Desktop': pic('file:///old/my%20photo.jpg', 2)}}}},
              open(sys.argv[1], 'wb'), fmt=plistlib.FMT_BINARY)
EOF
KADOMO_WALLPAPER_STORE="$store" osascript -l JavaScript "$ROOT/lib/wallpaper.js" save "$WORK/before.plist" >/dev/null
check "save copies the store" cmp -s "$store" "$WORK/before.plist"
python3 - "$store" "$HOME" <<'EOF'
import plistlib, sys, datetime
s = plistlib.load(open(sys.argv[1], 'rb'))
def pic(url, day): return {'Content': {'Choices': [{'Files': [{'relative': url}]}]}, 'LastSet': datetime.datetime(2026, 2, day)}
ours = pic('file://' + sys.argv[2] + '/.local/share/kadomo/theme-manager/themes/tmac2k/backgrounds/0.png', 1)
s['AllSpacesAndDisplays']['Desktop'] = ours
s['AllSpacesAndDisplays']['Idle'] = {'saver': 'since'}
s['Spaces']['S1']['Default']['Desktop'] = ours
s['Spaces']['S2'] = {'Default': {'Desktop': ours}}
s['Spaces']['S3'] = {'Default': {'Desktop': pic('file:///mine/since.png', 2)}}
plistlib.dump(s, open(sys.argv[1], 'wb'), fmt=plistlib.FMT_BINARY)
EOF
KADOMO_WALLPAPER_STORE="$store" osascript -l JavaScript "$ROOT/lib/wallpaper.js" restore "$WORK/before.plist" "$HOME/.local/share/kadomo/theme-manager" >/dev/null
shows() { python3 -c 'import plistlib, sys
s = plistlib.load(open(sys.argv[1], "rb")); e = s
for k in sys.argv[2].split("/"): e = e[k]
c = e["Desktop"]["Content"]["Choices"][0]; print(c.get("Provider") or c["Files"][0]["relative"])' "$store" "$1"; }
check "an aerial comes back" same "$(shows AllSpacesAndDisplays)" com.apple.wallpaper.choice.aerials
check "a Space's photo comes back" same "$(shows Spaces/S1/Default)" com.apple.wallpaper.choice.image
check "a Space made since gets the picture shown last before" same "$(shows Spaces/S2/Default)" com.apple.wallpaper.choice.aerials
check "a picture chosen since stays" same "$(shows Spaces/S3/Default)" file:///mine/since.png
check "the screen saver is left alone" bash -c "plutil -p '$store' | grep -q since"

echo "install.sh and uninstall.sh leave no trace"
export HOME="$WORK/home2" KADOMO_STATE_DIR="$WORK/app-support2"
mkdir -p "$HOME/.config/ghostty" "$HOME/.config/btop" "$HOME/.config/nvim"
printf 'font-size = 14\n' >"$HOME/.config/ghostty/config"
printf 'vim.o.number = true\n' >"$HOME/.config/nvim/init.lua"
printf 'color_theme = "Default"\nupdate_ms = 1000\n' >"$HOME/.config/btop/btop.conf"
snapshot() { (cd "$HOME" && find . -print0 | sort -z | xargs -0 ls -ld | awk '{ print $1, $NF }'; find . -type f -exec shasum {} + | sort); }
snapshot >"$WORK/before"
"$ROOT/install.sh" --dry-run --only themes,btop >/dev/null
snapshot >"$WORK/dry"
check "--dry-run changes nothing" cmp -s "$WORK/before" "$WORK/dry"
"$ROOT/install.sh" --only themes,btop >"$WORK/install.log" 2>&1
check "installs" same "$?" 0
check "commands linked into ~/.local/bin" [ -L "$HOME/.local/bin/theme-set" -a -x "$HOME/.local/bin/theme-set" ]
check "tmac2k applied" same "$(cat "$HOME/.config/kadomo/current/theme.name")" tmac2k
check "Ghostty config reads the theme" has "$HOME/.config/ghostty/config" 'config-file = ?"~/.config/kadomo/current/theme/ghostty.conf"'
check "  and keeps your settings" has "$HOME/.config/ghostty/config" "font-size = 14"
check "kitty.conf made to read it" has "$HOME/.config/kitty/kitty.conf" "include ~/.config/kadomo/current/theme/kitty.conf"
check "btop shows the current theme" has "$HOME/.config/btop/btop.conf" 'color_theme = "current"'
check "  through current.theme" same "$(readlink "$HOME/.config/btop/themes/current.theme")" "$HOME/.config/kadomo/current/theme/btop.theme"
check "the installed commands work" same "$("$HOME/.local/bin/theme-current")" tmac2k
check "init.lua selects kadomo" has "$HOME/.config/nvim/init.lua" 'pcall(vim.cmd.colorscheme, "kadomo")'
check "  and keeps your settings" has "$HOME/.config/nvim/init.lua" "vim.o.number = true"
check "Neovim starts in tmac2k" same "$(XDG_STATE_HOME="$WORK/nvim-state" XDG_DATA_HOME="$WORK/nvim-data" nvim --headless -c 'lua io.stdout:write(vim.g.colors_name .. " " .. string.format("#%06x", vim.api.nvim_get_hl(0, {name = "Normal"}).fg))' -c q 2>&1 | grep -v 'nice(5)')" "kadomo #d1d1d1"
check "a ~/.vimrc is made" has "$HOME/.vimrc" "silent! colorscheme kadomo"
check "  that keeps Vim's defaults" has "$HOME/.vimrc" "source \$VIMRUNTIME/defaults.vim"
check "Vim starts in tmac2k" same "$(/usr/bin/vim -u "$HOME/.vimrc" -i NONE -es -c 'put =g:colors_name' -c '%p' -c 'q!' 2>&1 | grep -x kadomo)" kadomo
# The theme-install link an older install made.
ln -s "$HOME/.local/share/kadomo/theme-manager/bin/theme-install" "$HOME/.local/bin/theme-install"
"$ROOT/install.sh" --only themes,btop >/dev/null 2>&1
check "installing again removes the old theme-install link" [ ! -L "$HOME/.local/bin/theme-install" ]
check "installing again adds nothing twice" same "$(grep -c 'kadomo/current' "$HOME/.config/ghostty/config")" 1
"$HOME/.local/bin/theme-set" gruvbox >/dev/null
"$ROOT/install.sh" --only themes,btop >/dev/null 2>&1
check "  and keeps the theme you had" same "$(cat "$HOME/.config/kadomo/current/theme.name")" gruvbox
printf 'purple-night\n' >"$HOME/.config/kadomo/current/theme.name"
mkdir -p "$HOME/.config/kadomo/themes/purple-night"
printf 'background = #123456\n' >"$HOME/.config/kadomo/themes/purple-night/ghostty.conf"
"$ROOT/install.sh" --only themes,btop >/dev/null 2>&1
check "  Purple Night, no longer built in, becomes tmac2k" same "$(cat "$HOME/.config/kadomo/current/theme.name")" tmac2k
printf 'tokyo-night\n' >"$HOME/.config/kadomo/current/theme.name"
"$ROOT/install.sh" --only themes,btop >/dev/null 2>&1
check "  so does Tokyo Night" same "$(cat "$HOME/.config/kadomo/current/theme.name")" tmac2k
rm -rf -- "$HOME/.config/kadomo/themes/purple-night"
"$HOME/.local/bin/theme-set" --external "$ext" omarchy-tokyo-test "Tokyo Test" >/dev/null
"$ROOT/install.sh" --only themes,btop >/dev/null 2>&1
check "  or the external theme you had" same "$(cat "$HOME/.config/kadomo/current/theme.name")" omarchy-tokyo-test
check "  still external" same "$(cut -f1 "$HOME/.config/kadomo/current/theme.external")" omarchy-tokyo-test
"$HOME/.local/bin/theme-set" gruvbox >/dev/null
"$ROOT/uninstall.sh" --dry-run >/dev/null
check "uninstall --dry-run changes nothing" [ -L "$HOME/.local/bin/theme-set" ]
"$ROOT/uninstall.sh" >"$WORK/uninstall.log" 2>&1
check "uninstalls" same "$?" 0
snapshot >"$WORK/after"
check "everything is as it was" cmp -s "$WORK/before" "$WORK/after"
cmp -s "$WORK/before" "$WORK/after" || diff "$WORK/before" "$WORK/after" | head -20
check "nothing left in Application Support" [ ! -e "$KADOMO_STATE_DIR" ]
"$ROOT/uninstall.sh" >"$WORK/again"
check "uninstalling again finds nothing" has "$WORK/again" "no kadomo-theme-manager installed"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
((FAIL == 0))
