#!/bin/sh
# Prints the next semantic version (no leading v) from conventional commits since the latest
# vX.Y.Z tag reachable from the ref, or "none" when nothing warrants a release.
#
#   breaking (`type!:` subject or a BREAKING CHANGE footer)  -> major
#   feat                                                    -> minor
#   fix and any other type                                  -> patch
#   chore(release) commits, and docs-only commits           -> ignored
#
# No vX.Y.Z tag yet gives 0.1.0.
# Usage: next-version.sh [--repo DIR] [--ref REF]
set -eu

repo=.
ref=HEAD
while [ $# -gt 0 ]; do
    case $1 in
        --repo) repo=$2; shift 2 ;;
        --ref) ref=$2; shift 2 ;;
        -h|--help) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "next-version: unknown argument $1" >&2; exit 2 ;;
    esac
done

g() { git -C "$repo" "$@"; }

# Latest plain semver tag merged into the ref, or empty.
latest_tag() {
    g tag --merged "$ref" --list 'v[0-9]*' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -t. -k1.2,1n -k2,2n -k3,3n | tail -n 1 || true
}

# True when every file path on stdin is documentation (docs/, web/docs/, or a markdown file).
only_docs() {
    while IFS= read -r f; do
        case $f in
            docs/*|web/docs/*|*.md) ;;
            *) return 1 ;;
        esac
    done
    return 0
}

# Bump level of one commit: 0 ignore, 1 patch, 2 minor, 3 major.
commit_level() {
    subject=$(g log -1 --format=%s "$1")
    body=$(g log -1 --format=%b "$1")
    if printf '%s\n' "$subject" | grep -Eq '^[A-Za-z]+(\([^)]*\))?!:' ||
        printf '%s\n' "$body" | grep -Eq '^BREAKING[ -]CHANGE(:| )'; then
        echo 3; return
    fi
    if printf '%s\n' "$subject" | grep -Eq '^chore\(release\)'; then echo 0; return; fi
    if printf '%s\n' "$subject" | grep -Eq '^docs(\([^)]*\))?:'; then echo 0; return; fi
    files=$(g diff-tree --no-commit-id --name-only -r --root "$1")
    if [ -n "$files" ] && printf '%s\n' "$files" | only_docs; then echo 0; return; fi
    if printf '%s\n' "$subject" | grep -Eq '^feat(\([^)]*\))?:'; then echo 2; return; fi
    echo 1
}

tag=$(latest_tag)
if [ -z "$tag" ]; then
    echo "0.1.0"
    exit 0
fi

level=0
for c in $(g rev-list --no-merges "$tag..$ref"); do
    l=$(commit_level "$c")
    [ "$l" -gt "$level" ] && level=$l
done

version=${tag#v}
major=${version%%.*}
rest=${version#*.}
minor=${rest%%.*}
patch=${rest#*.}
case $level in
    0) echo "none" ;;
    1) echo "$major.$minor.$((patch + 1))" ;;
    2) echo "$major.$((minor + 1)).0" ;;
    3) echo "$((major + 1)).0.0" ;;
esac
