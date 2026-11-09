#!/bin/sh
# Runs inside a lab VM made from dy-base-dev: measures Rust (rustup, Cargo), Go, Ruby gems and SwiftPM in phases, so
# the host can take a snapshot between them. Each builds a real public project from source.
#
# usage: sh run.sh <phase>
#   install-tools  rustup (stable toolchain) and Go with their official installers; Ruby and Swift come with the
#                  Command Line Tools
#   workload       build ripgrep with Cargo, gh with Go and a package using swift-argument-parser with SwiftPM, and
#                  install some gems into the user's gem folder
#   cleanup-dry    print what each tool's own cleanup would remove
#   cleanup        run each tool's own cleanup
#   recache        remove the caches and build output, then build again to show what comes back
set -eu

work="$HOME/Projects"
export PATH="$HOME/.cargo/bin:$HOME/sdk/go/bin:$HOME/go/bin:$PATH" GOTOOLCHAIN=local GOFLAGS=-mod=mod

# Writes a small Swift package that depends on swift-argument-parser and swift-log.
swift_package() {
    mkdir -p "$work/swift-app/Sources/App"
    cat > "$work/swift-app/Package.swift" <<'EOF'
// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "App",
    dependencies: [.package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
                   .package(url: "https://github.com/apple/swift-log", from: "1.6.0")],
    targets: [.executableTarget(name: "App", dependencies: [.product(name: "ArgumentParser", package: "swift-argument-parser"),
                                                             .product(name: "Logging", package: "swift-log")])])
EOF
    printf 'import ArgumentParser\nimport Logging\n@main struct App: ParsableCommand { func run() { Logger(label: "app").info("hi") } }\n' \
        > "$work/swift-app/Sources/App/main.swift"
}

# Fetches a project from GitHub into ~/Projects unless it is there already.
fetch() {
    [ -d "$work/$1" ] && return 0
    mkdir -p "$work/$1"
    curl -fsSL "https://codeload.github.com/$2/tar.gz/refs/heads/$3" | tar -xz -C "$work/$1" --strip-components 1
}

# Builds every project; a failing build is reported, not fatal.
build_all() {
    (cd "$work/ripgrep" && cargo build -q --release) || echo "cargo build failed"
    (cd "$work/gh" && go build -o bin/gh ./cmd/gh) || echo "go build failed"
    (cd "$work/swift-app" && swift build -c release > /dev/null) || echo "swift build failed"
    gem install --user-install --no-document rake rspec rubocop > /dev/null 2>&1 || echo "gem install failed"
}

# Prints a folder's size in KB, or 0 if it does not exist.
size_kb() { if [ -e "$1" ]; then du -sk "$1" | cut -f1; else echo 0; fi; }

# Prints the sizes of every toolchain, cache and build folder.
report() {
    for d in "$HOME/.rustup/toolchains" "$HOME/.rustup/downloads" "$HOME/.cargo/registry" "$HOME/.cargo/git" \
             "$work/ripgrep/target" "$HOME/sdk/go" "$HOME/go/pkg/mod" "$HOME/Library/Caches/go-build" "$work/gh/bin" \
             "$HOME/.gem" "$HOME/Library/Caches/org.swift.swiftpm" "$HOME/Library/org.swift.swiftpm" "$work/swift-app/.build"; do
        printf '%10s KB  %s\n' "$(size_kb "$d")" "${d#$HOME/}"
    done
}

case ${1:?usage: run.sh <phase>} in
    install-tools)
        curl -fsSL https://sh.rustup.rs | sh -s -- -y --no-modify-path --profile default > /tmp/rustup.log 2>&1
        v=$(curl -fsSL "https://go.dev/VERSION?m=text" | head -1); mkdir -p "$HOME/sdk"
        curl -fsSL "https://go.dev/dl/$v.darwin-arm64.tar.gz" | tar -xz -C "$HOME/sdk"
        echo "$(rustc -V | cut -d' ' -f1-2), $(go version | cut -d' ' -f3), ruby $(ruby -e 'print RUBY_VERSION'), $(swift --version 2>&1 | head -1 | cut -d'(' -f1)" ;;
    workload)
        fetch ripgrep BurntSushi/ripgrep master; fetch gh cli/cli trunk; swift_package
        build_all; echo "built 3 projects, installed gems" ;;
    cleanup-dry)
        echo "go clean would remove the module cache ($(du -sk "$HOME/go/pkg/mod" | cut -f1) KB) and build cache"
        gem cleanup --user-install --dryrun 2>&1 | tail -2 ;;
    cleanup)
        go clean -modcache; go clean -cache
        (cd "$work/swift-app" && swift package purge-cache)
        (cd "$work/ripgrep" && cargo clean -q)
        gem cleanup --user-install 2>&1 | tail -1 ;;
    recache)
        rm -rf "$HOME/.cargo/registry" "$HOME/go/pkg/mod" "$HOME/Library/Caches/go-build" "$HOME/Library/Caches/org.swift.swiftpm" \
               "$work/ripgrep/target" "$work/swift-app/.build" "$work/gh/bin"
        build_all
        "$work/ripgrep/target/release/rg" --version | head -1; "$work/gh/bin/gh" --version | head -1 ;;
    *) echo "run.sh: unknown phase $1" >&2; exit 1 ;;
esac
report
