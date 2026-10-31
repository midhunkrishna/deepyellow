#!/bin/sh
# Runs `swift test` for every package under Packages/, then for the root package, then the release script tests.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
failed=""
for pkg in "$root"/Packages/*/; do
    [ -f "$pkg/Package.swift" ] || continue
    name=$(basename "$pkg")
    echo "==> $name"
    swift test --package-path "$pkg" || failed="$failed $name"
done
echo "==> DeepYellow (root package)"
(cd "$root" && swift test) || failed="$failed DeepYellow"
echo "==> release scripts"
"$root/scripts/test-next-version.sh" || failed="$failed next-version"
if [ -n "$failed" ]; then
    echo "FAILED:$failed" >&2
    exit 1
fi
echo "all tests passed"
