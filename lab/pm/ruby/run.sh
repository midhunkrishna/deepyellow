#!/bin/sh
# Runs inside a lab VM made from dy-base-dev: measures Ruby version managers and Bundler in phases, so the host can take
# a snapshot between them. rbenv (with ruby-build, from Homebrew), RVM and mise each build Ruby 3.4, then install the
# same Gemfile: rbenv and RVM into the Ruby's own gem folder, mise into the project's vendor/bundle.
#
# usage: sh run.sh <phase>
#   install-tools  Homebrew, rbenv and ruby-build from Homebrew, RVM (master: its 2020 stable release predates Ruby
#                  3.4) and mise with their official installers
#   workload       build Ruby 3.4 with each manager and bundle the Gemfile in one project per manager
#   cleanup-dry    print what each tool's own cleanup would remove
#   cleanup        run each tool's own cleanup
#   recache        remove download and gem caches and vendor/bundle, then bundle again to show what comes back
set -eu

work="$HOME/Projects"
export HOMEBREW_NO_ANALYTICS=1 HOMEBREW_NO_ENV_HINTS=1 NONINTERACTIVE=1 MISE_YES=1 MISE_QUIET=1
export PATH="$HOME/.rbenv/shims:/opt/homebrew/bin:$HOME/.local/bin:$PATH"
projects="rbenv-app rvm-app mise-app"
# The exact Ruby version the workload chose, kept in each project's .ruby-version (rbenv and RVM need it exact).
v=$(cat "$work/rbenv-app/.ruby-version" 2>/dev/null || true)

# Runs a command in Bash with RVM loaded.
rvm_do() { /bin/bash -c "source \$HOME/.rvm/scripts/rvm && $*"; }

# Writes a project's Gemfile (a Rails app's usual gems plus Jekyll and test and lint tools) and its .ruby-version.
gemfile() {
    mkdir -p "$work/$1"
    cat > "$work/$1/Gemfile" <<'EOF'
source "https://rubygems.org"
gem "rails", "~> 8.0"
gem "puma"
gem "sqlite3"
gem "sidekiq"
gem "nokogiri"
gem "jekyll"
gem "rspec-rails"
gem "rubocop"
gem "rubocop-rails"
EOF
    echo "$v" > "$work/$1/.ruby-version"
}

# Bundles every project with its own manager's Ruby; a failing manager is reported, not fatal.
bundle_all() {
    (cd "$work/rbenv-app" && rbenv exec bundle install --quiet) || echo "rbenv bundle failed"
    rvm_do "cd '$work/rvm-app' && rvm use $v > /dev/null && bundle install --quiet" || echo "rvm bundle failed"
    (cd "$work/mise-app" && mise exec ruby@$v -- sh -c 'bundle config set --local path vendor/bundle && bundle install --quiet') \
        || echo "mise bundle failed"
}

# Prints a folder's size in KB, or 0 if it does not exist.
size_kb() { if [ -e "$1" ]; then du -sk "$1" | cut -f1; else echo 0; fi; }

# Prints the total size in KB of the .gem files Ruby keeps in its gem caches under a folder.
gem_cache_kb() {
    kb=$(find "$1" -path '*/gems/*/cache/*.gem' -type f -print0 2>/dev/null | xargs -0 du -ck 2>/dev/null | tail -1 | cut -f1)
    echo "${kb:-0}"
}

# Installs Ruby with mise, retrying because its prebuilt Rubies come from GitHub releases, which sometimes time out.
mise_ruby() {
    for _ in 1 2 3; do mise install "ruby@$v" > /tmp/mise-build.log 2>&1 && return 0; sleep 20; done
    return 1
}

# Prints the sizes of every Ruby install, cache and bundle folder.
report() {
    for d in "$HOME/.rbenv/versions" "$HOME/.rbenv/cache" "$HOME/Library/Caches/ruby-build" "$HOME/.rvm/rubies" "$HOME/.rvm/gems" \
             "$HOME/.rvm/src" "$HOME/.rvm/archives" "$HOME/.rvm/log" "$HOME/.local/share/mise/installs/ruby" \
             "$HOME/Library/Caches/mise" "$HOME/.local/share/gem" "$HOME/.gem" "$HOME/.bundle/cache" "$HOME/.cache/bundler" \
             "$work/mise-app/vendor/bundle"; do
        printf '%10s KB  %s\n' "$(size_kb "$d")" "${d#$HOME/}"
    done
    for d in "$HOME/.rbenv/versions" "$HOME/.rvm/gems" "$HOME/.local/share/mise/installs/ruby" "$work/mise-app/vendor/bundle"; do
        printf '%10s KB  .gem files in %s\n' "$(gem_cache_kb "$d")" "${d#$HOME/}"
    done
}

case ${1:?usage: run.sh <phase>} in
    install-tools)
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" > /tmp/brew.log 2>&1
        brew install -q rbenv ruby-build openssl@3 libyaml > /tmp/brew-ruby.log 2>&1
        curl -fsSL https://get.rvm.io | /bin/bash -s master --ignore-dotfiles > /tmp/rvm.log 2>&1 || echo "rvm install failed"
        curl -fsSL https://mise.run | sh > /tmp/mise.log 2>&1
        echo "$(rbenv -v), $(ruby-build --version), $(rvm_do 'rvm -v' | awk '{print $1, $2}'), mise $(mise -v | cut -d' ' -f1)" ;;
    workload)
        v=$(rbenv install -l 2>/dev/null | grep -E '^3\.4\.[0-9]+$' | tail -1)
        rbenv install -s "$v" > /tmp/rbenv-build.log 2>&1 && rbenv global "$v" || echo "rbenv build failed"
        rvm_do "rvm install $v > /tmp/rvm-build.log 2>&1" || echo "rvm build failed"
        mise_ruby || echo "mise install failed"
        for p in $projects; do gemfile "$p"; done
        bundle_all; echo "ruby $v with rbenv; $(rvm_do 'rvm list strings' | tr '\n' ' ')with rvm; bundled 3 projects" ;;
    cleanup-dry)
        rvm_do "rvm cleanup --help" 2>&1 | head -3
        (cd "$work/rbenv-app" && rbenv exec gem cleanup --dryrun 2>&1 | tail -2)
        (cd "$work/mise-app" && mise exec ruby@$v -- bundle clean --dry-run 2>&1 | tail -2) ;;
    cleanup)
        rvm_do "rvm cleanup all" 2>&1 | tail -3
        (cd "$work/rbenv-app" && rbenv exec gem cleanup 2>&1 | tail -1)
        rvm_do "cd '$work/rvm-app' && rvm use $v > /dev/null && gem cleanup" 2>&1 | tail -1
        mise cache clear 2>&1 | tail -1 ;;
    recache)
        for d in "$HOME/.rbenv/versions" "$HOME/.rvm/gems" "$HOME/.local/share/mise/installs/ruby"; do
            find "$d" -path '*/gems/*/cache/*.gem' -type f -delete 2>/dev/null || true
        done
        rm -rf "$HOME/.rvm/src" "$HOME/.rvm/archives" "$HOME/.bundle/cache" "$HOME/.cache/bundler" "$work/mise-app/vendor/bundle"
        bundle_all
        (cd "$work/rbenv-app" && rbenv exec ruby -e 'require "bundler/setup"; require "rails"; puts "rbenv-app loads rails #{Rails.version}"')
        (cd "$work/mise-app" && mise exec ruby@$v -- ruby -e 'require "bundler/setup"; require "nokogiri"; puts "mise-app loads nokogiri"') ;;
    *) echo "run.sh: unknown phase $1" >&2; exit 1 ;;
esac
report
