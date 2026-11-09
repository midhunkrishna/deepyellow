#!/bin/sh
# Runs inside a lab VM made from dy-base-dev: measures the JavaScript package managers in phases, so the host can take a
# snapshot between them. The same dependency list is installed with npm, pnpm, Yarn 1, Yarn 4 and Bun, each in its own
# project under ~/Projects, so their caches and node_modules can be compared like for like.
#
# usage: sh run.sh <phase>
#   install-tools  nvm and Node LTS, corepack (pnpm, Yarn) and Bun, with their official installers
#   workload       install the dependency list in each project
#   cleanup-dry    print what each tool's own cleanup reports, without removing anything
#   cleanup        run each tool's own cache cleanup
#   recache        remove the caches and node_modules, then install again to show what comes back
set -eu

export NVM_DIR="$HOME/.nvm" COREPACK_ENABLE_DOWNLOAD_PROMPT=0 COREPACK_ENABLE_AUTO_PIN=0
work="$HOME/Projects"
deps='"react": "^19", "react-dom": "^19", "next": "^15", "typescript": "^5", "eslint": "^9", "vite": "^6",
      "jest": "^29", "webpack": "^5", "lodash": "^4", "axios": "^1", "@mui/material": "^7", "@emotion/react": "^11",
      "@emotion/styled": "^11", "express": "^5", "prisma": "^6", "sharp": "^0.34"'

# Loads nvm and puts Node, corepack shims and Bun on PATH.
tools() {
    . "$NVM_DIR/nvm.sh"
    export PATH="$HOME/.bun/bin:$PATH"
}

# Writes a project's package.json, with an optional packageManager field.
project() {
    mkdir -p "$work/$1"
    pm=${2:+"\"packageManager\": \"$2\","}
    printf '{ "name": "%s", "private": true, %s "dependencies": { %s } }\n' "$1" "$pm" "$deps" > "$work/$1/package.json"
}

# Installs the dependencies in every project with its own package manager; a failing tool is reported, not fatal.
install_all() {
    printf 'dangerouslyAllowAllBuilds: true\n' > "$work/pnpm-app/pnpm-workspace.yaml"  # approve sharp, esbuild, prisma
    (cd "$work/npm-app" && npm install --no-audit --no-fund --loglevel=error) || echo "npm install failed"
    (cd "$work/pnpm-app" && pnpm install --reporter=silent) || echo "pnpm install failed"
    (cd "$work/yarn1-app" && yarn install --silent --non-interactive) || echo "yarn 1 install failed"
    (cd "$work/yarn4-app" && touch yarn.lock && YARN_ENABLE_TELEMETRY=0 yarn install > /dev/null) || echo "yarn 4 install failed"
    (cd "$work/bun-app" && bun install --silent) || echo "bun install failed"
}

# Prints a folder's size in KB, or 0 if it does not exist.
size_kb() { if [ -e "$1" ]; then du -sk "$1" | cut -f1; else echo 0; fi; }

# Prints the sizes of every cache, store and project folder.
report() {
    for d in "$HOME/.nvm/versions" "$HOME/.nvm/.cache" "$HOME/.npm/_cacache" "$HOME/Library/pnpm/store" \
             "$HOME/Library/Caches/pnpm" "$HOME/Library/Caches/Yarn" "$HOME/.yarn/berry/cache" "$HOME/.bun/install/cache" \
             "$HOME/.cache/node/corepack" "$work/npm-app/node_modules" "$work/pnpm-app/node_modules" \
             "$work/yarn1-app/node_modules" "$work/yarn4-app/node_modules" "$work/yarn4-app/.yarn" "$work/bun-app/node_modules"; do
        printf '%10s KB  %s\n' "$(size_kb "$d")" "${d#$HOME/}"
    done
}

case ${1:?usage: run.sh <phase>} in
    install-tools)
        curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | PROFILE=/dev/null bash > /tmp/nvm.log 2>&1
        . "$NVM_DIR/nvm.sh"; nvm install --lts > /tmp/node.log 2>&1
        npm install -g corepack --silent > /dev/null  # no longer bundled with current Node releases
        corepack enable; corepack prepare pnpm@latest --activate > /dev/null; corepack prepare yarn@1.22.22 --activate > /dev/null
        curl -fsSL https://bun.sh/install | bash > /tmp/bun.log 2>&1
        tools; echo "node $(node -v), npm $(npm -v), pnpm $(pnpm -v), yarn $(yarn -v), bun $(bun -v)" ;;
    workload)
        tools
        project npm-app; project pnpm-app; project yarn1-app; project yarn4-app "yarn@4.9.2"; project bun-app
        install_all; echo "installed in 5 projects" ;;
    cleanup-dry)
        tools
        npm cache verify 2>&1 | tail -3
        (cd "$work/pnpm-app" && pnpm store path)
        echo "yarn 1 cache: $(cd "$work/yarn1-app" && yarn cache dir)" ;;
    cleanup)
        tools
        npm cache clean --force 2>&1 | tail -1
        (cd "$work/pnpm-app" && pnpm store prune 2>&1 | tail -2)
        (cd "$work/yarn1-app" && yarn cache clean 2>&1 | tail -1)
        (cd "$work/yarn4-app" && yarn cache clean --all 2>&1 | tail -1)
        bun pm cache rm 2>&1 | tail -1
        nvm cache clear 2>&1 | tail -1 ;;
    recache)
        tools
        for p in npm-app pnpm-app yarn1-app yarn4-app bun-app; do rm -rf "$work/$p/node_modules"; done
        rm -rf "$HOME/.npm/_cacache" "$HOME/Library/pnpm/store" "$HOME/Library/Caches/Yarn" "$HOME/.yarn/berry/cache" "$HOME/.bun/install/cache"
        install_all; echo "reinstalled in 5 projects"; (cd "$work/npm-app" && node -e "require('lodash'); console.log('npm-app loads lodash')") ;;
    *) echo "run.sh: unknown phase $1" >&2; exit 1 ;;
esac
report
