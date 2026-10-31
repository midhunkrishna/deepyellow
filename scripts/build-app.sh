#!/bin/sh
# Builds dist/DeepYellow.app: universal binary, Info.plist, icon, CLI script, signature.
# Environment:
#   VERSION        version to stamp (default: git describe, else 0.0.0-dev)
#   ARCHS          space-separated architectures (default: "arm64 x86_64")
#   SIGN_IDENTITY  codesign identity (default: "-" for ad-hoc)
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

version=$("$root/scripts/version.sh")
build_number=${version%%-*}
archs=${ARCHS:-"arm64 x86_64"}
identity=${SIGN_IDENTITY:--}
app="$root/dist/DeepYellow.app"

# One build per architecture, joined by lipo. Passing several --arch flags at once switches
# SwiftPM to its Xcode build system, which rejects these packages on GitHub's runners.
binaries=""
for a in $archs; do
    echo "==> swift build (release, $a)"
    swift build -c release --product DeepYellow --arch "$a"
    binaries="$binaries $(swift build -c release --product DeepYellow --arch "$a" --show-bin-path)/DeepYellow"
done

echo "==> assembling $app (version $version)"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/bin"
# shellcheck disable=SC2086
lipo -create $binaries -output "$app/Contents/MacOS/DeepYellow"
cp "$root/Resources/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
cp "$root/Resources/bin/deepyellow" "$app/Contents/Resources/bin/deepyellow"
chmod +x "$app/Contents/Resources/bin/deepyellow"
sed -e "s/@VERSION@/$version/" -e "s/@BUILD@/$build_number/" \
    "$root/Resources/Info.plist" > "$app/Contents/Info.plist"
printf 'APPL????' > "$app/Contents/PkgInfo"
plutil -lint "$app/Contents/Info.plist" >/dev/null

echo "==> signing (identity: $identity)"
if [ "$identity" = "-" ]; then
    codesign --force --deep --sign - "$app"
else
    codesign --force --deep --options runtime --timestamp --sign "$identity" "$app"
fi
codesign --verify --deep --strict "$app"
echo "built $app"
