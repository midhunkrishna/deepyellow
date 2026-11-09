#!/bin/sh
# Runs inside a lab VM: the remove-and-relaunch test. Quits the app, moves the given folders to the Trash, relaunches
# the app, screenshots it (to check it is still signed in) and records how much of each folder comes back, before and
# after a short run of the app's usage script. Copied to /opt/deepyellow by `lab/lab.sh install-dy`.
#
# usage: sh relaunch.sh <label> <folder>...
# Environment: APP (default /Applications/Slack.app), BUNDLE (default com.tinyspeck.slackmacgap), PROC (process name,
# default Slack), WAIT (seconds after relaunch, default 25), DRIVE (usage command run after the relaunch, default
# "sh /opt/deepyellow/drive.sh 5 3", the Slack script; empty skips).
set -eu

label=${1:?usage: relaunch.sh <label> <folder>...}; shift
[ $# -gt 0 ] || { echo "relaunch: give at least one folder" >&2; exit 1; }
app=${APP:-/Applications/Slack.app}
bundle=${BUNDLE:-com.tinyspeck.slackmacgap}
proc=${PROC:-Slack}
wait_s=${WAIT:-25}
drive=${DRIVE-sh /opt/deepyellow/drive.sh 5 3}
out=/tmp/relaunch-$label

# Prints the bundle id of the frontmost app.
frontmost() {
    osascript -e 'tell application "System Events" to get bundle identifier of first process whose frontmost is true'
}

# Brings the app to the front and clicks the Quit item in its app menu, then waits until its process is gone.
# The menu item is used instead of Command-Q because some apps (Chrome) ask you to hold Command-Q.
quit_app() {
    pgrep -x "$proc" > /dev/null || return 0
    open "$app"; sleep 2
    [ "$(frontmost)" = "$bundle" ] || { echo "relaunch: $bundle is not frontmost; not quitting" >&2; exit 1; }
    osascript -e 'tell application "System Events" to tell (first process whose frontmost is true) to click (first menu item of menu 1 of menu bar item 2 of menu bar 1 whose name starts with "Quit")' > /dev/null
    tries=0
    while pgrep -x "$proc" > /dev/null; do
        tries=$((tries + 1))
        [ "$tries" -lt 30 ] || { echo "relaunch: $proc did not quit" >&2; exit 1; }
        sleep 1
    done
}

# Prints a folder's allocated size in KB, or 0 when it does not exist.
size_kb() {
    if [ -e "$1" ]; then du -sk "$1" | cut -f1; else echo 0; fi
}

# Prints the sizes of all folders, one per line, in argument order.
sizes() {
    for f in "$@"; do size_kb "$f"; done
}

quit_app
before=$(sizes "$@")
for f in "$@"; do
    [ -e "$f" ] && mv "$f" "$HOME/.Trash/$label-$(basename "$f" | tr ' ' '_')-$$"
done
open "$app"; sleep "$wait_s"
screencapture -x "$out.png"
relaunched=$(sizes "$@")
used=$relaunched
if [ -n "$drive" ]; then
    sh -c "$drive" > /dev/null
    sleep 3
    used=$(sizes "$@")
fi

printf 'folder\tbefore_kb\tafter_relaunch_kb\tafter_use_kb\n'
i=1
for f in "$@"; do
    printf '%s\t%s\t%s\t%s\n' "$f" "$(echo "$before" | sed -n "${i}p")" "$(echo "$relaunched" | sed -n "${i}p")" \
        "$(echo "$used" | sed -n "${i}p")"
    i=$((i + 1))
done
echo "screenshot: $out.png"
