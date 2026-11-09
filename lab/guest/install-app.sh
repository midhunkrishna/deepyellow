#!/bin/sh
# Runs inside a lab VM: downloads an app and installs it in /Applications, from a disk image, a zip or an installer
# package. The download and the mounted disk image stay in /opt/deepyellow, outside the measured folders.
# Copied to /opt/deepyellow by `lab/lab.sh install-dy`.
#
# usage: sh install-app.sh <url> <Name.app>
set -eu

url=${1:?usage: install-app.sh <url> <Name.app>}
name=${2:?app name, e.g. "Google Chrome.app"}
dl=/opt/deepyellow/downloads
mnt=/opt/deepyellow/mnt
file="$dl/$(basename "$name" .app).download"

# Copies the app out of a disk image.
from_dmg() {
    mkdir -p "$mnt"
    yes | hdiutil attach -nobrowse -readonly -mountpoint "$mnt" "$file" > /dev/null
    cp -R "$mnt/$name" /Applications/
    hdiutil detach "$mnt" > /dev/null
}

mkdir -p "$dl"
curl -fsSL -o "$file" "$url"
case $(head -c 4 "$file") in
    PK*) ditto -x -k "$file" /Applications/ ;;
    'xar!') mv "$file" "$file.pkg" && sudo installer -pkg "$file.pkg" -target / | tail -1 ;;  # installer needs .pkg
    *) from_dmg ;;
esac
[ -d "/Applications/$name" ] || { echo "install-app: /Applications/$name not found after install" >&2; exit 1; }
echo "$name $(defaults read "/Applications/$name/Contents/Info.plist" CFBundleShortVersionString) installed"
