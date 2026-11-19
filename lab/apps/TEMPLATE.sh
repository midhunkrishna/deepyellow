#!/bin/sh
# Template for an app's usage script. Copy it to lab/apps/<app>/drive.sh and fill in the three values below.
#
# Runs inside a lab VM: uses the app the way a person does, so it writes the caches and data a real session would.
# It only sends key codes for navigation (arrows, Page Up, Page Down). It never sends characters, Return or Command
# shortcuts, so it cannot type into a message box, post anything or fill in a form. Before every key it checks that
# the app is frontmost and stops if not, so keys never reach another app.
#
# Copy it into the VM with:  lab/lab.sh push <vm> lab/apps/<app>/drive.sh /opt/deepyellow/drive.sh
# Run it with:               lab/lab.sh ssh <vm> "sh /opt/deepyellow/drive.sh"
#
# usage: sh drive.sh [rounds] [pages-per-round]
set -eu

rounds=${1:-10}
pages=${2:-5}
# 1. The app's path in the VM, as installed by lab/guest/install-app.sh.
app=${DRIVE_APP:-/Applications/Example.app}
# 2. Its bundle id: `defaults read "$app/Contents/Info.plist" CFBundleIdentifier` inside the VM.
bundle=${DRIVE_BUNDLE:-com.example.app}

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

# 3. The loop: replace the key codes with whatever moves through this app's content (125 is Down, 121 is Page Down,
#    116 is Page Up). Keep the sleeps long enough for the app to load what it shows.
i=0
while [ "$i" -lt "$rounds" ]; do
    open "$app"
    sleep 1
    press 125
    sleep 3
    j=0
    while [ "$j" -lt "$pages" ]; do
        press 121
        sleep 1
        j=$((j + 1))
    done
    i=$((i + 1))
done
echo "ran $rounds rounds, $pages pages each"
