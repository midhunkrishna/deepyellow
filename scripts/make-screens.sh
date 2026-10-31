#!/bin/sh
# Renders every app screenshot from the sample disk, offscreen, then converts them for the site.
#   docs/screens/app-*.png   1600x1000
#   web/images/app-*.webp    via cwebp
# Needs dist/DeepYellow.app (run `make app` first) and cwebp. Only the sample disk is used, so no real file names appear.
# Usage: scripts/make-screens.sh [name ...]   (default: every screenshot)
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
bin="$root/dist/DeepYellow.app/Contents/MacOS/DeepYellow"
[ -x "$bin" ] || { echo "missing $bin; run 'make app' first" >&2; exit 1; }
command -v cwebp >/dev/null 2>&1 || { echo "cwebp not found" >&2; exit 1; }

all="app-map app-map-safety app-map-files app-things app-spectrum app-field app-rings app-browse app-reclaim app-worklists app-review app-plan app-ledger app-palette app-welcome app-preview-video app-preview-image"
names=${*:-$all}

mkdir -p "$root/docs/screens" "$root/web/images"
scratch=$(mktemp -d "${TMPDIR:-/tmp}/dy-screens.XXXXXX")
trap 'rm -rf "$scratch"' EXIT

for name in $names; do
    out="$root/docs/screens/$name.png"
    echo "==> $name"
    DEEPYELLOW_HOME="$scratch/home-$name" "$bin" --demo --shot "$name" --out "$out"
    cwebp -quiet -q 88 "$out" -o "$root/web/images/$name.webp"
done
echo "wrote $(echo "$names" | wc -w | tr -d ' ') screenshots"
