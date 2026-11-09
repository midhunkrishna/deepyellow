#!/bin/sh
# Runs inside a lab VM: writes one CSV row per file and folder under the folders apps write to, using DeepYellow's
# read-only SQL command. Copied to /opt/deepyellow by `lab/lab.sh install-dy`.
#
# usage: sh snapshot.sh <out.csv>
set -eu

out=${1:?usage: snapshot.sh <out.csv>}
dy=/opt/deepyellow/DeepYellow.app/Contents/MacOS/DeepYellow
query="SELECT path, is_dir, size, logical, file_count, modified, safety FROM nodes"
# The per-user cache and temp folders macOS keeps under /private/var/folders (the parent of C, T and 0).
user_var=$(cd "$(getconf DARWIN_USER_DIR)/.." && pwd -P)

export DEEPYELLOW_HOME=/opt/deepyellow/home
: > "$out"
first=1
roots="$HOME /Library /Applications $user_var"
[ -d /opt/homebrew ] && roots="$roots /opt/homebrew"   # Homebrew's prefix on Apple silicon
for dir in $roots; do
    if [ $first -eq 1 ]; then
        "$dy" --cli sql "$dir" "$query" --csv >> "$out"
        first=0
    else
        "$dy" --cli sql "$dir" "$query" --csv | tail -n +2 >> "$out"
    fi
done
echo "$(($(wc -l < "$out") - 1)) rows in $out"
