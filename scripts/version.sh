#!/bin/sh
# Prints the version to stamp into a build: $VERSION, else `git describe` on the latest
# vX.Y.Z tag (leading v removed), else 0.0.0-dev.
set -eu

if [ -n "${VERSION:-}" ]; then
    printf '%s\n' "${VERSION#v}"
    exit 0
fi
root=$(cd "$(dirname "$0")/.." && pwd)
if described=$(git -C "$root" describe --tags --match 'v[0-9]*' 2>/dev/null); then
    printf '%s\n' "${described#v}"
else
    echo "0.0.0-dev"
fi
