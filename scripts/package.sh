#!/bin/sh
# Packages dist/DeepYellow.app into dist/DeepYellow.dmg, dist/DeepYellow.zip and dist/SHA256SUMS.
# The disk image holds the app and a symlink to /Applications for drag-to-install.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
dist="$root/dist"
app="$dist/DeepYellow.app"
[ -d "$app" ] || { echo "package: $app not found; run scripts/build-app.sh first" >&2; exit 1; }

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT

echo "==> DeepYellow.dmg"
ditto "$app" "$stage/DeepYellow.app"
ln -s /Applications "$stage/Applications"
rm -f "$dist/DeepYellow.dmg"
hdiutil create -quiet -volname DeepYellow -srcfolder "$stage" -format UDZO -ov "$dist/DeepYellow.dmg"

echo "==> DeepYellow.zip"
rm -f "$dist/DeepYellow.zip"
ditto -c -k --keepParent "$app" "$dist/DeepYellow.zip"

echo "==> SHA256SUMS"
(cd "$dist" && shasum -a 256 DeepYellow.dmg DeepYellow.zip > SHA256SUMS && cat SHA256SUMS)
