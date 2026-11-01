# Shared by install.sh and uninstall.sh: where LinearMouse and its config are,
# the Moonlight profile Kadomo adds, and the record of what Kadomo did.

MOUSE_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# find_brew, app_path (KADOMO_APP_DIRS overrides where apps are looked for), STATE_DIR.
source "$MOUSE_HERE/../apps/apps.sh"

MOONLIGHT_ID="com.moonlight-stream.Moonlight"
LM_CASK="linearmouse"
LM_APP="LinearMouse.app"
LM_JS="$MOUSE_HERE/linearmouse.js"

# What Kadomo did, one file each, so uninstall.sh undoes exactly that.
RECORD_DIR="$STATE_DIR/moonlight-mouse"
SCHEME_RECORD="$RECORD_DIR/scheme.json"         # the profile as Kadomo last wrote it
CONFIG_RECORD="$RECORD_DIR/config-path"         # the linearmouse.json it is in
CREATED_RECORD="$RECORD_DIR/created-config"     # Kadomo created that file
BREW_RECORD="$RECORD_DIR/installed-linearmouse" # Kadomo installed LinearMouse with Homebrew
LOGIN_RECORD="$RECORD_DIR/login-item"           # an earlier Kadomo added a System Events login item

# The file LinearMouse reads: the Application Support one when it exists, as in
# LinearMouse itself, otherwise ~/.config/linearmouse/linearmouse.json.
lm_config_path() {
    local support="$HOME/Library/Application Support/linearmouse/linearmouse.json"
    if [[ -e "$support" || -L "$support" ]]; then printf '%s' "$support"
    else printf '%s' "$HOME/.config/linearmouse/linearmouse.json"; fi
}

# The config install.sh edited, or where LinearMouse reads it now.
recorded_config_path() {
    local path=""
    [[ -s "$CONFIG_RECORD" ]] && path="$(cat "$CONFIG_RECORD")"
    if [[ -n "$path" && ( -e "$path" || -L "$path" ) ]]; then printf '%s' "$path"; else lm_config_path; fi
}

lm_js() { osascript -l JavaScript "$LM_JS" "$@"; }
lm_running() { pgrep -qf "$LM_APP/Contents/MacOS/" 2>/dev/null; }

# Kadomo's profile, as LinearMouse itself would save it. Only a mouse, only
# while Moonlight is the frontmost app. A whole number for distance is "by
# lines": every wheel step is exactly that many lines, with no acceleration and
# no momentum. Acceleration 1 and speed 0 are LinearMouse's "no change", set so
# that a broader scheme of yours cannot add them back inside Moonlight.
moonlight_scheme() { # <reverse: true or false>
    cat <<EOF
{
  "if": {
    "app": "$MOONLIGHT_ID",
    "device": {
      "category": "mouse"
    }
  },
  "pointer": {
    "disableAcceleration": true
  },
  "scrolling": {
    "acceleration": 1,
    "distance": 3,
    "reverse": $1,
    "smoothed": {
      "enabled": false
    },
    "speed": 0
  }
}
EOF
}

# Whether macOS natural scrolling is on (its default) and whether Moonlight's
# own "Reverse mouse scrolling direction" option is: 1 or 0.
natural_scrolling() {
    case "$(defaults read -g com.apple.swipescrolldirection 2>/dev/null)" in
        0|false) echo 0 ;;
        *) echo 1 ;;
    esac
}
moonlight_reverses() {
    case "$(defaults read "$MOONLIGHT_ID" reversescroll 2>/dev/null)" in
        1|true) echo 1 ;;
        *) echo 0 ;;
    esac
}

# Opens LinearMouse at each login. LinearMouse's own Start at login can only
# be switched from inside LinearMouse, and a System Events login item needs
# Automation permission; a launch agent needs neither. It runs once at login
# and exits, and shows in System Settings › General › Login Items.
LAUNCH_AGENT_LABEL="com.kadomo.linearmouse"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/$LAUNCH_AGENT_LABEL.plist"
launch_agent() { # <app path>
    local app
    app="$(printf '%s' "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')"
    cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$LAUNCH_AGENT_LABEL</string>
	<key>ProgramArguments</key>
	<array>
		<string>/usr/bin/open</string>
		<string>-g</string>
		<string>$app</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>LimitLoadToSessionType</key>
	<string>Aqua</string>
</dict>
</plist>
EOF
}

# Waits up to 10 seconds (KADOMO_START_WAIT, for testing) for LinearMouse to be running.
wait_for_linearmouse() {
    local n
    for ((n=0; n<${KADOMO_START_WAIT:-10}*2; n++)); do
        lm_running && return 0
        sleep 0.5
    done
    return 1
}

# The login item an earlier Kadomo added through System Events; uninstall.sh
# still removes one it finds recorded.
remove_login_item() {
    osascript -e 'tell application "System Events" to delete (every login item whose name is "LinearMouse")' >/dev/null 2>&1
}

# A backup path next to $1 that does not exist yet, so no backup ever overwrites another.
backup_path() {
    local stamp path n=2
    stamp="$(date +%Y%m%d-%H%M%S)"
    path="$1.bak.$stamp"
    while [[ -e "$path" || -L "$path" ]]; do path="$1.bak.$stamp-$n"; n=$((n+1)); done
    printf '%s' "$path"
}

short_path() { case "$1" in "$HOME"/*) printf '~%s' "${1#"$HOME"}" ;; *) printf '%s' "$1" ;; esac; }
