#!/bin/zsh
# Run a command in a fresh Ghostty window and hold it open at the end. Launched
# from the bar the environment is launchd's, and a login zsh does not read
# .zshrc, so the tool paths are set here by hand. Usage:
#   open -na Ghostty --args -e tui.sh <cmd...>
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
print -P "%F{blue}▸%f $*"
"$@"
echo
read -k1 "?Press any key to close"
