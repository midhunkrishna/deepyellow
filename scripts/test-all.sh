#!/bin/sh
# Runs `swift test` for every package under Packages/, then for the root package, then the release script tests the rules doc check and the rules checker.
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
echo "==> rules doc"
python3 "$root/scripts/gen-rules-doc.py" --check || failed="$failed rules-doc"
echo "==> rules doc generator tests"
python3 "$root/scripts/test-gen-rules-doc.py" || failed="$failed rules-doc-tests"
echo "==> rules check"
python3 "$root/scripts/check-rules.py" || failed="$failed check-rules"
echo "==> rules checker tests"
python3 "$root/scripts/test-check-rules.py" || failed="$failed check-rules-tests"
if [ -n "$failed" ]; then
    echo "FAILED:$failed" >&2
    exit 1
fi
echo "all tests passed"
