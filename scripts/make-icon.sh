#!/bin/sh
# Regenerates Resources/AppIcon.icns, web/images/icon.png and web/favicon.png
# from scripts/make-icon.swift. The outputs are committed; run this only when the icon changes.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

swift "$root/scripts/make-icon.swift" "$tmp"
mkdir -p "$root/Resources" "$root/web/images"
iconutil -c icns -o "$root/Resources/AppIcon.icns" "$tmp/AppIcon.iconset"
cp "$tmp/web-icon.png" "$root/web/images/icon.png"
cp "$tmp/web-favicon.png" "$root/web/favicon.png"
echo "wrote Resources/AppIcon.icns, web/images/icon.png, web/favicon.png"
