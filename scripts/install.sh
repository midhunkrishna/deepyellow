#!/bin/sh
# DeepYellow installer.
#   curl -fsSL https://raw.githubusercontent.com/midhunkrishna/deepyellow/master/scripts/install.sh | sh
#
# Downloads the latest DeepYellow.zip, verifies it against SHA256SUMS, installs DeepYellow.app
# and links the command line tool. Never uses sudo and never deletes: an earlier install is moved
# aside to DeepYellow.app.previous-<timestamp>.
#
# Options:
#   --dir DIR        where DeepYellow.app goes (default ~/Applications)
#   --bin DIR        where the `deepyellow` link goes (default ~/.local/bin)
#   --from-file ZIP  install from a local DeepYellow.zip instead of downloading
#   --dry-run        print what would happen and change nothing
#   -h, --help       show this help
set -eu

BASE_URL="https://github.com/midhunkrishna/deepyellow/releases/latest/download"
BUNDLE_ID="com.midhunkrishna.deepyellow"

dir=""
bin=""
from_file=""
dry_run=0
tmp=""

# Prints a message to stderr and exits with status 1.
die() { echo "install: $*" >&2; exit 1; }

# Prints one line of what was done (or would be done under --dry-run).
say() { if [ "$dry_run" -eq 1 ]; then echo "would: $*"; else echo "$*"; fi; }

# Removes the scratch directory this script created.
cleanup() { if [ -n "$tmp" ]; then rm -rf "$tmp"; fi; }

# Prints the options.
usage() {
    cat <<'USAGE'
usage: install.sh [--dir DIR] [--bin DIR] [--from-file ZIP] [--dry-run]
  --dir DIR        where DeepYellow.app goes (default ~/Applications)
  --bin DIR        where the `deepyellow` link goes (default ~/.local/bin)
  --from-file ZIP  install from a local DeepYellow.zip instead of downloading
  --dry-run        print what would happen and change nothing
USAGE
}

# Parses command line options into the globals above.
parse_args() {
    while [ $# -gt 0 ]; do
        case $1 in
            --dir) [ $# -ge 2 ] || die "--dir needs a value"; dir=$2; shift 2 ;;
            --bin) [ $# -ge 2 ] || die "--bin needs a value"; bin=$2; shift 2 ;;
            --from-file) [ $# -ge 2 ] || die "--from-file needs a value"; from_file=$2; shift 2 ;;
            --dry-run) dry_run=1; shift ;;
            -h|--help) usage; exit 0 ;;
            *) die "unknown option $1 (try --help)" ;;
        esac
    done
    if [ -z "$dir" ] || [ -z "$bin" ]; then
        [ -n "${HOME:-}" ] || die "HOME is not set; pass --dir and --bin"
        [ -n "$dir" ] || dir="$HOME/Applications"
        [ -n "$bin" ] || bin="$HOME/.local/bin"
    fi
    case $dir in /*) ;; *) die "--dir must be an absolute path" ;; esac
    case $bin in /*) ;; *) die "--bin must be an absolute path" ;; esac
}

# Prints the CFBundleIdentifier of the app bundle at $1, or nothing.
bundle_id() {
    plist="$1/Contents/Info.plist"
    [ -f "$plist" ] || return 0
    /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist" 2>/dev/null || true
}

# Succeeds when $1 is a DeepYellow app bundle.
is_deepyellow() { [ "$(bundle_id "$1")" = "$BUNDLE_ID" ]; }

# Prints the SHA-256 of file $1.
sha256_of() { shasum -a 256 "$1" | awk '{print $1}'; }

# Checks file $1 against the DeepYellow.zip line of checksum file $2; dies on mismatch.
verify_checksum() {
    want=$(awk '$2 == "DeepYellow.zip" || $2 == "*DeepYellow.zip" {print $1}' "$2")
    [ -n "$want" ] || die "no DeepYellow.zip entry in $2"
    have=$(sha256_of "$1")
    [ "$want" = "$have" ] || die "checksum mismatch for $1 (expected $want, got $have)"
    echo "checksum ok: $have"
}

# Downloads the latest zip and SHA256SUMS into $tmp and verifies them; sets $zip.
fetch_release() {
    say "download $BASE_URL/DeepYellow.zip and SHA256SUMS"
    [ "$dry_run" -eq 1 ] && return 0
    curl -fsSL -o "$tmp/DeepYellow.zip" "$BASE_URL/DeepYellow.zip" || die "download failed"
    curl -fsSL -o "$tmp/SHA256SUMS" "$BASE_URL/SHA256SUMS" || die "checksum download failed"
    verify_checksum "$tmp/DeepYellow.zip" "$tmp/SHA256SUMS"
    zip="$tmp/DeepYellow.zip"
}

# Uses the local zip given by --from-file; verifies it when a SHA256SUMS file sits beside it.
use_local_file() {
    [ -f "$from_file" ] || die "$from_file not found"
    zip=$from_file
    sums="$(dirname "$from_file")/SHA256SUMS"
    if [ "$(basename "$from_file")" = "DeepYellow.zip" ] && [ -f "$sums" ]; then
        verify_checksum "$from_file" "$sums"
    else
        echo "checksum not verified (no SHA256SUMS beside $from_file)"
    fi
}

# Dies when $1 exists and is not a DeepYellow app, so unrelated files are never replaced.
check_destination() {
    if [ -e "$1" ] || [ -L "$1" ]; then
        is_deepyellow "$1" || die "$1 exists and is not DeepYellow; leaving it alone"
    fi
}

# Moves an existing install at $1 aside to a timestamped name.
move_aside() {
    [ -e "$1" ] || return 0
    aside="$1.previous-$(date +%Y%m%d-%H%M%S)"
    say "move $1 to $aside"
    [ "$dry_run" -eq 1 ] || mv "$1" "$aside"
}

# Unpacks $zip into $tmp/unpacked and installs it at $dir/DeepYellow.app.
install_app() {
    target="$dir/DeepYellow.app"
    check_destination "$target"
    if [ "$dry_run" -eq 1 ]; then
        move_aside "$target"
        say "unpack $zip and copy DeepYellow.app to $target"
        say "clear quarantine on $target"
        return 0
    fi
    mkdir -p "$tmp/unpacked"
    ditto -x -k "$zip" "$tmp/unpacked"
    [ -d "$tmp/unpacked/DeepYellow.app" ] || die "archive does not contain DeepYellow.app"
    is_deepyellow "$tmp/unpacked/DeepYellow.app" || die "archive's app is not DeepYellow"
    mkdir -p "$dir"
    move_aside "$target"
    ditto "$tmp/unpacked/DeepYellow.app" "$target"
    xattr -dr com.apple.quarantine "$target" 2>/dev/null || true
    echo "installed $target"
}

# Links $bin/deepyellow to the CLI script in the installed app, unless something else is there.
link_cli() {
    link="$bin/deepyellow"
    want="$dir/DeepYellow.app/Contents/Resources/bin/deepyellow"
    if [ -L "$link" ]; then
        case $(readlink "$link") in
            */DeepYellow.app/Contents/Resources/bin/deepyellow) ;;
            *) echo "skipped CLI link: $link points elsewhere" >&2; return 0 ;;
        esac
    elif [ -e "$link" ]; then
        echo "skipped CLI link: $link exists and is not a DeepYellow link" >&2
        return 0
    fi
    say "link $link -> $want"
    if [ "$dry_run" -eq 0 ]; then
        mkdir -p "$bin"
        ln -sfn "$want" "$link"
    fi
    case ":$PATH:" in
        *":$bin:"*) ;;
        *) echo "note: $bin is not on your PATH" ;;
    esac
}

# Runs the install.
main() {
    parse_args "$@"
    trap cleanup EXIT
    if [ "$dry_run" -eq 0 ]; then tmp=$(mktemp -d); fi
    zip=""
    if [ -n "$from_file" ]; then use_local_file; else fetch_release; fi
    install_app
    link_cli
    if [ "$dry_run" -eq 1 ]; then echo "dry run: nothing was changed"; else echo "done. Run: $bin/deepyellow --version"; fi
}

main "$@"
