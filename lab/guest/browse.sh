#!/bin/sh
# Runs inside a lab VM: browses public pages in a web browser the way a reader does. Each page opens in a new tab,
# is scrolled with Page Down (key code 121) and closed with Command-W (key code 13). It never types characters or
# presses Return, so it cannot fill in a form. Before every key it checks the browser is frontmost and stops if not.
# Copied to /opt/deepyellow by `lab/lab.sh install-dy`.
#
# usage: sh browse.sh <app> <bundle-id> <urls-file> [rounds] [pages-down]
set -eu

app=${1:?usage: browse.sh <app> <bundle-id> <urls-file> [rounds] [pages-down]}
bundle=${2:?bundle id}
urls=${3:?urls file}
rounds=${4:-1}
downs=${5:-5}

# Prints the bundle id of the frontmost app.
frontmost() {
    osascript -e 'tell application "System Events" to get bundle identifier of first process whose frontmost is true'
}

# Sends one key code to the browser, with optional modifiers such as "command down", after checking it is frontmost.
press() {
    front=$(frontmost)
    [ "$front" = "$bundle" ] || { echo "browse: $front is frontmost, not $bundle; stopping" >&2; exit 1; }
    if [ -n "${2:-}" ]; then
        osascript -e "tell application \"System Events\" to key code $1 using {$2}"
    else
        osascript -e "tell application \"System Events\" to key code $1"
    fi
}

r=0
pages=0
while [ "$r" -lt "$rounds" ]; do
    while IFS= read -r url; do
        case $url in ''|'#'*) continue ;; esac
        open -a "$app" "$url"
        sleep 6
        d=0
        while [ "$d" -lt "$downs" ]; do
            press 121
            sleep 1
            d=$((d + 1))
        done
        press 13 "command down"
        sleep 1
        pages=$((pages + 1))
    done < "$urls"
    r=$((r + 1))
done
echo "browsed $pages pages"
