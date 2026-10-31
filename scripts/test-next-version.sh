#!/bin/sh
# Tests scripts/next-version.sh against throwaway repositories in a temp directory.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
script="$root/scripts/next-version.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failures=0
n=0

# git wrapper with a fixed identity and no signing, never reading user config.
gt() {
    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
        git -c user.name=test -c user.email=test@example.com -c commit.gpgsign=false -c tag.gpgsign=false \
        -C "$repo" "$@"
}

# Creates a fresh repo in $repo with one initial commit.
new_repo() {
    n=$((n + 1))
    repo="$tmp/r$n"
    mkdir -p "$repo"
    gt init -q
    commit "chore: init" src.txt
}

# commit MESSAGE [FILE]: makes a commit touching FILE (default src.txt).
commit() {
    f=${2:-src.txt}
    mkdir -p "$repo/$(dirname "$f")"
    echo "$n $RANDOM $(date +%s)" >> "$repo/$f"
    gt add -A
    gt commit -q -m "$1"
}

# expect NAME WANT: compares next-version output with WANT.
expect() {
    got=$(GIT_CONFIG_GLOBAL=/dev/null "$script" --repo "$repo")
    if [ "$got" = "$2" ]; then
        echo "ok   $1"
    else
        echo "FAIL $1: want $2, got $got"
        failures=$((failures + 1))
    fi
}

new_repo; commit "fix: x"
expect "no tag gives 0.1.0" 0.1.0

new_repo; gt tag v1.2.3; commit "fix: bug"
expect "fix is patch" 1.2.4

new_repo; gt tag v1.2.3; commit "feat: thing"; commit "fix: bug"
expect "feat is minor, resets patch" 1.3.0

new_repo; gt tag v1.2.3; commit "refactor: tidy"
expect "other types are patch" 1.2.4

new_repo; gt tag v1.2.3; commit "feat!: new format"
expect "bang is major" 2.0.0

new_repo; gt tag v1.2.3; commit "fix(scan)!: drop api"
expect "scoped bang is major" 2.0.0

new_repo; gt tag v1.2.3; commit "fix: x

BREAKING CHANGE: removed flag"
expect "BREAKING CHANGE footer is major" 2.0.0

new_repo; gt tag v1.2.3
expect "no commits since tag is none" none

new_repo; gt tag v1.2.3; commit "chore(release): 1.2.3"
expect "chore(release) is none" none

new_repo; gt tag v1.2.3; commit "docs: readme"
expect "docs commit is none" none

new_repo; gt tag v1.2.3; commit "fix: wording" docs/faq.md
expect "docs-only files are none" none

new_repo; gt tag v1.2.3; commit "docs: x"; commit "fix: real"
expect "docs plus fix is patch" 1.2.4

new_repo; gt tag v1.2.3; commit "feat: a"; gt tag v1.3.0; commit "fix: b"
expect "uses latest tag" 1.3.1

new_repo; gt tag v1.9.0; gt tag v1.10.0; commit "fix: b"
expect "tags sort numerically" 1.10.1

new_repo; gt tag v1.2.3; gt tag not-a-version; gt tag v2.0.0-rc1; commit "fix: b"
expect "ignores non-semver tags" 1.2.4

new_repo; gt tag v0.4.0; commit "feat: a"
expect "0.x feat is minor" 0.5.0

if [ "$failures" -ne 0 ]; then
    echo "$failures failure(s)" >&2
    exit 1
fi
echo "next-version: all passed"
