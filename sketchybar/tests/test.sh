#!/bin/bash
# Checks sketchybar/install.sh and uninstall.sh in a throwaway HOME, with a
# stand-in brew, defaults, osascript, and bar. Nothing is installed on this Mac,
# nothing is downloaded, and no real setting is read or changed.
#
# Usage: sketchybar/tests/test.sh
set -uo pipefail

SB="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/kadomo-sketchybar-test.XXXXXX")"
trap '[[ -n "${KEEP:-}" ]] || rm -rf "$WORK"' EXIT
PASS=0
FAIL=0

check() {
    local what="$1"; shift
    if "$@"; then PASS=$((PASS + 1)); printf '  ✓ %s\n' "$what"
    else FAIL=$((FAIL + 1)); printf '  ✗ %s\n' "$what"; fi
}
has() { grep -qF -- "$2" "$1" 2>/dev/null; }
lacks() { ! grep -qF -- "$2" "$1" 2>/dev/null; }
exists() { [[ -e "$1" ]]; }
gone() { [[ ! -e "$1" ]]; }

# A fresh world. INSTALLED lists what the stand-in brew says is there already.
setup() {
    W="$WORK/$1"; H="$W/home"; STUBS="$W/bin"; LOG="$W/calls.log"
    rm -rf -- "$W"; mkdir -p "$H/.config/omniwm" "$STUBS"; : >"$LOG"
    cat >"$H/.config/omniwm/settings.toml" <<'EOF'
[gaps.outer]
bottom = 0.0
top = 0.0

[general]
ipcEnabled = false
EOF
    cat >"$STUBS/brew" <<EOF
#!/bin/bash
echo "brew \$*" >>"$LOG"
case "\$1" in
    tap) if [[ \$# -gt 1 ]]; then echo "\$2" >>"$W/tapped"; else printf '%s\n' \${TAPS:-}; cat "$W/tapped" 2>/dev/null; fi ;;
    list) [[ " \${INSTALLED:-} " == *" \${@: -1} "* ]] ;;
esac
EOF
    local cmd
    for cmd in defaults osascript pkill sketchybar; do
        printf '#!/bin/bash\necho "%s $*" >>"%s"\n' "$cmd" "$LOG" >"$STUBS/$cmd"
    done
    # defaults read says the key is absent; the menu bar is not hidden.
    printf '#!/bin/bash\necho "defaults $*" >>"%s"\n[[ "$1" != read ]]\n' "$LOG" >"$STUBS/defaults"
    printf '#!/bin/bash\necho "osascript $*" >>"%s"\n[[ "$*" != *" get "* ]] || echo false\n[[ "$*" != *"fonts.js register"* ]] || echo registered\n' "$LOG" >"$STUBS/osascript"
    printf '#!/bin/bash\n[[ -n "${BAR_RUNNING:-}" ]]\n' >"$STUBS/pgrep"
    chmod +x "$STUBS"/*
}
sb() { # <script> [args...]
    local script="$1"; shift
    HOME="$H" XDG_CONFIG_HOME="$H/.config" KADOMO_STATE_DIR="$H/state" KADOMO_BREW="$STUBS/brew" \
        PATH="$STUBS:/usr/bin:/bin:/usr/sbin:/sbin" "$SB/$script.sh" ${1+"$@"}
}

CONFIG() { printf '%s' "$H/.config/sketchybar"; }
SETTINGS() { printf '%s' "$H/.config/omniwm/settings.toml"; }
MANIFEST() { printf '%s' "$H/state/sketchybar-installed.txt"; }

echo "The config"
for file in "$SB"/config/sketchybarrc "$SB"/config/colors.sh "$SB"/config/icon_map.sh "$SB"/config/plugins/*.sh; do
    case "$file" in
        */tui.sh) check "${file##*/} parses" zsh -n "$file" ;;
        *) check "${file##*/} parses" bash -n "$file" ;;
    esac
    check "${file##*/} can be run" test -x "$file"
done
check "nothing is left of AeroSpace, Hammerspoon, or omarchy's commands" \
    bash -c "! grep -rnE 'aerospace|hs -c|omarchy-|theme-switcher' '$SB/config' --exclude=icon_map.sh"

check "the watcher finds the bar, its own ancestor" has "$SB/config/plugins/omniwm_watch.sh" "pgrep -axq sketchybar"
check "theme-set finds the bar when a click on it started theme-set" has "$SB/../kadomo-theme-manager/lib/reloaders.sh" "pgrep -axq sketchybar"

check "all nine of OmniWM's workspaces" has "$SB/config/sketchybarrc" "for sid in 1 2 3 4 5 6 7 8 9; do"
check "the bar stays above the menu bar, which would take its clicks" has "$SB/config/sketchybarrc" "topmost=on"
check "the bar keeps the open app's name" has "$SB/config/plugins/front_app.sh" 'label="$INFO"'
check "no glyph is written in a way the bar's bash cannot read" bash -c "! grep -rn \"\\$'\\\\U\" '$SB/config'"
check "nothing is left of the font it used before" bash -c "! grep -rn 'Hack Nerd Font' '$SB/config'"

echo "The workspaces"
setup workspaces
mkdir -p "$H/.local/bin"
printf '#!/bin/bash\necho "$*" >>"%s"\n' "$LOG" >"$H/.local/bin/sketchybar"
chmod +x "$H/.local/bin/sketchybar"
ws() { HOME="$H" CONFIG_DIR="$SB/config" NAME="space.$1" FOCUSED_WORKSPACE=2 "$SB/config/plugins/omniwm.sh"; }
ws 2
check "the focused one is a dot" has "$LOG" "--set space.2 icon=󰝥 icon.color="
ws 3
check "the others keep their number" has "$LOG" "--set space.3 icon=3 icon.color="

echo "A dry run"
setup dry
out="$(sb install --dry-run)"
check "says what it would do" grep -q 'would run: .*services restart sketchybar' <<<"$out"
check "places no config" gone "$(CONFIG)"
check "keeps no record" gone "$(MANIFEST)"
check "leaves OmniWM alone" has "$(SETTINGS)" 'ipcEnabled = false'
check "installs nothing" lacks "$LOG" 'install'
check "writes no menu entries" gone "$H/.config/kadomo/menu/commands/sketchybar.toml"

echo "Installing"
setup install
sb install >"$W/out" 2>&1
check "tap first" has "$LOG" "brew tap felixkratz/formulae"
check "SketchyBar" has "$LOG" "brew install --formula felixkratz/formulae/sketchybar"
check "the fonts" has "$LOG" "brew install --cask font-sketchybar-app-font"
check "the config" exists "$(CONFIG)/sketchybarrc"
check "registers no font whose file is not there" lacks "$LOG" "fonts.js register"
check "the plugins" exists "$(CONFIG)/plugins/omniwm.sh"
check "hides the menu bar" has "$LOG" "defaults write NSGlobalDomain _HIHideMenuBar -bool true"
check "turns on OmniWM's IPC" has "$(SETTINGS)" 'ipcEnabled = true'
check "makes room for the bar" has "$(SETTINGS)" 'top = 32.0'
check "changes only that gap" has "$(SETTINGS)" 'bottom = 0.0'
check "starts the bar" has "$LOG" "brew services restart sketchybar"
MENU="$H/.config/kadomo/menu/commands/sketchybar.toml"
check "adds SketchyBar under Services" has "$MENU" 'id = "services/sketchybar"'
for verb in start stop restart; do
    check "with $verb" has "$MENU" "args = [\"services\", \"$verb\", \"sketchybar\"]"
done
check "through the brew it found" has "$MENU" "exec = \"$STUBS/brew\""
check "adds the menu bar under Services" has "$MENU" 'id = "services/menu-bar"'
for verb in toggle show hide; do
    check "with $verb" has "$MENU" "args = [\"$verb\"]"
done
check "with a key for the toggle" has "$MENU" 'hotkey = "option+shift+m"'
check "and only for the toggle" test "$(grep -c '^hotkey = ' "$MENU")" = 1
check "and says so under Keybinds" has "$MENU" 'key = "OPT SHIFT + M"'
check "through the bar's plugin" has "$MENU" "exec = \"$(CONFIG)/plugins/menu_bar.sh\""
check "leaves no stray file there" test "$(ls -A "$(dirname "$MENU")")" = sketchybar.toml
check "records what it installed" has "$(MANIFEST)" "formula|felixkratz/formulae/sketchybar"
check "records the menu bar before" has "$(MANIFEST)" "hide-menu-bar|absent"
check "records the gap before" has "$(MANIFEST)" "omniwm-gap-top|0.0"

echo "Installing again"
sb install >"$W/out" 2>&1
check "the config is unchanged" has "$W/out" "(unchanged)"
check "the record of the menu bar is the first one" test "$(grep -c '^hide-menu-bar|' "$(MANIFEST)")" = 1
check "the record of the gap is the first one" has "$(MANIFEST)" "omniwm-gap-top|0.0"
check "one record of the config" test "$(grep -c '^config-sha|' "$(MANIFEST)")" = 1

echo "An edited config at update"
echo "# mine" >>"$(CONFIG)/sketchybarrc"
sb install >"$W/out" 2>&1
check "is backed up" bash -c "grep -q '# mine' '$(CONFIG)'.bak.*/sketchybarrc"
check "the copy is Kadomo's again" lacks "$(CONFIG)/sketchybarrc" "# mine"

echo "Uninstalling"
setup uninstall
sb install >/dev/null 2>&1
plan="$(sb uninstall --dry-run)"
check "a dry run removes nothing" exists "$(CONFIG)/sketchybarrc"
check "a dry run lists the config" grep -q '\.config/sketchybar$' <<<"$plan"
: >"$LOG"
BAR_RUNNING=1 sb uninstall >"$W/out" 2>&1
check "stops the bar first" has "$LOG" "brew services stop sketchybar"
check "stops the watcher" has "$LOG" "pkill -f omniwmctl watch active-workspace"
check "removes the config" gone "$(CONFIG)"
check "removes the menu entries" gone "$H/.config/kadomo/menu/commands/sketchybar.toml"
check "shows the menu bar again" has "$LOG" "defaults delete NSGlobalDomain _HIHideMenuBar"
check "as it was" has "$LOG" "set autohide menu bar of dock preferences to false"
check "OmniWM's IPC goes back" has "$(SETTINGS)" 'ipcEnabled = false'
check "OmniWM's gap goes back" has "$(SETTINGS)" 'top = 0.0'
check "removes what it installed" has "$LOG" "brew uninstall --formula felixkratz/formulae/sketchybar"
check "removes the fonts" has "$LOG" "brew uninstall --cask font-jetbrains-mono-nerd-font"
check "removes the tap" has "$LOG" "brew untap felixkratz/formulae"
check "removes its record" gone "$(MANIFEST)"
out="$(sb uninstall --dry-run)"
check "then nothing is left to do" grep -q 'no sketchybar installed' <<<"$out"

echo "What was yours"
setup yours
mkdir -p "$(CONFIG)" "$H/Library/Fonts"; echo "# my bar" >"$(CONFIG)/sketchybarrc"
touch "$H/Library/Fonts/JetBrainsMonoNerdFont-Regular.ttf" "$H/Library/Fonts/sketchybar-app-font.ttf"
sed -i '' 's/^top = 0.0/top = 50.0/; s/^ipcEnabled = false/ipcEnabled = true/' "$(SETTINGS)"
TAPS="FelixKratz/formulae" INSTALLED="sketchybar switchaudio-osx" BAR_RUNNING=1 \
    sb install >"$W/out" 2>&1
check "your config is backed up" has "$W/out" "backed up to sketchybar.bak."
check "installs no package you have" lacks "$LOG" "brew install --formula"
check "adds no tap you have" lacks "$(MANIFEST)" "tap|"
check "a bigger gap of yours stays" has "$(SETTINGS)" 'top = 50.0'
check "records no setting it left alone" lacks "$(MANIFEST)" "omniwm-"
: >"$LOG"
BAR_RUNNING=1 sb uninstall >"$W/out" 2>&1
check "your config comes back" has "$(CONFIG)/sketchybarrc" "# my bar"
check "your bar keeps running" lacks "$LOG" "brew services stop"
check "and reads your config" has "$LOG" "sketchybar --reload"
check "your packages stay" lacks "$LOG" "brew uninstall"
check "your IPC stays on" has "$(SETTINGS)" 'ipcEnabled = true'

echo "Registering fonts"
setup fonts
mkdir -p "$H/Library/Fonts"
touch "$H/Library/Fonts/JetBrainsMonoNerdFont-Regular.ttf" "$H/Library/Fonts/JetBrainsMonoNerdFontMono-Regular.ttf" "$H/Library/Fonts/sketchybar-app-font.ttf"
out="$(sb install --dry-run)"
check "a dry run registers nothing" lacks "$LOG" "fonts.js register"
check "a dry run says it would" grep -q 'would run: register_font .*sketchybar-app-font.ttf' <<<"$out"
sb install >/dev/null 2>&1
check "the font the bar asks for" has "$LOG" "fonts.js register $H/Library/Fonts/JetBrainsMonoNerdFont-Regular.ttf"
check "the app icons" has "$LOG" "fonts.js register $H/Library/Fonts/sketchybar-app-font.ttf"
check "not the Mono variant it does not use" lacks "$LOG" "JetBrainsMonoNerdFontMono-Regular.ttf"
check "before the bar starts" bash -c "grep -n 'fonts.js register' '$LOG' | tail -1 | cut -d: -f1 | { read a; b=\$(grep -n 'services restart' '$LOG' | cut -d: -f1); [ \"\$a\" -lt \"\$b\" ]; }"
check "records them" has "$(MANIFEST)" "font-file|$H/Library/Fonts/sketchybar-app-font.ttf"
sb install >/dev/null 2>&1
check "one record each when installed again" test "$(grep -c '^font-file|.*sketchybar-app-font' "$(MANIFEST)")" = 1
: >"$LOG"
sb uninstall >/dev/null 2>&1
check "uninstall takes them back" has "$LOG" "fonts.js unregister $H/Library/Fonts/sketchybar-app-font.ttf"
check "before removing the fonts" bash -c "grep -n 'fonts.js unregister' '$LOG' | tail -1 | cut -d: -f1 | { read a; b=\$(grep -n 'uninstall --cask font-sketchybar' '$LOG' | cut -d: -f1); [ -z \"\$b\" ] || [ \"\$a\" -lt \"\$b\" ]; }"

echo "An edited config at uninstall"
setup edited
sb install >/dev/null 2>&1
echo "# mine" >>"$(CONFIG)/sketchybarrc"
sb uninstall >"$W/out" 2>&1
check "is kept" bash -c "grep -q '# mine' '$(CONFIG)'.bak.*/sketchybarrc"

echo "OmniWM's settings changed since"
setup changed
sb install >/dev/null 2>&1
sed -i '' 's/^top = 32.0/top = 60.0/' "$(SETTINGS)"
sb uninstall >/dev/null 2>&1
check "your gap stays" has "$(SETTINGS)" 'top = 60.0'

echo "Without OmniWM"
setup no-omniwm
rm -f "$(SETTINGS)"
sb install >"$W/out" 2>&1
check "installs" exists "$(CONFIG)/sketchybarrc"
check "writes no settings" gone "$(SETTINGS)"

echo "The menu bar item"
setup menu-bar
sb install >/dev/null 2>&1
echo true >"$W/autohide"
cat >"$STUBS/osascript" <<EOF
#!/bin/bash
echo "osascript \$*" >>"$LOG"
case "\$*" in
    *"get autohide"*) cat "$W/autohide" ;;
    *"to true") echo true >"$W/autohide" ;;
    *"to false") echo false >"$W/autohide" ;;
    *JavaScript*) echo 33 ;;
esac
EOF
# colors.sh puts ~/.local/bin and then Homebrew first on the PATH, so the stand-ins
# go in that ~/.local/bin: from anywhere else, the plugin would reach the real bar.
mb() {
    mkdir -p "$H/.local/bin"; ln -sf "$STUBS"/* "$H/.local/bin/"
    HOME="$H" CONFIG_DIR="$(CONFIG)" XDG_CONFIG_HOME="$H/.config" KADOMO_STATE_DIR="$H/state" PATH="$STUBS:/usr/bin:/bin" "$(CONFIG)/plugins/menu_bar.sh" "$@"
}
GAP_FILE="$H/state/sketchybar-menu-bar-gap"
: >"$LOG"
mb sync
check "a sync leaves a hidden menu bar hidden" lacks "$LOG" "to false"
check "and the gap alone" has "$(SETTINGS)" 'top = 32.0'
mb toggle
check "a click shows the menu bar" has "$LOG" "set autohide menu bar of dock preferences to false"
check "moves the bar below it" has "$LOG" "sketchybar --bar y_offset=33"
check "and the windows below the bar" has "$(SETTINGS)" 'top = 65.0'
check "changes only that gap" has "$(SETTINGS)" 'bottom = 0.0'
mb sync
check "a reload does not raise the gap twice" has "$(SETTINGS)" 'top = 65.0'
check "and keeps what it was" has "$GAP_FILE" "32.0 65.0"
: >"$LOG"
mb
check "the next click hides the menu bar" has "$LOG" "set autohide menu bar of dock preferences to true"
check "puts the bar back" has "$LOG" "sketchybar --bar y_offset=0"
check "and the gap" has "$(SETTINGS)" 'top = 32.0'
check "and keeps no record" gone "$GAP_FILE"
check "and writes no stray file" bash -c "! ls -A '$H/.config/omniwm' | grep -q kadomo"
mb
sed -i '' 's/^top = 65.0/top = 70.0/' "$(SETTINGS)"
mb
check "a gap you changed in the meantime stays" has "$(SETTINGS)" 'top = 70.0'
sed -i '' 's/^top = 70.0/top = 32.0/' "$(SETTINGS)"
mb
sb uninstall >/dev/null 2>&1
check "uninstalling with the menu bar showing brings the gap back to before Kadomo" has "$(SETTINGS)" 'top = 0.0'
check "and removes the record" gone "$GAP_FILE"

echo "The menu bar, from Kadomo Menu"
setup menu-bar-menu
sb install >/dev/null 2>&1
echo true >"$W/autohide"
cat >"$STUBS/osascript" <<EOF
#!/bin/bash
echo "osascript \$*" >>"$LOG"
case "\$*" in
    *"get autohide"*) cat "$W/autohide" ;;
    *"to true") echo true >"$W/autohide" ;;
    *"to false") echo false >"$W/autohide" ;;
    *JavaScript*) echo 33 ;;
esac
EOF
: >"$LOG"
mb_menu() { mkdir -p "$H/.local/bin"; ln -sf "$STUBS"/* "$H/.local/bin/"; env -u CONFIG_DIR HOME="$H" XDG_CONFIG_HOME="$H/.config" KADOMO_STATE_DIR="$H/state" PATH="$STUBS:/usr/bin:/bin" "$(CONFIG)/plugins/menu_bar.sh" "$@"; }
mb_menu hide
check "hide with the menu bar hidden changes no gap" has "$(SETTINGS)" 'top = 32.0'
mb_menu show
check "show works without the bar's environment" has "$LOG" "sketchybar --bar y_offset=33"
check "raises the gap" has "$(SETTINGS)" 'top = 65.0'
mb_menu show
check "show twice raises it once" has "$(SETTINGS)" 'top = 65.0'
check "and stays showing" has "$W/autohide" "false"
mb_menu hide
check "hide puts the gap back" has "$(SETTINGS)" 'top = 32.0'
check "and hides the menu bar" has "$W/autohide" "true"

echo "The menu bar item, without OmniWM"
setup menu-bar-no-omniwm
sb install >/dev/null 2>&1
rm -f "$(SETTINGS)"
printf '#!/bin/bash\ncase "$*" in *"get autohide"*) echo true ;; *JavaScript*) echo 24 ;; esac\n' >"$STUBS/osascript"
: >"$LOG"
mb toggle
check "still moves the bar" has "$LOG" "sketchybar --bar y_offset=24"
check "writes no settings" gone "$(SETTINGS)"
check "keeps no record of a gap" gone "$GAP_FILE"

echo "The menu bar item, when System Events says no"
setup menu-bar-refused
sb install >/dev/null 2>&1
printf '#!/bin/bash\nexit 1\n' >"$STUBS/osascript"
: >"$LOG"
mb toggle
check "leaves the bar where it is" lacks "$LOG" "y_offset"
check "and the gap" has "$(SETTINGS)" 'top = 32.0'

echo "Double clicking the bar"
setup opacity
sb install >/dev/null 2>&1
mkdir -p "$H/.local/bin"
echo 0xc0112233 >"$W/color"
cat >"$STUBS/sketchybar" <<EOF
#!/bin/bash
case "\$*" in
    "--query bar") printf '{\n\t"color": "%s",\n\t"border_color": "0xffff0000"\n}\n' "\$(cat "$W/color")" ;;
    "--bar color="*) echo "\${2#color=}" >"$W/color" ;;
esac
EOF
ln -sf "$STUBS/sketchybar" "$H/.local/bin/sketchybar"
mkdir -p "$H/.config/kadomo/current/theme"
echo 'export BG_TRANS="0xc0112233"' >"$H/.config/kadomo/current/theme/sketchybar-colors.sh"
click() { HOME="$H" CONFIG_DIR="$(CONFIG)" TMPDIR="$W" BUTTON="${1:-left}" PATH="$STUBS:/usr/bin:/bin" "$(CONFIG)/plugins/bar_opacity.sh"; }
click
check "one click changes nothing" has "$W/color" 0xc0112233
rm -f "$W/sketchybar-last-click"
click right; click right
check "nor does a double click with the right button" has "$W/color" 0xc0112233
echo 1000 >"$W/sketchybar-last-click"
click
check "nor two clicks far apart" has "$W/color" 0xc0112233
rm -f "$W/sketchybar-last-click"
click; click
check "a double click takes the theme's color to 50%" has "$W/color" 0x80112233
click; click
check "the next to 25%" has "$W/color" 0x40112233
click; click
check "the next to 10%" has "$W/color" 0x1a112233
click; click
check "the next to 100%" has "$W/color" 0xff112233
click; click
check "and round again to 50%" has "$W/color" 0x80112233
click; click; click
check "a third click starts a new double click" has "$W/color" 0x40112233
check "the empty items catch clicks on either side" bash -c "grep -c 'click_script=\"\$PLUGIN_DIR/bar_opacity.sh\"' '$SB/config/sketchybarrc' | grep -qx 2"

echo "The theme's colors"
THEMER="$SB/../kadomo-theme-manager"
PALETTE="$WORK/colors.toml"
cat >"$PALETTE" <<'EOF'
background = "#112233"
foreground = "$(touch pwned)"
accent = "#445566; touch pwned"
EOF
awk -f "$THEMER/lib/palette.awk" "$PALETTE" >"$WORK/palette.tsv" 2>/dev/null
awk -f "$THEMER/lib/render.awk" "$WORK/palette.tsv" "$THEMER/themed/sketchybar-colors.sh.tpl" >"$WORK/colors.out" 2>/dev/null
check "renders ARGB" has "$WORK/colors.out" 'export BG="0xff112233"'
check "the bar's own color is see-through" has "$WORK/colors.out" 'export BG_TRANS="0xc0112233"'
check "a theme cannot put a command in a file the bar sources" lacks "$WORK/colors.out" "pwned"
(cd "$WORK" && bash -c "source '$WORK/colors.out'")
check "sourcing it runs nothing" gone "$WORK/pwned"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
((FAIL == 0))
