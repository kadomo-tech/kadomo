#!/usr/bin/env bash
# Network indicator: an ethernet plug when a cable carries the traffic, the
# Wi-Fi fan otherwise. Click opens Wi-Fi settings.
source "$CONFIG_DIR/colors.sh"

# Find the Wi-Fi interface name dynamically (usually en0)
DEV=$(networksetup -listallhardwareports 2>/dev/null \
  | awk '/Hardware Port: Wi-Fi/ {getline; print $2; exit}')
DEV=${DEV:-en0}

# The active interfaces in service order, highest priority first. Skip VPN
# tunnels and bridges so a VPN doesn't hide the link underneath it.
PRIMARY=$(scutil --nwi 2>/dev/null \
  | awk -F': ' '/^Network interfaces:/ {print $2}' \
  | tr ' ' '\n' | grep -vE '^(utun|ipsec|ppp|bridge|lo)' | head -n1)

POWER=$(networksetup -getairportpower "$DEV" 2>/dev/null | awk '{print $NF}')

if [ -n "$PRIMARY" ] && [ "$PRIMARY" != "$DEV" ]; then
  ICON="󰈀"
  COLOR="$FG"
elif [ "$POWER" = "On" ]; then
  ICON="󰖩"
  COLOR="$FG"
else
  ICON="󰖪"
  COLOR="$COMMENT"
fi

sketchybar --set "$NAME" \
  icon="$ICON" \
  icon.color="$COLOR"
