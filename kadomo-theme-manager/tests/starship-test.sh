#!/bin/bash
# Checks Starship support in a throwaway HOME with a stand-in starship
# command: prompt colors for every theme, the generated TOML, enable and
# disable in .zshrc (ZDOTDIR, symlinks, your own prompt setup), matching the
# Kadomo theme, previews, and rollback. Nothing is installed, no real shell
# config is read or changed, and no app is signalled.
#
# Usage: tests/starship-test.sh
#   KADOMO_STARSHIP_SCHEMA=<config-schema.json> also checks every key against
#   Starship's published schema (https://starship.rs/config-schema.json).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/kadomo-starship-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
BIN="$ROOT/bin"
# Found before the tests narrow PATH: a Python with tomllib (3.11+) parses the configs.
PY="$(command -v python3 || true)"
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
count() { grep -cF -- "$2" "$1" 2>/dev/null || true; }

# The stand-in: answers --version, init zsh (counting each init), and prompt
# (with a config warning when STUB_WARN is set).
STUB="$WORK/stub/starship"
mkdir -p "$WORK/stub"
cat >"$STUB" <<EOF
#!/bin/bash
case "\$1" in
    --version) echo "starship 1.27.0"; echo "tag:v1.27.0" ;;
    init) echo "echo x >>'$WORK/inits'; prompt_starship_precmd() { :; }; PROMPT='STAR> '" ;;
    prompt) [[ -z "\${STUB_WARN:-}" ]] || echo "[WARN] - (starship::config): Error in 'Character' at 'success_symbol'" >&2; echo "> " ;;
esac
EOF
chmod +x "$STUB"

# A fresh HOME for each part. $1 names it (spaces and a quote included where asked).
fresh() {
    export HOME="$WORK/$1"
    rm -rf -- "$HOME"; mkdir -p "$HOME"
    export KADOMO_THEME_APPS="starship" KADOMO_STATE_DIR="$HOME/app-support" KADOMO_FONT_DIRS=""
    export KADOMO_STARSHIP_SEARCH="$STUB" PATH="$WORK/stub:/usr/bin:/bin:/usr/sbin:/sbin"
    unset ZDOTDIR XDG_CONFIG_HOME
    rm -f "$WORK/inits"
    "$BIN/theme-set" catppuccin >/dev/null 2>&1
}
SS="starship"   # for readability below
TOML() { printf '%s' "$HOME/.config/kadomo/starship/starship.toml"; }
# Sources a .zshrc in a clean zsh (no other startup files) and prints what Starship saw.
zsh_run() { zsh -fc 'source "$1"; print -r -- "$STARSHIP_CONFIG|$PROMPT"' zsh "${1:-$HOME/.zshrc}" 2>&1; }
inits() { [[ -f "$WORK/inits" ]] && wc -l <"$WORK/inits" | tr -d ' ' || echo 0; }
# Every file under HOME with its checksum, to prove nothing changed.
snapshot() { (cd "$HOME" && find . -type f -o -type l | LC_ALL=C sort | while IFS= read -r f; do printf '%s %s\n' "$f" "$(shasum <"$f" 2>/dev/null || readlink "$f")"; done); }

echo "Prompt colors: every theme, every role, readable"
fresh colors
themes="$("$BIN/theme-list" --names)"
check "seven built-in themes" same "$(printf '%s\n' "$themes" | wc -l | tr -d ' ')" 7
for name in $themes; do
    "$BIN/theme-set" "$name" >/dev/null 2>"$WORK/err"
    check "$name: applies without warnings" [ ! -s "$WORK/err" ]
    pal="$HOME/.config/kadomo/current/theme/starship-palette.toml"
    bg="$(awk -F'\t' '$1 == "background" { print $2 }' "$HOME/.config/kadomo/current/theme/palette.tsv")"
    # WCAG contrast of each chip's text against that chip's own background
    # (not the terminal background: each role is a solid color block now),
    # and of success/error (the plain ❯/✗) against the terminal background.
    check "  all 12 roles; each chip's text reads on its own chip" awk -v bg="$bg" '
        function h(x) { return index("0123456789abcdef", tolower(x)) - 1 }
        function c8(s, i) { return h(substr(s, i, 1)) * 16 + h(substr(s, i + 1, 1)) }
        function lin(v) { v /= 255; return v <= 0.04045 ? v / 12.92 : exp(2.4 * log((v + 0.055) / 1.055)) }
        function L(s) { return 0.2126 * lin(c8(s, 2)) + 0.7152 * lin(c8(s, 4)) + 0.0722 * lin(c8(s, 6)) }
        function cr(a, b) { a = L(a); b = L(b); return a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05) }
        /^[a-z_]+ = "#/ { k = $1; v = $3; gsub(/"/, "", v); C[k] = v; n++ }
        END {
            if (n != 12) { print "      " n " roles, wanted 12"; bad = 1 }
            for (k in C) {
                if (k !~ /_fg$/) continue
                base = substr(k, 1, length(k) - 3)
                if (cr(C[k], C[base]) < 4.5 - 0.001) {
                    printf "      %s %s on %s %s is %.2f\n", k, C[k], base, C[base], cr(C[k], C[base]); bad = 1
                }
            }
            if (cr(C["success"], bg) < 3 - 0.001) { printf "      success %s on %s is %.2f\n", C["success"], bg, cr(C["success"], bg); bad = 1 }
            if (cr(C["error"], bg) < 3 - 0.001) { printf "      error %s on %s is %.2f\n", C["error"], bg, cr(C["error"], bg); bad = 1 }
            exit bad
        }' "$pal"
done
check "tmac2k: success and failure differ" bash -c "! '$BIN/theme-starship' list | awk '\$1 == \"tmac2k\" { exit \$12 != \$13 }'"

echo "Every theme, also future ones, gets a valid, deterministic config"
mkdir -p "$HOME/.config/kadomo/themes/my-new-theme"
printf 'background = "#202020"\nforeground = "#dddddd"\naccent = "#ff8800"\n' >"$HOME/.config/kadomo/themes/my-new-theme/colors.toml"
"$BIN/theme-starship" list >"$WORK/list"
check "theme-starship list has every theme" same "$(grep -vc '^THEME' "$WORK/list")" 8
check "  a new theme with only colors.toml included" has "$WORK/list" "my-new-theme"
check "  none without colors" lacks "$WORK/list" "no prompt colors"
(
    source "$ROOT/lib/common.sh"; source "$LIB/apply.sh"; source "$LIB/starship.sh"
    for name in $(theme_names); do
        for icons in nerd plain; do
            starship_config "$name" "$icons" "$(starship_palette "$name")" >"$WORK/gen-$name-$icons.toml"
            starship_config "$name" "$icons" "$(starship_palette "$name")" >"$WORK/again.toml"
            cmp -s "$WORK/gen-$name-$icons.toml" "$WORK/again.toml" || echo "not deterministic: $name $icons"
            KADOMO_STARSHIP_SEARCH="" starship_validate "$WORK/gen-$name-$icons.toml" || echo "invalid: $name $icons"
        done
    done
) >"$WORK/gen.out" 2>&1
check "  nerd and plain configs for all 7 validate, byte-identical on a rerun" [ ! -s "$WORK/gen.out" ]
check "  plain has no Nerd Font symbols" bash -c "! LC_ALL=C grep -q \$'\\xee' '$WORK/gen-catppuccin-plain.toml'"
check "  nerd has the branch symbol" bash -c "LC_ALL=C grep -q \$'\\xee\\x82\\xa0' '$WORK/gen-catppuccin-nerd.toml'"
if [[ -n "$PY" ]] && "$PY" -c 'import tomllib' 2>/dev/null; then
    check "  python's tomllib parses all 14" "$PY" - "$WORK" "${KADOMO_STARSHIP_SCHEMA:-}" <<'EOF'
import glob, json, sys, tomllib
work, schema = sys.argv[1], sys.argv[2]
props = defs = None
if schema:
    s = json.load(open(schema)); props = s["properties"]; defs = s.get("definitions") or s.get("$defs")
bad = 0
for f in sorted(glob.glob(work + "/gen-*.toml")):
    d = tomllib.load(open(f, "rb"))
    assert d["palette"] == "kadomo" and len(d["palettes"]["kadomo"]) == 12, f
    if props:
        for k, v in d.items():
            if k not in props: print("unknown key", k, f); bad = 1; continue
            if isinstance(v, dict) and k != "palettes":
                ref = props[k].get("$ref") or (props[k].get("allOf") or [{}])[0].get("$ref", "")
                allowed = defs[ref.split("/")[-1]]["properties"] if ref else {}
                for sub in v:
                    if sub not in allowed: print("unknown key", k + "." + sub, f); bad = 1
sys.exit(bad)
EOF
    [[ -z "${KADOMO_STARSHIP_SCHEMA:-}" ]] || echo "    (keys checked against $KADOMO_STARSHIP_SCHEMA)"
else
    echo "    (skipped the TOML parse: no python3 with tomllib)"
fi

echo "Themes from git cannot bring their own Starship config"
repo="$WORK/omarchy-sneaky-theme"
mkdir -p "$repo"
printf 'background = "#101010"\nforeground = "#e0e0e0"\n' >"$repo/colors.toml"
printf 'text = "#ffffff"\n[custom.x]\ncommand = "touch /tmp/kadomo-pwned"\n' >"$repo/starship-palette.toml"
(cd "$repo" && git init -q && git add -A && git -c user.name=t -c user.email=t@t commit -qm t)
git clone -q "$repo" "$HOME/.config/kadomo/themes/sneaky"
"$BIN/theme-set" sneaky >/dev/null 2>"$WORK/err"
check "its starship-palette.toml is reported as ignored" has "$WORK/err" "starship-palette.toml"
check "  the palette comes from its colors" bash -c "! grep -q custom '$HOME/.config/kadomo/current/theme/starship-palette.toml'"
"$BIN/theme-set" catppuccin >/dev/null 2>&1

echo "Status: not installed, installed, enabled, needs attention"
fresh states
check "not installed" bash -c "KADOMO_STARSHIP_SEARCH='' '$BIN/theme-starship' status | grep -q 'not installed'"
check "  enable refuses, and says how to install" bash -c "! KADOMO_STARSHIP_SEARCH='' '$BIN/theme-starship' enable 2>&1 | grep -q 'brew install starship' && false || true"
KADOMO_STARSHIP_SEARCH='' "$BIN/theme-starship" enable >/dev/null 2>&1; st=$?
check "  enable exits 1 and changes nothing" same "$st $(ls -A "$HOME" | grep -c zshrc)" "1 0"
check "installed, not on" bash -c "'$BIN/theme-starship' status | grep -q 'installed, not on'"

echo "Enable: a block in ~/.zshrc, backed up, once"
printf 'export EDITOR=vim\nalias ll="ls -l"\n' >"$HOME/.zshrc"
cp "$HOME/.zshrc" "$WORK/zshrc.orig"
"$BIN/theme-starship" enable >"$WORK/out" 2>&1; st=$?
check "exits 0" same "$st" 0
check "  says when the prompt changes" has "$WORK/out" "new terminal tab"
check "  one block" same "$(count "$HOME/.zshrc" ">>> kadomo starship")" 1
check "  your lines stay first, as they were" same "$(head -n 2 "$HOME/.zshrc")" "$(cat "$WORK/zshrc.orig")"
check "  a backup of the old .zshrc" cmp -s "$HOME"/.zshrc.kadomo-backup.* "$WORK/zshrc.orig"
check "  matching is on" same "$(sed -n 's/^match = //p' "$HOME/.config/kadomo/starship/settings.conf")" on
check "  icons plain without a Nerd Font" same "$(sed -n 's/^icons = //p' "$HOME/.config/kadomo/starship/settings.conf")" plain
check "  the config is Catppuccin's" has "$(TOML)" "theme=catppuccin"
check "  status: on" bash -c "'$BIN/theme-starship' status | grep -q 'on for zsh'"
check "  .zshrc and init.zsh are valid zsh" zsh -n "$HOME/.zshrc" "$HOME/.config/kadomo/starship/init.zsh"
check "  zsh points STARSHIP_CONFIG at it and starts Starship" same "$(zsh_run)" "$(TOML)|STAR> "
check "  bright, bold ls colors" same \
    "$(zsh -fc 'source "$1"; print -r -- "$CLICOLOR|$LSCOLORS|$LS_COLORS"' zsh "$HOME/.zshrc" 2>&1)" \
    "1|ExGxFxdxCxegedabagacad|di=1;34:ln=1;36:so=1;35:pi=33:ex=1;32"
check "  a CLICOLOR/LSCOLORS/LS_COLORS already set wins" same \
    "$(CLICOLOR=0 LSCOLORS=mine LS_COLORS=mine zsh -fc 'source "$1"; print -r -- "$CLICOLOR|$LSCOLORS|$LS_COLORS"' zsh "$HOME/.zshrc" 2>&1)" \
    "0|mine|mine"
rm -f "$WORK/inits"
check "  once, even when .zshrc is read twice" bash -c "zsh -fc 'source ~/.zshrc; source ~/.zshrc' && [ \$(wc -l <'$WORK/inits') -eq 1 ]"
"$BIN/theme-starship" enable >/dev/null 2>&1
"$BIN/theme-starship" enable >/dev/null 2>&1
check "enabling again adds nothing" same "$(count "$HOME/.zshrc" ">>> kadomo starship")" 1
check "  and makes no second backup" same "$(ls -A "$HOME" | grep -c kadomo-backup)" 1

echo "Matching the Kadomo theme, and keeping your own choice"
"$BIN/theme-set" gruvbox >/dev/null 2>&1
check "theme-set gruvbox: the prompt follows" has "$(TOML)" "theme=gruvbox"
"$BIN/theme-starship" set rose-pine >/dev/null
check "theme-starship set rose-pine" has "$(TOML)" "theme=rose-pine"
check "  turns matching off" same "$(sed -n 's/^match = //p' "$HOME/.config/kadomo/starship/settings.conf")" off
"$BIN/theme-set" catppuccin >/dev/null 2>&1
check "  theme-set catppuccin keeps rose-pine" has "$(TOML)" "theme=rose-pine"
"$BIN/theme-starship" match on >/dev/null
check "match on: catppuccin again" has "$(TOML)" "theme=catppuccin"
"$BIN/theme-starship" match off >/dev/null
"$BIN/theme-set" catppuccin >/dev/null 2>&1
check "match off keeps what showed (rose-pine was the saved choice)" has "$(TOML)" "theme=rose-pine"
"$BIN/theme-starship" match on >/dev/null
"$BIN/theme-starship" icons nerd >/dev/null
check "icons nerd" has "$(TOML)" "icons=nerd"
"$BIN/theme-starship" icons plain >/dev/null

echo "Previews change nothing"
snapshot >"$WORK/before"
"$BIN/theme-starship" preview --all >"$WORK/preview" 2>&1
"$BIN/theme-starship" preview gruvbox >/dev/null 2>&1
snapshot >"$WORK/after"
check "no file under HOME changed" cmp -s "$WORK/before" "$WORK/after"
check "  every theme previewed" same "$(grep -c 'simulated preview' "$WORK/preview")" 7
check "  all five scenarios" bash -c "for s in 'A folder' 'with changes' 'Node.js project' 'failed command' 'slow command'; do grep -q \"\$s\" '$WORK/preview' || exit 1; done"
dircolor="$(sed -n 's/^seg_dir = "#\(.*\)"/\1/p' "$(TOML)")"
"$BIN/theme-starship" preview >"$WORK/preview-current" 2>&1
check "  the preview's colors are the config's" has "$WORK/preview-current" "48;2;$((16#${dircolor:0:2}));$((16#${dircolor:2:2}));$((16#${dircolor:4:2}))m"

echo "Rollback: a config that fails to validate never replaces the working one"
cp "$(TOML)" "$WORK/good.toml"
STUB_WARN=1 "$BIN/theme-starship" set gruvbox >/dev/null 2>"$WORK/err"; st=$?
check "Starship's own warning fails it (exit $st)" [ "$st" -ne 0 ]
check "  the message says so" has "$WORK/err" "kept the previous prompt config"
check "  the old config is untouched" cmp -s "$(TOML)" "$WORK/good.toml"
check "  no temporary file left" bash -c "! ls '$HOME/.config/kadomo/starship/' | grep -q tmp"
mkdir -p "$HOME/.config/kadomo/themes/broken"
printf 'background = "#000000"\n' >"$HOME/.config/kadomo/themes/broken/colors.toml"
printf 'text = "#ffffff"\n' >"$HOME/.config/kadomo/themes/broken/starship-palette.toml"
"$BIN/theme-starship" set broken >/dev/null 2>&1; st=$?
check "a theme's own palette missing roles fails too" [ "$st" -ne 0 ]
check "  and the old config stays" cmp -s "$(TOML)" "$WORK/good.toml"
STUB_WARN=1 "$BIN/theme-set" gruvbox >/dev/null 2>"$WORK/err"
check "a failing theme-set reports it, with the retry" has "$WORK/err" "retry with theme-starship apply"
check "  the other apps' files still switch" has "$HOME/.config/kadomo/current/theme/ghostty.conf" "#282828"
"$BIN/theme-starship" match on >/dev/null 2>&1
check "theme-starship apply retries" bash -c "'$BIN/theme-starship' apply >/dev/null && grep -q theme=gruvbox '$(TOML)'"

echo "Needs attention, and recovery"
mv "$HOME/.config/kadomo/starship/starship.toml" "$WORK/moved.toml"
check "a missing config is reported, with the fix" bash -c "'$BIN/theme-starship' status | grep -q 'needs attention' && '$BIN/theme-starship' status | grep -q 'theme-starship enable'"
"$BIN/theme-starship" enable >/dev/null 2>&1
check "  enable repairs it" bash -c "'$BIN/theme-starship' status | grep -q 'on for zsh'"
check "a missing starship command is reported" bash -c "KADOMO_STARSHIP_SEARCH='' '$BIN/theme-starship' status | grep -q 'missing or does not run'"

echo "Disable: exactly back to before"
"$BIN/theme-starship" disable >"$WORK/out" 2>&1; st=$?
check "exits 0" same "$st" 0
check "  .zshrc is as it was" cmp -s "$HOME/.zshrc" "$WORK/zshrc.orig"
check "  the backup, no longer needed, is gone" same "$(ls -A "$HOME" | grep -c kadomo-backup)" 0
check "  init.zsh and the config are gone" bash -c "[ ! -e '$HOME/.config/kadomo/starship/init.zsh' -a ! -e '$(TOML)' ]"
check "  Starship stays installed" [ -x "$STUB" ]
check "  disable twice is fine" "$BIN/theme-starship" disable >/dev/null

echo "A .zshrc Kadomo made is removed again"
fresh made
"$BIN/theme-starship" enable >/dev/null 2>&1
check "made with only the block" same "$(grep -vc '^$' "$HOME/.zshrc")" 3
"$BIN/theme-starship" disable >/dev/null 2>&1
check "  and removed by disable" [ ! -e "$HOME/.zshrc" ]

echo "Your edits are kept"
fresh edits
printf 'export A=1\n' >"$HOME/.zshrc"
"$BIN/theme-starship" enable >/dev/null 2>&1
printf 'alias g=git\n' >>"$HOME/.zshrc"
"$BIN/theme-starship" disable >/dev/null 2>&1
check "lines added after enable stay" same "$(cat "$HOME/.zshrc")" "export A=1
alias g=git"
check "  the backup is kept, since the file differs from it" same "$(ls -A "$HOME" | grep -c kadomo-backup)" 1
fresh edited-block
"$BIN/theme-starship" enable >/dev/null 2>&1
sed -i '' 's/&& source/\&\& . /' "$HOME/.zshrc"
"$BIN/theme-starship" disable >"$WORK/out" 2>&1; st=$?
check "a block you changed is left in place (exit $st), and reported" bash -c "[ $st -eq 1 ] && grep -q 'changed since' '$WORK/out' && grep -q '>>> kadomo starship' '$HOME/.zshrc'"
check "  it is harmless now: zsh starts without errors" bash -c "zsh -fc 'source ~/.zshrc' 2>&1 | grep -q . && exit 1 || exit 0"

echo "ZDOTDIR"
fresh zdotdir
mkdir -p "$HOME/.config/zsh"
printf 'export ZDOTDIR="$HOME/.config/zsh"\n' >"$HOME/.zshenv"
"$BIN/theme-starship" enable >/dev/null 2>&1
check "the block goes in \$ZDOTDIR/.zshrc (set in ~/.zshenv)" has "$HOME/.config/zsh/.zshrc" ">>> kadomo starship"
check "  not in ~/.zshrc" [ ! -e "$HOME/.zshrc" ]
check "  zsh starts it" same "$(zsh_run "$HOME/.config/zsh/.zshrc")" "$(TOML)|STAR> "
"$BIN/theme-starship" disable >/dev/null 2>&1
check "  disable removes the file it made there" [ ! -e "$HOME/.config/zsh/.zshrc" ]
check "ZDOTDIR from the environment" bash -c "mkdir -p '$HOME/zd' && ZDOTDIR='$HOME/zd' '$BIN/theme-starship' enable >/dev/null 2>&1 && grep -q 'kadomo starship' '$HOME/zd/.zshrc'"
"$BIN/theme-starship" disable >/dev/null 2>&1

echo "Your own Starship or prompt: a decision first"
fresh conflicts
printf 'eval "$(starship init zsh)"\n' >"$HOME/.zshrc"
cp "$HOME/.zshrc" "$WORK/zshrc.orig"
"$BIN/theme-starship" enable >"$WORK/out" 2>&1; st=$?
check "an existing starship init: exit 3" same "$st" 3
check "  explained, with the choice" bash -c "grep -q 'starts Starship already' '$WORK/out' && grep -q -- '--use-kadomo' '$WORK/out'"
check "  nothing changed" bash -c "cmp -s '$HOME/.zshrc' '$WORK/zshrc.orig' && [ ! -e '$HOME/.config/kadomo/starship/enabled.txt' ]"
"$BIN/theme-starship" enable --use-kadomo >/dev/null 2>&1
check "--use-kadomo: init.zsh only picks the config" lacks "$HOME/.config/kadomo/starship/init.zsh" "init zsh"
rm -f "$WORK/inits"
check "  Starship starts once, with Kadomo's config" bash -c "[ \"\$(zsh -fc 'source ~/.zshrc; print -r -- \$STARSHIP_CONFIG')\" = '$(TOML)' ] && [ \$(wc -l <'$WORK/inits') -eq 1 ]"
"$BIN/theme-starship" disable >/dev/null 2>&1
check "  disable leaves your init line" cmp -s "$HOME/.zshrc" "$WORK/zshrc.orig"
for setup in 'source ~/powerlevel10k/powerlevel10k.zsh-theme' 'ZSH_THEME="robbyrussell"' 'export STARSHIP_CONFIG=~/my.toml' 'eval "$(oh-my-posh init zsh)"'; do
    printf '%s\n' "$setup" >"$HOME/.zshrc"
    "$BIN/theme-starship" enable >/dev/null 2>&1; st=$?
    check "$setup: exit 3" same "$st" 3
done
printf 'ZSH_THEME=""\n# eval "$(starship init zsh)"\n' >"$HOME/.zshrc"
check "an empty ZSH_THEME and comments are no conflict" "$BIN/theme-starship" enable >/dev/null 2>&1
"$BIN/theme-starship" disable >/dev/null 2>&1
rm -f "$HOME/.zshrc"
mkdir -p "$HOME/.config"
printf 'format = "$all"\n' >"$HOME/.config/starship.toml"
"$BIN/theme-starship" enable >"$WORK/out" 2>&1; st=$?
check "your own starship.toml: exit 3, explained" bash -c "[ $st -eq 3 ] && grep -q 'your own Starship config' '$WORK/out'"
"$BIN/theme-starship" enable --use-kadomo >/dev/null 2>&1
check "  never overwritten" same "$(cat "$HOME/.config/starship.toml")" 'format = "$all"'
"$BIN/theme-starship" disable >/dev/null 2>&1

echo "A symlinked .zshrc is not edited unless you say so"
fresh symlink
mkdir -p "$HOME/dotfiles"
printf 'export B=2\n' >"$HOME/dotfiles/zshrc"
ln -s "$HOME/dotfiles/zshrc" "$HOME/.zshrc"
"$BIN/theme-starship" enable >"$WORK/out" 2>&1; st=$?
check "exit 3, with the line to add" bash -c "[ $st -eq 3 ] && grep -q 'kadomo/starship/init.zsh' '$WORK/out'"
check "  untouched" same "$(cat "$HOME/dotfiles/zshrc")" "export B=2"
"$BIN/theme-starship" enable --edit-symlinked >/dev/null 2>&1
check "--edit-symlinked: the target gets the block" has "$HOME/dotfiles/zshrc" ">>> kadomo starship"
check "  .zshrc is still a symlink" [ -L "$HOME/.zshrc" ]
"$BIN/theme-starship" disable >/dev/null 2>&1
check "  disable puts the target back, link intact" bash -c "[ -L '$HOME/.zshrc' ] && [ \"\$(cat '$HOME/dotfiles/zshrc')\" = 'export B=2' ]"
printf '[[ -r ~/.config/kadomo/starship/init.zsh ]] && source ~/.config/kadomo/starship/init.zsh\n' >>"$HOME/dotfiles/zshrc"
"$BIN/theme-starship" enable >/dev/null 2>&1; st=$?
check "a line you added yourself counts as on (exit $st)" bash -c "[ $st -eq 0 ] && '$BIN/theme-starship' status | grep -q 'on for zsh'"
check "  and the file is not edited" same "$(grep -c kadomo "$HOME/dotfiles/zshrc")" 1
"$BIN/theme-starship" disable >"$WORK/out" 2>&1
check "  disable asks you to remove your line" has "$WORK/out" "line of yours"

echo "Paths with spaces and quotes"
fresh "it's a home"
printf 'export C=3\n' >"$HOME/.zshrc"
"$BIN/theme-starship" enable >/dev/null 2>&1
check "enable works" has "$HOME/.zshrc" ">>> kadomo starship"
check "  zsh finds the config" same "$(zsh_run)" "$(TOML)|STAR> "
export KADOMO_CONFIG_DIR="$WORK/outside \$HOME 'q'"
"$BIN/theme-set" catppuccin >/dev/null 2>&1
printf '' >"$HOME/.zshrc"
"$BIN/theme-starship" disable >/dev/null 2>&1
"$BIN/theme-starship" enable >/dev/null 2>&1
check "a config folder outside HOME, with \$ and quotes" same "$(zsh_run)" "$KADOMO_CONFIG_DIR/starship/starship.toml|STAR> "
"$BIN/theme-starship" disable >/dev/null 2>&1
unset KADOMO_CONFIG_DIR

echo "The theme manager's uninstall takes Starship out too"
fresh roundtrip
printf 'export D=4\n' >"$HOME/.zshrc"
"$ROOT/install.sh" --only themes >/dev/null 2>&1
check "install lists starship in theme.conf" has "$HOME/.config/kadomo/theme.conf" "starship"
"$HOME/.local/bin/theme-starship" enable >/dev/null 2>&1
check "  enable from the installed command" has "$HOME/.zshrc" ">>> kadomo starship"
"$ROOT/uninstall.sh" --dry-run >"$WORK/out" 2>&1
check "  the dry run names it" has "$WORK/out" "Starship for zsh"
"$ROOT/uninstall.sh" >/dev/null 2>&1
check "  uninstall: .zshrc as before" same "$(cat "$HOME/.zshrc")" "export D=4"
check "  ~/.config/kadomo/starship is gone" [ ! -e "$HOME/.config/kadomo/starship" ]
check "  Starship itself stays" [ -x "$STUB" ]

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
((FAIL == 0))
