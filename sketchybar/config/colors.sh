#!/usr/bin/env bash
# Every plugin sources this. It sets the PATH (the bar runs under launchd, whose
# PATH has neither Homebrew nor ~/.local/bin) and the colors: the current Kadomo
# theme's, which theme-set renders from kadomo-theme-manager's
# themed/sketchybar-colors.sh.tpl, else Tokyo Night when there is no theme.
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

export BG="0xff1a1b26"
export BG_TRANS="0xc01a1b26"
export FG="0xffc0caf5"
export SURFACE="0xff33467c"
export OVERLAY="0xff565f89"
export COMMENT="0xff565f89"
export ACCENT="0xff7aa2f7"
export RED="0xfff7768e"
export GREEN="0xff9ece6a"
export YELLOW="0xffe0af68"
export BLUE="0xff7aa2f7"
export MAGENTA="0xffbb9af7"
export CYAN="0xff7dcfff"
export ORANGE="0xffff9e64"

THEME_COLORS="$HOME/.config/kadomo/current/theme/sketchybar-colors.sh"
[ -f "$THEME_COLORS" ] && source "$THEME_COLORS"
