#!/bin/sh
# Runs inside a lab VM made from dy-base-dev (Command Line Tools installed): measures Homebrew in phases, so the host
# can take a snapshot between them. Analytics are turned off so lab runs don't count as real installs.
#
# usage: sh run.sh <phase>
#   install-brew   install Homebrew with its official script
#   workload       install a fixed set of popular formulae and casks
#   cleanup-dry    print what `brew cleanup` and `brew autoremove` would remove, without removing it
#   cleanup        run `brew cleanup --prune=all` and `brew autoremove`
#   recache        remove the download cache, then reinstall one formula to show what comes back
set -eu

export HOMEBREW_NO_ANALYTICS=1 HOMEBREW_NO_ENV_HINTS=1 NONINTERACTIVE=1
brew=/opt/homebrew/bin/brew
formulae="wget jq ripgrep fd gh htop tree cmake node python@3.13 go postgresql@17 redis imagemagick ffmpeg"
casks="iterm2 rectangle firefox"

# Prints a folder's size in KB, or 0 if it does not exist.
size_kb() { if [ -e "$1" ]; then du -sk "$1" | cut -f1; else echo 0; fi; }

# Prints the sizes of Homebrew's folders, one per line.
report() {
    for d in /opt/homebrew /opt/homebrew/Cellar /opt/homebrew/Caskroom "$HOME/Library/Caches/Homebrew" \
             "$HOME/Library/Logs/Homebrew"; do
        printf '%10s KB  %s\n' "$(size_kb "$d")" "$d"
    done
}

case ${1:?usage: run.sh <phase>} in
    install-brew)
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" > /tmp/brew-install.log 2>&1
        $brew --version | head -1 ;;
    workload)
        $brew install --quiet $formulae > /tmp/brew-workload.log 2>&1
        $brew install --quiet --cask $casks >> /tmp/brew-workload.log 2>&1
        echo "$($brew list --formula | wc -l | tr -d ' ') formulae, $($brew list --cask | wc -l | tr -d ' ') casks installed" ;;
    cleanup-dry)
        $brew cleanup --prune=all --dry-run 2>&1 | tail -3
        $brew autoremove --dry-run 2>&1 | tail -3 ;;
    cleanup)
        $brew cleanup --prune=all 2>&1 | tail -2
        $brew autoremove 2>&1 | tail -2 ;;
    recache)
        rm -rf "$HOME/Library/Caches/Homebrew"
        $brew reinstall --quiet jq > /tmp/brew-recache.log 2>&1
        jq --version ;;
    *) echo "run.sh: unknown phase $1" >&2; exit 1 ;;
esac
report
