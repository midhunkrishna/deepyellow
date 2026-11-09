#!/bin/sh
# Runs inside a lab VM: downloads the current Slack for Mac and copies it to /Applications.
# The download and the mounted disk image stay in /opt/deepyellow, outside the measured folders.
set -eu

dl=/opt/deepyellow/downloads
mnt=/opt/deepyellow/mnt
mkdir -p "$dl" "$mnt"
curl -fsSL -o "$dl/Slack.dmg" "https://slack.com/ssb/download-osx-universal"
hdiutil attach -nobrowse -readonly -mountpoint "$mnt" "$dl/Slack.dmg" > /dev/null
cp -R "$mnt/Slack.app" /Applications/
hdiutil detach "$mnt" > /dev/null
echo "Slack $(defaults read /Applications/Slack.app/Contents/Info.plist CFBundleShortVersionString) installed"
