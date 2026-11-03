#!/bin/bash
# Checks the AeroSpace Kadomo component, the window manager switch and the
# JankyBorders theme colors in a throwaway HOME. brew, open, osascript, pgrep,
# pkill, launchctl, curl, tccutil and borders are stand-ins that only write
# files under the test folder, so nothing on this Mac starts, stops or installs.
#
# Usage: aerospace/tests/test.sh
# Runs on the Bash 3.2 that ships with macOS.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/kadomo-aerospace-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
MOCK="$WORK/mock"
RUN="$MOCK/run"
APPS="$WORK/Applications"
export HOME="$WORK/home" KADOMO_STATE_DIR="$WORK/app-support" XDG_STATE_HOME="$WORK/home/.local/state"
export KADOMO_AEROSPACE_APP="$APPS/AeroSpace Kadomo.app" KADOMO_WM_START_TICKS=4 KADOMO_WM_LOGIN_TICKS=4
export MOCK RUN APPS
mkdir -p "$HOME" "$RUN" "$APPS" "$MOCK/bin"
PASS=0
FAIL=0

check() {
    local what="$1"; shift
    if "$@"; then PASS=$((PASS + 1)); printf '  ✓ %s\n' "$what"
    else FAIL=$((FAIL + 1)); printf '  ✗ %s\n' "$what"; fi
}
running() { [[ -e "$RUN/$1" ]]; }
not() { ! "$@"; }
has() { grep -qF -- "$2" "$1" 2>/dev/null; }
lines() { grep -cF -- "$2" "$1" 2>/dev/null || true; }

# --- stand-ins ---------------------------------------------------------------------

mock() { printf '#!/bin/bash\n%s\n' "$2" >"$MOCK/bin/$1"; chmod 755 "$MOCK/bin/$1"; }
mock brew 'echo "brew $*" >>"$MOCK/brew.log"
case "$1" in install) [[ ! -e "$MOCK/brew-fails" ]] || exit 1; mock_borders=1 ;; esac
[[ -z "${mock_borders:-}" ]] || cp "$MOCK/borders.real" "$MOCK/bin/borders"
[[ "$1" != uninstall ]] || rm -f "$MOCK/bin/borders"'
# borders: a second call while one runs hands its settings over (logged).
cat >"$MOCK/borders.real" <<'EOF'
#!/bin/bash
if [[ -e "$RUN/borders" ]]; then echo "update $*" >>"$MOCK/borders.log"; exit 0; fi
echo "start $*" >>"$MOCK/borders.log"; touch "$RUN/borders"
EOF
chmod 755 "$MOCK/borders.real"
mock open 'case "$1" in
  *"AeroSpace Kadomo.app") [[ -e "$MOCK/aerospace-fails" ]] || touch "$RUN/aerospace" ;;
  *OmniWM.app) [[ -e "$MOCK/omniwm-fails" ]] || touch "$RUN/OmniWM" ;;
esac'
mock osascript 'case "$*" in
  *tech.kadomo.aerospace*) rm -f "$RUN/aerospace" ;;
  *bobko.aerospace*) rm -f "$RUN/regular-aerospace" ;;
  *com.barut.OmniWM*) rm -f "$RUN/OmniWM" ;;
esac'
mock pgrep 'args="$*"
case "$args" in
  *"AeroSpace Kadomo.app/Contents/MacOS/"*) [[ -e "$RUN/aerospace" ]] ;;
  *"/AeroSpace\.app/Contents/MacOS/"*) [[ -e "$RUN/regular-aerospace" ]] ;;
  *OmniWM*) [[ -e "$RUN/OmniWM" ]] ;;
  *borders*) [[ -e "$RUN/borders" ]] ;;
  *) exit 1 ;;
esac'
mock pkill 'case "$*" in
  *"AeroSpace Kadomo.app"*) rm -f "$RUN/aerospace" ;; *OmniWM*) rm -f "$RUN/OmniWM" ;;
  *borders*) rm -f "$RUN/borders" ;; *AeroSpace*) rm -f "$RUN/regular-aerospace" ;;
esac'
mock launchctl 'echo "launchctl $*" >>"$MOCK/launchctl.log"; exit 1'
mock tccutil 'echo "tccutil $*" >>"$MOCK/tccutil.log"'
mock curl 'out=""; while (($#)); do [[ "$1" == -o ]] && { out="$2"; shift; }; shift; done
[[ -e "$MOCK/curl-fails" ]] && exit 22; cp "$MOCK/release.zip" "$out"'
export PATH="$MOCK/bin:/usr/bin:/bin:/usr/sbin:/sbin"

# A fake AeroSpace Kadomo build: the app, with its command from the same build.
make_build() { # <version> <zip>
    local dir="$WORK/build-$1" app
    app="$dir/AeroSpace Kadomo.app"
    mkdir -p "$app/Contents/MacOS" "$app/Contents/Helpers"
    /usr/bin/plutil -create xml1 "$app/Contents/Info.plist"
    /usr/bin/plutil -insert CFBundleIdentifier -string tech.kadomo.aerospace "$app/Contents/Info.plist"
    /usr/bin/plutil -insert CFBundleShortVersionString -string "$1" "$app/Contents/Info.plist"
    printf '#!/bin/bash\necho "aerospace CLI client version: %s"\n' "$1" >"$app/Contents/Helpers/aerospace"
    printf '#!/bin/bash\n' >"$app/Contents/MacOS/AeroSpace"
    chmod 755 "$app/Contents/Helpers/aerospace" "$app/Contents/MacOS/AeroSpace"
    (cd "$dir" && ditto -c -k --keepParent "AeroSpace Kadomo.app" "$2")
}
make_build 0.21.3-kadomo.3 "$MOCK/release.zip"
SUM="$(shasum -a 256 "$MOCK/release.zip" | awk '{ print $1 }')"
printf 'version=0.21.3-kadomo.3\nurl=https://example.invalid/AeroSpace-Kadomo.zip\nsha256=%s\n' "$SUM" >"$MOCK/release.txt"
export KADOMO_AEROSPACE_RELEASE="$MOCK/release.txt"

APP="$KADOMO_AEROSPACE_APP"
CONFIG="$HOME/.config/aerospace/aerospace.toml"
RC="$HOME/.config/borders/bordersrc"
CHOICE="$XDG_STATE_HOME/kadomo/wm-choice"
AGENT="$HOME/Library/LaunchAgents/tech.kadomo.window-manager.plist"
MANIFEST="$KADOMO_STATE_DIR/aerospace-kadomo-installed.txt"
OMNI="$HOME/Applications/OmniWM.app"
install_aerospace() { "$REPO/aerospace/install.sh" "$@" >"$WORK/install.out" 2>&1; }

# --- a fresh install ---------------------------------------------------------------
echo "Fresh install"
mkdir -p "$HOME/.config/aerospace"
printf '# my own config\nstart-at-login = true\n' >"$CONFIG"
printf 'mine = true\n' >"$HOME/.aerospace.toml"
check "installs" install_aerospace
check "the app is in place" test -d "$APP"
check "the aerospace command links into the same build" test "$(readlink "$HOME/.local/bin/aerospace")" = "$APP/Contents/Helpers/aerospace"
check "Kadomo's config is installed" has "$CONFIG" "# Kadomo's AeroSpace config"
check "your config is set aside" has "$CONFIG.before-kadomo" "# my own config"
check "your ~/.aerospace.toml is set aside (AeroSpace refuses two configs)" test -f "$HOME/.aerospace.toml.before-kadomo" -a ! -e "$HOME/.aerospace.toml"
check "JankyBorders is installed with Homebrew" has "$MOCK/brew.log" "brew install felixkratz/formulae/borders"
check "and recorded as Kadomo's" has "$MANIFEST" "formula|felixkratz/formulae/borders"
check "Homebrew's ownership lookup sees it" bash -c "STATE_DIR='$KADOMO_STATE_DIR'; source '$REPO/homebrew/homebrew.sh' 2>/dev/null; hb_kadomo_packages | grep -qx felixkratz/formulae/borders"
check "bordersrc is installed" has "$RC" "# Kadomo's JankyBorders config"
check "the login agent starts kadomo-wm" has "$AGENT" "<string>login</string>"
check "AeroSpace is the window manager" test "$(cat "$CHOICE")" = aerospace
check "AeroSpace runs" running aerospace
check "borders runs" running borders
check "Kadomo Menu lists its keys" has "$HOME/.config/kadomo/menu/commands/aerospace-kadomo.toml" "OPT SHIFT + B"
check "the menu's Start goes through kadomo-wm" has "$HOME/.config/kadomo/menu/commands/aerospace-kadomo.toml" 'args = ["use", "aerospace"]'

echo "Installing again"
cp "$CONFIG" "$WORK/config.first"
check "installs again" install_aerospace
check "skips the download" has "$WORK/install.out" "already installed"
check "one login agent" test "$(ls "$HOME/Library/LaunchAgents" | wc -l | tr -d ' ')" = 1
check "nothing recorded twice" test "$(sort "$MANIFEST" | uniq -d | wc -l | tr -d ' ')" = 0
check "your set-aside config is not overwritten" has "$CONFIG.before-kadomo" "# my own config"
check "the config is unchanged" cmp -s "$CONFIG" "$WORK/config.first"
check "still AeroSpace" test "$(cat "$CHOICE")" = aerospace

# --- switching -----------------------------------------------------------------------
echo "OmniWM"
mkdir -p "$OMNI"
install -m 755 "$REPO/omniwm/bin/kadomo-omniwm" "$HOME/.local/bin/kadomo-omniwm"
check "switches to OmniWM" "$HOME/.local/bin/kadomo-wm" use omniwm
check "OmniWM runs" running OmniWM
check "AeroSpace is quit" not running aerospace
check "its borders are quit (no second border renderer)" not running borders
check "the choice is OmniWM" test "$(cat "$CHOICE")" = omniwm

touch "$MOCK/aerospace-fails"
check "a switch that cannot start AeroSpace fails" not "$HOME/.local/bin/kadomo-wm" use aerospace
check "OmniWM runs again" running OmniWM
check "the choice stays OmniWM" test "$(cat "$CHOICE")" = omniwm
rm -f "$MOCK/aerospace-fails"

echo "Installing AeroSpace while OmniWM runs"
check "installs" install_aerospace
check "OmniWM is quit" not running OmniWM
check "AeroSpace runs" running aerospace
check "OmniWM stays installed" test -d "$OMNI"

echo "Login"
rm -f "$RUN/aerospace"; touch "$RUN/OmniWM"
check "login runs" "$HOME/.local/bin/kadomo-wm" login
check "starts AeroSpace, the choice" running aerospace
check "and quits OmniWM, which its own setting started" not running OmniWM
touch "$RUN/regular-aerospace"
"$HOME/.local/bin/kadomo-aerospace" stop
"$HOME/.local/bin/kadomo-aerospace" start
check "a regular AeroSpace is quit before Kadomo's starts" not running regular-aerospace

# --- a failed download --------------------------------------------------------------
echo "Updates"
make_build 0.21.3-kadomo.4 "$MOCK/release.zip"
printf 'version=0.21.3-kadomo.4\nurl=https://example.invalid/x.zip\nsha256=%s\n' "0000" >"$MOCK/release.txt"
check "a wrong checksum fails" not install_aerospace
check "and leaves the installed build" test "$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$APP/Contents/Info.plist")" = 0.21.3-kadomo.3
check "which still runs" running aerospace
touch "$MOCK/curl-fails"
printf 'version=0.21.3-kadomo.4\nurl=https://example.invalid/x.zip\nsha256=%s\n' "$(shasum -a 256 "$MOCK/release.zip" | awk '{ print $1 }')" >"$MOCK/release.txt"
check "a failed download fails" not install_aerospace
check "and leaves the installed build" test "$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$APP/Contents/Info.plist")" = 0.21.3-kadomo.3
rm -f "$MOCK/curl-fails"
check "a good update installs" install_aerospace
check "the new build is in place" test "$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$APP/Contents/Info.plist")" = 0.21.3-kadomo.4
check "and runs" running aerospace

# --- the legacy remover ---------------------------------------------------------------
echo "What an older Kadomo left"
printf '#!/bin/bash\n# kadomo-workspace-layout\n' >"$HOME/.local/bin/kadomo-workspace-layout"
"$REPO/aerospace/remove-legacy.sh" >"$WORK/legacy.out" 2>&1
check "the older script goes" test ! -e "$HOME/.local/bin/kadomo-workspace-layout"
check "the renewed app stays" test -d "$APP"
check "its command link stays" test -L "$HOME/.local/bin/aerospace"
check "kadomo-aerospace stays" test -x "$HOME/.local/bin/kadomo-aerospace"
check "AeroSpace keeps running" running aerospace
check "borders keeps running" running borders
check "the window manager choice stays" test "$(cat "$CHOICE")" = aerospace

# --- theme colors --------------------------------------------------------------------
echo "Theme colors"
THEME="$HOME/.config/kadomo/current/theme"
mkdir -p "$THEME"
sed -i '' 's/width=6.0/width=9.5/' "$RC"
printf 'active_color=gradient(top_left=0xff8839ef,bottom_right=0xff1e66f5)\ninactive_color=0x80595959\n' >"$THEME/borders.conf"
: >"$MOCK/borders.log"
check "applies" "$HOME/.local/bin/kadomo-borders" theme
check "bordersrc gets the gradient" has "$RC" 'active_color="gradient(top_left=0xff8839ef,bottom_right=0xff1e66f5)"'
check "and the inactive color, alpha kept" has "$RC" 'inactive_color="0x80595959"'
check "your width stays" has "$RC" "width=9.5"
check "the running borders gets both colors" has "$MOCK/borders.log" "update active_color=gradient(top_left=0xff8839ef,bottom_right=0xff1e66f5) inactive_color=0x80595959"
check "no second borders starts" test "$(lines "$MOCK/borders.log" start)" = 0
printf 'active_color=$(rm -rf ~)\ninactive_color=0xff000000\n' >"$THEME/borders.conf"
check "a value that is not a color is refused" not "$HOME/.local/bin/kadomo-borders" theme 2>/dev/null
check "and bordersrc keeps the last good colors" has "$RC" 'inactive_color="0x80595959"'
for i in 1 2 3 4 5; do
    printf 'active_color=0xff00000%s\ninactive_color=0xff11111%s\n' "$i" "$i" >"$THEME/borders.conf"
    "$HOME/.local/bin/kadomo-borders" theme
done
check "rapid changes end on the last theme" has "$RC" 'active_color="0xff000005"'
rm -f "$RUN/borders"
mv "$MOCK/bin/borders" "$MOCK/borders.away"
check "without borders installed, theme still succeeds" "$HOME/.local/bin/kadomo-borders" theme
check "and start does nothing" "$HOME/.local/bin/kadomo-borders" start
mv "$MOCK/borders.away" "$MOCK/bin/borders"

echo "Rendering every bundled theme"
TM="$REPO/kadomo-theme-manager"
for dir in "$TM"/themes/*/; do
    name="$(basename "$dir")"
    awk -f "$TM/lib/palette.awk" "$dir/colors.toml" >"$WORK/palette.tsv" 2>/dev/null
    printf 'theme_name\t%s\n' "$name" >>"$WORK/palette.tsv"
    awk -f "$TM/lib/render.awk" "$WORK/palette.tsv" "$TM/themed/borders.conf.tpl" >"$WORK/borders-$name.conf" 2>"$WORK/render.err"
    check "$name: valid JankyBorders colors" bash -c "grep -Eq '^active_color=(0x[0-9a-f]{8}|gradient\\(top_(left|right)=0x[0-9a-f]{8},bottom_(right|left)=0x[0-9a-f]{8}\\))$' '$WORK/borders-$name.conf' && grep -Eq '^inactive_color=0x[0-9a-f]{8}$' '$WORK/borders-$name.conf' && test ! -s '$WORK/render.err'"
done
printf 'accent = "#123456"\nbackground = "#000000"\nforeground = "#ffffff"\n' >"$WORK/minimal.toml"
awk -f "$TM/lib/palette.awk" "$WORK/minimal.toml" >"$WORK/palette.tsv" 2>/dev/null
awk -f "$TM/lib/render.awk" "$WORK/palette.tsv" "$TM/themed/borders.conf.tpl" >"$WORK/minimal.conf" 2>/dev/null
check "a theme without border colors uses its accent" has "$WORK/minimal.conf" "active_color=0xff123456"
check "and color8 for the other windows" grep -Eq '^inactive_color=0xff[0-9a-f]{6}$' "$WORK/minimal.conf"

echo "theme.conf"
check "borders follows the theme by default" bash -c "export KADOMO_CONFIG_DIR='$WORK/tc'; source '$TM/lib/common.sh'; enabled_apps | grep -qw borders"
mkdir -p "$WORK/tc"; printf 'apps = ghostty borders\nborders = off\n' >"$WORK/tc/theme.conf"
check "borders = off keeps it out" bash -c "export KADOMO_CONFIG_DIR='$WORK/tc'; source '$TM/lib/common.sh'; ! enabled_apps | grep -qw borders"

# --- uninstall ---------------------------------------------------------------------
echo "Uninstall"
rm -rf "$OMNI" "$HOME/.local/bin/kadomo-omniwm"
check "a dry run changes nothing" bash -c "'$REPO/aerospace/uninstall.sh' --dry-run >/dev/null && test -d '$APP'"
check "uninstalls" "$REPO/aerospace/uninstall.sh" >"$WORK/uninstall.out" 2>&1
check "AeroSpace is quit" not running aerospace
check "the app is gone" test ! -e "$APP"
check "the command link is gone" test ! -e "$HOME/.local/bin/aerospace"
check "your config is back" has "$CONFIG" "# my own config"
check "your ~/.aerospace.toml is back" has "$HOME/.aerospace.toml" "mine = true"
check "JankyBorders is uninstalled" has "$MOCK/brew.log" "brew uninstall felixkratz/formulae/borders"
check "kadomo-wm and its agent are gone" test ! -e "$HOME/.local/bin/kadomo-wm" -a ! -e "$AGENT"
check "the choice is gone" test ! -e "$CHOICE"
check "the record is gone" test ! -e "$MANIFEST"
check "nothing left to remove" bash -c "'$REPO/aerospace/uninstall.sh' --dry-run | grep -q 'no aerospace installed'"

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
((FAIL == 0))
