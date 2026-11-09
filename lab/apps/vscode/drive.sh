#!/bin/sh
# Runs inside a lab VM: uses VS Code the way a developer starting on new projects does, only through VS Code's own
# command line. It installs common extensions, downloads a few open-source projects, and opens each project and some
# of its files so the language extensions index them. It never types into the editor or saves a file.
#
# usage: sh drive.sh [seconds-per-project]
set -eu

secs=${1:-60}
code="/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
work=/opt/deepyellow/projects
extensions="ms-python.python dbaeumer.vscode-eslint esbenp.prettier-vscode golang.go rust-lang.rust-analyzer ms-vscode.cpptools"
# owner/repo:branch of public projects in the languages above.
projects="expressjs/express:master psf/requests:main spf13/cobra:main BurntSushi/ripgrep:master nlohmann/json:develop"

for ext in $extensions; do
    "$code" --install-extension "$ext" > /dev/null
done
"$code" --list-extensions --show-versions

mkdir -p "$work"
for p in $projects; do
    repo=${p%%:*}; branch=${p#*:}; dir="$work/$(basename "$repo")"
    [ -d "$dir" ] || { mkdir -p "$dir"; curl -fsSL "https://codeload.github.com/$repo/tar.gz/refs/heads/$branch" | tar -xz -C "$dir" --strip-components 1; }
    "$code" "$dir"
    sleep 5
    find "$dir" -type f \( -name '*.js' -o -name '*.py' -o -name '*.go' -o -name '*.rs' -o -name '*.cpp' -o -name '*.hpp' \) \
        -not -path '*/node_modules/*' | head -6 | while IFS= read -r f; do "$code" --reuse-window "$f"; sleep 2; done
    sleep "$secs"
done
echo "opened $(echo $projects | wc -w | tr -d ' ') projects"
