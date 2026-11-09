#!/bin/sh
# Runs inside a lab VM: reads Slack the way a person catching up does, moving through channels and scrolling back.
# It only sends Option+Down (key code 125, next channel) and Page Up (key code 116). It never sends characters, Return
# or Command shortcuts, so it cannot type into the message box or post anything. Before every key it checks that the
# app is frontmost and stops if not, so keys never reach another app.
#
# usage: sh drive.sh [channels] [pages-per-channel]
# DRIVE_APP and DRIVE_BUNDLE pick another app; the lab uses them only to test this script against TextEdit.
set -eu

channels=${1:-40}
pages=${2:-8}
app=${DRIVE_APP:-/Applications/Slack.app}
bundle=${DRIVE_BUNDLE:-com.tinyspeck.slackmacgap}

# Prints the bundle id of the frontmost app.
frontmost() {
    osascript -e 'tell application "System Events" to get bundle identifier of first process whose frontmost is true'
}

# Sends one key code to the app, with optional modifiers such as "option down", after checking it is frontmost.
press() {
    front=$(frontmost)
    [ "$front" = "$bundle" ] || { echo "drive: $front is frontmost, not $bundle; stopping" >&2; exit 1; }
    if [ -n "${2:-}" ]; then
        osascript -e "tell application \"System Events\" to key code $1 using {$2}"
    else
        osascript -e "tell application \"System Events\" to key code $1"
    fi
}

i=0
while [ "$i" -lt "$channels" ]; do
    open "$app"
    sleep 1
    press 125 "option down"
    sleep 3
    j=0
    while [ "$j" -lt "$pages" ]; do
        press 116
        sleep 1
        j=$((j + 1))
    done
    i=$((i + 1))
done
echo "visited $channels channels, $pages pages each"
