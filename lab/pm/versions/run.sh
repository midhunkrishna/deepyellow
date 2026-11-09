#!/bin/sh
# Runs inside a lab VM made from dy-base-dev: measures version managers in phases, so the host can take a snapshot
# between them. mise and asdf each install Node; mise also installs Python. SDKMAN installs a JDK, Gradle and Maven,
# which then build the same public Java project, so Gradle's and Maven's caches fill.
#
# usage: sh run.sh <phase>
#   install-tools  mise, asdf and SDKMAN with their official installers
#   workload       install language versions and build the Java project with Gradle and Maven
#   java-tools     Homebrew and its Bash (SDKMAN needs Bash 4), then SDKMAN
#   java-workload  JDK, Gradle and Maven from SDKMAN, then build the Java project with both
#   cleanup-dry    print what each tool's own cleanup would remove
#   cleanup        run each tool's own cleanup
#   recache        remove the caches, then build again to show what comes back
set -eu

work="$HOME/Projects"
export PATH="$HOME/.local/bin:$HOME/.asdf-bin:$PATH" ASDF_DATA_DIR="$HOME/.asdf" NODEJS_CHECK_SIGNATURES=no
export MISE_YES=1 MISE_QUIET=1

# SDKMAN needs Bash 4 or later; macOS ships 3.2, so the java-tools phase installs Homebrew's Bash.
bash4=/opt/homebrew/bin/bash

# Runs an sdk command in Bash 4, where SDKMAN works.
sdk() { "$bash4" -c "source \$HOME/.sdkman/bin/sdkman-init.sh && sdk $*"; }

# Runs a command with the SDKMAN JDK, Gradle and Maven on PATH.
with_java() { "$bash4" -c "source \$HOME/.sdkman/bin/sdkman-init.sh && $*"; }

# Builds the Java project with Gradle and with Maven; a failing build is reported, not fatal.
build_java() {
    with_java "cd '$work/petclinic' && gradle -q --no-daemon build -x test" || echo "gradle build failed"
    with_java "cd '$work/petclinic' && mvn -q -B -DskipTests package" || echo "maven build failed"
}

# Prints a folder's size in KB, or 0 if it does not exist.
size_kb() { if [ -e "$1" ]; then du -sk "$1" | cut -f1; else echo 0; fi; }

# Prints the sizes of every install, cache and build folder.
report() {
    for d in "$HOME/.local/share/mise/installs" "$HOME/.local/share/mise/downloads" "$HOME/Library/Caches/mise" \
             "$HOME/.asdf/installs" "$HOME/.asdf/downloads" "$HOME/.asdf/plugins" "$HOME/.sdkman/candidates" \
             "$HOME/.sdkman/archives" "$HOME/.sdkman/tmp" "$HOME/.gradle/caches" "$HOME/.gradle/wrapper" "$HOME/.gradle/daemon" \
             "$HOME/.m2/repository" "$work/petclinic/build" "$work/petclinic/target"; do
        printf '%10s KB  %s\n' "$(size_kb "$d")" "${d#$HOME/}"
    done
}

case ${1:?usage: run.sh <phase>} in
    install-tools)
        curl -fsSL https://mise.run | sh > /tmp/mise.log 2>&1
        tag=$(curl -fsSL https://api.github.com/repos/asdf-vm/asdf/releases/latest | sed -n 's/.*"tag_name": "\(.*\)".*/\1/p')
        mkdir -p "$HOME/.asdf-bin"
        curl -fsSL "https://github.com/asdf-vm/asdf/releases/download/$tag/asdf-$tag-darwin-arm64.tar.gz" | tar -xz -C "$HOME/.asdf-bin"
        curl -fsSL "https://get.sdkman.io?rcupdate=false" | bash > /tmp/sdkman.log 2>&1
        echo "mise $(mise -v | cut -d' ' -f1), asdf $(asdf version), sdkman $(sdk version | tail -1)" ;;
    workload)
        mise use -g node@22 python@3.12 > /dev/null || echo "mise failed"
        { asdf plugin add nodejs > /dev/null && asdf install nodejs 20.19.0 > /dev/null; } || echo "asdf failed"
        sdk install java < /dev/null > /dev/null || echo "sdk java failed"
        sdk install gradle < /dev/null > /dev/null || echo "sdk gradle failed"
        sdk install maven < /dev/null > /dev/null || echo "sdk maven failed"
        mkdir -p "$work/petclinic"
        curl -fsSL https://codeload.github.com/spring-projects/spring-petclinic/tar.gz/refs/heads/main | tar -xz -C "$work/petclinic" --strip-components 1
        build_java; echo "workload done" ;;
    java-tools)
        NONINTERACTIVE=1 HOMEBREW_NO_ANALYTICS=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" > /tmp/brew.log 2>&1
        HOMEBREW_NO_ANALYTICS=1 /opt/homebrew/bin/brew install -q bash > /dev/null 2>&1
        curl -fsSL "https://get.sdkman.io?rcupdate=false" | "$bash4" > /tmp/sdkman.log 2>&1
        echo "$("$bash4" --version | head -1 | cut -d' ' -f1-4), sdkman $(sdk version | tail -1)" ;;
    java-workload)
        sdk install java < /dev/null > /dev/null || echo "sdk java failed"
        sdk install gradle < /dev/null > /dev/null || echo "sdk gradle failed"
        sdk install maven < /dev/null > /dev/null || echo "sdk maven failed"
        [ -d "$work/petclinic/src" ] || { mkdir -p "$work/petclinic"; curl -fsSL https://codeload.github.com/spring-projects/spring-petclinic/tar.gz/refs/heads/main | tar -xz -C "$work/petclinic" --strip-components 1; }
        build_java; ls "$work/petclinic/target"/*.jar "$work/petclinic/build/libs"/*.jar 2>/dev/null | wc -l | xargs echo "jars built:" ;;
    cleanup-dry)
        mise prune --dry-run 2>&1 | tail -3
        echo "sdkman archives: $(ls "$HOME/.sdkman/archives" 2>/dev/null | wc -l | tr -d ' ') files" ;;
    cleanup)
        mise prune 2>&1 | tail -2; mise cache clear 2>&1 | tail -1
        sdk flush < /dev/null 2>&1 | tail -3 ;;
    recache)
        rm -rf "$HOME/.gradle/caches" "$HOME/.m2/repository" "$HOME/Library/Caches/mise" "$HOME/.asdf/downloads"
        rm -rf "$work/petclinic/build" "$work/petclinic/target"
        build_java; ls "$work/petclinic/target"/*.jar "$work/petclinic/build/libs"/*.jar 2>/dev/null | wc -l | xargs echo "jars built:" ;;
    *) echo "run.sh: unknown phase $1" >&2; exit 1 ;;
esac
report
