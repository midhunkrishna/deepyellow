# Reclaim rules

Every rule DeepYellow uses to advise on a place on disk. The rules are read from the JSON files in [`rules/`](https://github.com/midhunkrishna/deepyellow/tree/master/rules) when the app starts, and this page is generated from the same files, so it lists exactly what the app contains.

A rule says what a place is, how safe it is to remove, what removal costs, any condition to meet first, and an official cleanup command when one exists. **Commands are shown and never run.** Removal always goes through a [Plan](safety-and-accounting.md#the-plan) and the Trash.

## How to read it

| Tier | Meaning |
|---|---|
| **safe** | Regenerates automatically with no user-visible loss |
| **rebuild** | Recoverable at a cost of time, network or a login |
| **review** | May hold personal or unique data, so you must look |
| **never** | Not offered for removal, whatever you select |

- A rule applies to everything inside the matched place. The most specific rule wins, and a `never` ancestor always beats anything beneath it.
- Uncertain means `review`. Rules whose source is "Research notes (unverified)" are never given a tier safer than the evidence supports.
- The **source** records where the claim comes from.
- Rules marked "name heuristic" go only on a folder or file name, so they are hints.

### Pattern grammar

Patterns are case-insensitive. `~/` is your home folder and a leading `/` is an absolute path. `*` matches any run of characters within one path segment, and `**` as a middle segment matches zero or more folders. `**/name` at the start matches `name` anywhere. A segment may list alternatives with `|` and exclusions with `&!`, for example `*.sqlite&!*cache*`. Several full paths may be joined with `||`. A trailing `if-sibling:a|b` applies the rule only when a sibling named `a` or `b` exists next to the match.


## Caches

`~/Library/Caches` and its exceptions.


### App cache

**Tier: rebuild** · `caches.thirdparty`

- **Pattern:** `~/Library/Caches/*`
- **What it is:** A cache an app keeps so it can start faster.
- **If you remove it:** The app will be slower the next time it opens while it rebuilds the cache, and an app that stores real data here could lose it.
- **Condition:** Close the app first. Do not offer this when the owning app is unknown.
- **Source:** Apple developer documentation

### Apple system cache

**Tier: never** · `caches.apple`

- **Pattern:** `~/Library/Caches/com.apple.*`
- **What it is:** A cache belonging to macOS or an Apple app.
- **If you remove it:** It is probably harmless to remove but belongs to running system services, and the benefit is small.
- **Condition:** Not offered. macOS clears these itself.
- **Source:** Policy choice

### Homebrew downloads

**Tier: safe** · `caches.homebrew`

- **Pattern:** `~/Library/Caches/Homebrew`
- **What it is:** Bottles, app installers and package lists Homebrew downloaded, kept after installing.
- **If you remove it:** Homebrew downloads a package again only if you reinstall or upgrade it.
- **Condition:** Use the command rather than deleting by hand; plain `brew cleanup` keeps recent downloads and freed nothing in our test.
- **Official command:** `brew cleanup --prune=all`
- **Source:** Measured: Homebrew 7.0.12 on macOS 15.7
- **Measured:** Reached 618 MB after installing 15 formulae (73 with dependencies) and 3 casks. `brew cleanup --prune=all` freed 579 MB, leaving 40 MB of package lists; with the cache refilled to 1.3 GB, plain `brew cleanup` would have freed nothing. After deleting the folder, `brew reinstall jq` worked and the folder came back at 40 MB. (7.0.12, macOS 15.7.7, 2026-11-08)

### JetBrains IDE data

**Tier: review** · `caches.jetbrains`

- **Pattern:** `~/Library/Caches/JetBrains/*`
- **What it is:** Indexes, caches and logs for a JetBrains IDE, including its Local History.
- **If you remove it:** Indexes rebuild slowly, and Local History (your edit history outside version control) cannot be recovered.
- **Condition:** Close the IDE first. Never offer this as one blob.
- **Source:** Research notes (unverified)
- **Evidence:** unverified

### Spotify offline songs

**Tier: rebuild** · `caches.spotify`

- **Pattern:** `~/Library/Caches/com.spotify.client/Storage`
- **What it is:** Songs Spotify saved for offline listening.
- **If you remove it:** You will need to download the songs again, with network access and your account.
- **Condition:** Close Spotify first.
- **Owning app:** `com.spotify.client`
- **Source:** Research notes (unverified)
- **Evidence:** unverified

### Xcode cache

**Tier: rebuild** · `caches.xcode`

- **Pattern:** `~/Library/Caches/com.apple.dt.Xcode`
- **What it is:** Cached data that Xcode uses for indexing.
- **If you remove it:** Xcode will re-index and fetch some information again.
- **Condition:** Close Xcode first.
- **Owning app:** `com.apple.dt.Xcode`
- **Source:** Research notes (unverified)
- **Evidence:** unverified

### Chrome cache

**Tier: rebuild** · `caches.chrome`

- **Pattern:** `~/Library/Caches/Google/Chrome`
- **What it is:** Web pages and images Chrome saved to load sites faster.
- **If you remove it:** Pages load more slowly the first time you visit them again; your logins are not stored here.
- **Condition:** Close the browser first.
- **Owning app:** `com.google.Chrome`
- **Source:** Research notes (unverified)
- **Evidence:** unverified

### Firefox cache

**Tier: rebuild** · `caches.firefox`

- **Pattern:** `~/Library/Caches/Firefox/Profiles/*/cache2`
- **What it is:** Web pages and images Firefox saved to load sites faster.
- **If you remove it:** Pages load more slowly the first time you visit them again; your logins are not stored here.
- **Condition:** Close the browser first.
- **Owning app:** `org.mozilla.firefox`
- **Source:** Research notes (unverified)
- **Evidence:** unverified

### Cache folder that may hold your data

**Tier: review** · `caches.heuristic.names`

- **Pattern:** `~/Library/Caches/*/**/*Offline*|*Downloads*|*Drafts*|*Recordings*`
- **What it is:** A folder inside a cache whose name suggests saved content rather than temporary files.
- **If you remove it:** If it holds your own content, removing it could lose that content for good.
- **Condition:** Based on the folder name only, so treat it as a hint.
- **Source:** Name heuristic

### Database inside a cache

**Tier: review** · `caches.heuristic.sqlite`

- **Pattern:** `~/Library/Caches/*/**/*.sqlite&!*cache*`
- **What it is:** A database file inside a cache folder that does not look like a cache.
- **If you remove it:** If it holds your own records, removing it could lose them for good.
- **Condition:** Based on the file name only, so treat it as a hint.
- **Source:** Name heuristic

## Xcode and developer tools

Xcode, simulators and the toolchain.


### Xcode build files

**Tier: rebuild** · `xcode.deriveddata`

- **Pattern:** `~/Library/Developer/Xcode/DerivedData`
- **What it is:** Build results and indexes Xcode creates for your projects.
- **If you remove it:** Every project will rebuild and re-index in full the next time you open it.
- **Condition:** Quit Xcode and any builds. Delete the contents, not the folder.
- **Source:** Third-party guides
- **Evidence:** unverified

### Xcode archives

**Tier: review** · `xcode.archives`

- **Pattern:** `~/Library/Developer/Xcode/Archives`
- **What it is:** Saved builds of apps you shipped, with their debugging symbols.
- **If you remove it:** You would lose the ability to read crash reports for those builds or re-export them.
- **Condition:** Review each archive by date and version. Move to Trash only.
- **Source:** Third-party guides
- **Evidence:** unverified

### Device support files

**Tier: rebuild** · `xcode.devicesupport`

- **Pattern:** `~/Library/Developer/Xcode/*DeviceSupport/*`
- **What it is:** Debugging symbols Xcode copied from a connected iPhone, iPad or watch.
- **If you remove it:** Xcode copies them again the next time you connect that device, which is slow, and old crash logs lose their symbols until then.
- **Condition:** Delete the folders inside, never the parent. Keep the newest two versions. Close Xcode first.
- **Source:** Apple Developer Forums

### Simulator devices

**Tier: review** · `xcode.simulators`

- **Pattern:** `~/Library/Developer/CoreSimulator/Devices/*`
- **What it is:** A simulated iPhone or iPad with its installed apps and test data.
- **If you remove it:** You would lose the apps and test data inside that simulator.
- **Condition:** Do not delete by hand. The command removes only simulators whose runtime is gone.
- **Official command:** `xcrun simctl delete unavailable`
- **Source:** Third-party guides
- **Evidence:** unverified

### Simulator runtimes

**Tier: rebuild** · `xcode.simruntimes`

- **Pattern:** `/Library/Developer/CoreSimulator/Volumes|Images|Cryptex`
- **What it is:** The system images that simulators run on.
- **If you remove it:** You would need to download the runtime again, which can be several gigabytes.
- **Condition:** Remove through Xcode Settings or the runtime commands, never by hand or by unmounting.
- **Official command:** `xcrun simctl runtime list`
- **Source:** Local tool help

### Xcode settings

**Tier: never** · `xcode.userdata`

- **Pattern:** `~/Library/Developer/Xcode/UserData`
- **What it is:** Your Xcode snippets, themes and key bindings.
- **If you remove it:** You would lose settings you wrote yourself.
- **Condition:** Not offered.
- **Source:** Research notes (unverified)
- **Evidence:** unverified

## Containers, backups and system areas

Virtual machines, backups and parts of macOS that are shown but not offered.


### iPhone or iPad backup

**Tier: review** · `backup.iphone`

- **Pattern:** `~/Library/Application Support/MobileSync/Backup/*`
- **What it is:** A backup of an iPhone or iPad stored on this Mac.
- **If you remove it:** That backup would be gone for good, and if the device is lost with no iCloud backup its data cannot be recovered.
- **Condition:** Delete from Finder or the Apple Devices app, not by hand.
- **Source:** Apple Support

### Docker disk image

**Tier: review** · `docker.raw`

- **Pattern:** `~/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw`
- **What it is:** The single file holding every Docker image, container and volume.
- **If you remove it:** Deleting it would destroy all your images, containers and volume data, including databases.
- **Condition:** Never remove the file itself. The command clears only unused items.
- **Official command:** `docker system prune`
- **Owning app:** `com.docker.docker`
- **Source:** Docker documentation

### Virtual machine

**Tier: review** · `vm.disks`

- **Pattern:** `~/Parallels || ~/Virtual Machines.localized || ~/.lima || ~/.colima || ~/Library/Containers/com.utmapp.UTM`
- **What it is:** A virtual machine and everything stored inside it.
- **If you remove it:** You would lose that virtual machine and all of its data.
- **Condition:** Shown for information only.
- **Source:** Research notes (unverified)
- **Evidence:** unverified

### OS update area

**Tier: never** · `system.osupdate`

- **Pattern:** `/Library/Updates || /System/Library/AssetsV2 || /System/Library/Assets`
- **What it is:** Files macOS uses to stage and apply updates.
- **If you remove it:** Removing them could interfere with system updates.
- **Condition:** Manage only through System Settings.
- **Source:** Research notes (unverified)
- **Evidence:** unverified

### Swap and sleep files

**Tier: never** · `system.swap`

- **Pattern:** `/System/Volumes/VM/swapfile* || /private/var/vm`
- **What it is:** Memory swap files managed by the system.
- **If you remove it:** They are managed by macOS and the space returns by itself.
- **Condition:** Shown under system volumes, not offered.
- **Source:** Local observation

### System temporary data

**Tier: never** · `system.varfolders`

- **Pattern:** `/private/var/folders || /var/folders`
- **What it is:** Temporary files and caches in use by running programs.
- **If you remove it:** Programs that are running would fail or lose their working data.
- **Condition:** Display only.
- **Source:** Local observation

### System logs

**Tier: never** · `system.logs.protected`

- **Pattern:** `/var/log || /private/var/log || /var/db/diagnostics || /private/var/db/diagnostics || /Library/Logs`
- **What it is:** Logs and diagnostics macOS keeps for the whole system.
- **If you remove it:** They belong to macOS and are mostly owned by the system, so they are not offered for removal.
- **Source:** Research notes
- **Evidence:** unverified

### App language files

**Tier: never** · `system.lproj`

- **Pattern:** `/Applications/*.app/Contents/Resources/*.lproj`
- **What it is:** Language files inside an installed app.
- **If you remove it:** Removing them may invalidate the app's signature so it will not open.
- **Condition:** Not offered.
- **Source:** Eclectic Light Company
- **Evidence:** unverified

## Package managers and build output

Language caches, dependencies and build folders.


### JavaScript dependencies

**Tier: rebuild** · `node.modules`

- **Pattern:** `**/node_modules if-sibling:package-lock.json|npm-shrinkwrap.json|yarn.lock|pnpm-lock.yaml|bun.lock|bun.lockb`
- **What it is:** Libraries a JavaScript project installed.
- **If you remove it:** You will need to run the install again, with network access, and any local patches are lost.
- **Condition:** Offered because a lockfile sits next to it.
- **Source:** Measured: removed and reinstalled with npm 11, pnpm 12, Yarn 1 and Bun 1.4 on macOS 15.7
- **Measured:** Five projects with the same 16 dependencies (about 560 packages) had 606 to 680 MB of node_modules each. After removal, npm, pnpm, Yarn 1 and Bun each installed them again in 4 to 30 seconds, and the npm project loaded its packages. Bun projects have a bun.lock lockfile. (npm 11.20.0, pnpm 12.18.0, yarn 1.22.22, bun 1.4.4, macOS 15.7.7, 2026-11-08)

### JavaScript dependencies without a lockfile

**Tier: review** · `node.modules.nolock`

- **Pattern:** `**/node_modules`
- **What it is:** Libraries a JavaScript project installed, with no lockfile beside them.
- **If you remove it:** Without a lockfile the same versions may not come back, and local patches are lost.
- **Source:** Research notes (unverified)
- **Evidence:** unverified

### Yarn committed cache

**Tier: never** · `yarn.zeroinstall`

- **Pattern:** `**/.yarn/cache`
- **What it is:** A Yarn cache that some projects keep in version control as their dependency source.
- **If you remove it:** The project may be unable to install its dependencies.
- **Condition:** Not offered.
- **Source:** Research notes (unverified)
- **Evidence:** unverified

### npm download cache

**Tier: rebuild** · `npm.cache`

- **Pattern:** `~/.npm`
- **What it is:** Packages npm downloaded earlier.
- **If you remove it:** npm will download them again when needed.
- **Official command:** `npm cache clean --force`
- **Source:** Measured: removed and reinstalled with npm 11 on macOS 15.7
- **Measured:** Reached 612 MB for one project of 559 packages. `npm cache clean --force` emptied it, deleting it freed 129 of 130 MB on disk, and npm installed again afterwards. (11.20.0, macOS 15.7.7, 2026-11-08)

### pnpm package store

**Tier: rebuild** · `pnpm.store`

- **Pattern:** `~/Library/pnpm/store || ~/.local/share/pnpm/store`
- **What it is:** The shared store that pnpm links project dependencies from.
- **If you remove it:** pnpm downloads packages again when you next install, and while your projects keep their node_modules this frees little disk space.
- **Condition:** `pnpm store prune` removes only packages that no project uses.
- **Official command:** `pnpm store prune`
- **Source:** Measured: removed and reinstalled with pnpm 12 on macOS 15.7
- **Measured:** Reached 1.1 GB, plus a 268 MB metadata cache in ~/Library/Caches/pnpm, for one project of about 560 packages; `pnpm store prune` removed 0 packages. Deleting the store freed only 64 MB of disk, because pnpm on macOS clones files into node_modules, which keep the data. pnpm installed again afterwards. (12.18.0, macOS 15.7.7, 2026-11-08)

### pip cache

**Tier: rebuild** · `pip.cache`

- **Pattern:** `~/Library/Caches/pip || ~/.cache/pip`
- **What it is:** Python packages pip downloaded earlier.
- **If you remove it:** pip will download or rebuild them when needed.
- **Official command:** `pip cache purge`
- **Source:** Measured: removed and reinstalled with pip 26 on macOS 15.7
- **Measured:** Reached 281 MB installing 13 popular packages, PyTorch among them, into one virtual environment. `pip cache purge` emptied it, deleting it freed 272 of 274 MB on disk, and pip installed again afterwards. (26.2.2, macOS 15.7.7, 2026-11-08)

### uv cache

**Tier: rebuild** · `uv.cache`

- **Pattern:** `~/.cache/uv`
- **What it is:** Python packages uv downloaded earlier.
- **If you remove it:** uv downloads packages again when you next install, and while your environments exist this frees almost no disk space.
- **Condition:** `uv cache prune` removes only entries no environment uses.
- **Official command:** `uv cache clean`
- **Source:** Measured: removed and reinstalled with uv 0.13 on macOS 15.7
- **Measured:** Reached 1.17 GB for one project with 13 popular packages; `uv cache prune` found nothing unused. Deleting it freed no measurable disk space, because uv on macOS clones files into environments, which kept working. uv installed again afterwards. (0.13.7, macOS 15.7.7, 2026-11-08)

### conda packages

**Tier: rebuild** · `conda.pkgs`

- **Pattern:** `~/miniconda3/pkgs || ~/anaconda3/pkgs || ~/miniforge3/pkgs`
- **What it is:** Package files shared by your conda environments.
- **If you remove it:** conda downloads packages again when it needs them, and while your environments exist this frees little disk space.
- **Condition:** Use the command, never delete by hand.
- **Official command:** `conda clean --all`
- **Source:** Measured: removed and reinstalled with conda 26 (Miniforge) on macOS 15.7
- **Measured:** Reached 2.18 GB for the base install and one environment with 13 popular packages. `conda clean --all` freed 344 MB. Deleting the folder freed only 133 of 1,808 MB, because conda hard-links package files into environments, which kept working. (26.9.4, macOS 15.7.7, 2026-11-08)

### conda environments

**Tier: review** · `conda.envs`

- **Pattern:** `~/miniconda3/envs/* || ~/anaconda3/envs/* || ~/miniforge3/envs/*`
- **What it is:** Python environments you created.
- **If you remove it:** You would lose the environment and its installed packages.
- **Source:** Measured: conda 26 (Miniforge) on macOS 15.7
- **Observed:** One environment with Python 3.12 and 13 popular packages, PyTorch among them, took 1.74 GB.

### Cargo downloads

**Tier: rebuild** · `cargo.cache`

- **Pattern:** `~/.cargo/registry || ~/.cargo/git`
- **What it is:** Rust libraries Cargo downloaded earlier.
- **If you remove it:** Cargo will download them again, which needs the network.
- **Source:** Measured: removed and rebuilt with Cargo 1.99 on macOS 15.7
- **Measured:** Reached 32 MB of crates for one project (ripgrep). After removal, Cargo downloaded them again and the project built. (1.99.1, macOS 15.7.7, 2026-11-08)

### Cargo tools and settings

**Tier: never** · `cargo.keep`

- **Pattern:** `~/.cargo/bin || ~/.cargo/credentials.toml || ~/.cargo/config.toml || ~/.cargo/.crates.toml || ~/.cargo/.crates2.json`
- **What it is:** Rust tools you installed, your registry login and your settings.
- **If you remove it:** You would lose installed tools and have to log in and configure Cargo again.
- **Condition:** Not offered.
- **Source:** Cargo documentation

### Rust build output

**Tier: rebuild** · `cargo.target`

- **Pattern:** `**/target if-sibling:Cargo.toml`
- **What it is:** Files produced by building a Rust project.
- **If you remove it:** The project will rebuild in full next time.
- **Official command:** `cargo clean`
- **Source:** Measured: removed and rebuilt with Cargo 1.99 on macOS 15.7
- **Measured:** A release build of ripgrep left 166 MB in target. `cargo clean` emptied it, and the project built again afterwards. (1.99.1, macOS 15.7.7, 2026-11-08)

### Gradle downloads

**Tier: rebuild** · `gradle.cache`

- **Pattern:** `~/.gradle/caches || ~/.gradle/wrapper/dists || ~/.gradle/daemon`
- **What it is:** Libraries and tools Gradle downloaded earlier.
- **If you remove it:** Gradle will download them again and the next build will be slower.
- **Condition:** Not while a Gradle daemon is running.
- **Source:** Measured: removed and rerun with Gradle 9.5 on macOS 15.7
- **Measured:** One project (Spring PetClinic) filled 315 MB of caches and 154 MB of wrapper distributions. Deleting the caches freed 311 MB on disk, and the next run downloaded 188 MB again; that build then stopped on a Java version the project asks for, unrelated to the cache. (9.5.1, macOS 15.7.7, 2026-11-08)

### Gradle settings

**Tier: never** · `gradle.keep`

- **Pattern:** `~/.gradle/gradle.properties || ~/.gradle/init.d || ~/.gradle/init.gradle`
- **What it is:** Gradle settings you wrote.
- **If you remove it:** You would lose your own configuration.
- **Condition:** Not offered.
- **Source:** Gradle documentation

### Maven repository

**Tier: review** · `maven.repository`

- **Pattern:** `~/.m2/repository`
- **What it is:** Libraries Maven downloaded, plus any you installed locally.
- **If you remove it:** Downloaded libraries come back from the network, but ones installed only on this Mac are lost.
- **Source:** Measured: removed and rebuilt with Maven 3.9 on macOS 15.7
- **Measured:** One project (Spring PetClinic) filled 217 MB. After deleting it, Maven downloaded the dependencies again and built the project; deleting it freed 213 MB on disk. It stays review because `mvn install` puts your own builds here, which cannot be downloaded again. (3.9, macOS 15.7.7, 2026-11-08)

### Maven settings

**Tier: never** · `maven.keep`

- **Pattern:** `~/.m2/settings.xml || ~/.m2/settings-security.xml`
- **What it is:** Maven settings and credentials.
- **If you remove it:** You would lose your own configuration.
- **Condition:** Not offered.
- **Source:** Research notes (unverified)
- **Evidence:** unverified

### Go modules

**Tier: rebuild** · `go.modcache`

- **Pattern:** `~/go/pkg/mod`
- **What it is:** Go libraries downloaded earlier.
- **If you remove it:** Go will download them again.
- **Condition:** These files are read-only, so use the command.
- **Official command:** `go clean -modcache`
- **Source:** Measured: removed and rebuilt with Go 1.27 on macOS 15.7
- **Measured:** Reached 398 MB of modules for one project (GitHub's gh CLI). `go clean -modcache` emptied it, deleting it freed 403 MB on disk, and the project built again after downloading its modules. (go1.27.3, macOS 15.7.7, 2026-11-08)

### Go build cache

**Tier: rebuild** · `go.buildcache`

- **Pattern:** `~/Library/Caches/go-build`
- **What it is:** Compiled Go packages kept to speed up builds.
- **If you remove it:** The next builds will be slower.
- **Official command:** `go clean -cache`
- **Source:** Measured: removed and rebuilt with Go 1.27 on macOS 15.7
- **Measured:** Reached 633 MB building one project (GitHub's gh CLI). `go clean -cache` emptied it, deleting it freed 622 MB on disk, and the project built again afterwards. (go1.27.3, macOS 15.7.7, 2026-11-08)

### Go tools and sources

**Tier: never** · `go.keep`

- **Pattern:** `~/go/bin || ~/go/src`
- **What it is:** Go tools you installed and sources you keep.
- **If you remove it:** You would lose installed tools or your own code.
- **Condition:** Not offered.
- **Source:** Go documentation

### CocoaPods data

**Tier: rebuild** · `cocoapods.cache`

- **Pattern:** `~/.cocoapods || ~/Library/Caches/CocoaPods`
- **What it is:** Pod specifications and downloaded pods.
- **If you remove it:** CocoaPods will download them again, which is large.
- **Condition:** Check that no project keeps its Pods folder only here.
- **Official command:** `pod cache clean --all`
- **Source:** Research notes (unverified)
- **Evidence:** unverified

### Swift package cache

**Tier: rebuild** · `swiftpm.cache`

- **Pattern:** `~/Library/Caches/org.swift.swiftpm`
- **What it is:** Swift packages downloaded earlier.
- **If you remove it:** They will be fetched again.
- **Official command:** `swift package purge-cache`
- **Source:** Measured: removed and rebuilt with SwiftPM 6.1 on macOS 15.7
- **Measured:** Held 9.6 MB of cloned dependencies for a package with two dependencies. `swift package purge-cache` emptied it, and the package built again afterwards. (Swift 6.1.2, macOS 15.7.7, 2026-11-08)

### Swift build output

**Tier: rebuild** · `swiftpm.build`

- **Pattern:** `**/.build if-sibling:Package.swift`
- **What it is:** Files produced by building a Swift package.
- **If you remove it:** The package will rebuild in full next time.
- **Official command:** `swift package clean`
- **Source:** Measured: removed and rebuilt with SwiftPM 6.1 on macOS 15.7
- **Measured:** A release build of a package with two dependencies left 172 MB in .build; deleting it freed about 160 MB, and the package built again afterwards. (Swift 6.1.2, macOS 15.7.7, 2026-11-08)

### Swift package trust data

**Tier: never** · `swiftpm.security`

- **Pattern:** `~/Library/org.swift.swiftpm/security`
- **What it is:** Records of packages you chose to trust.
- **If you remove it:** You would lose those trust decisions.
- **Condition:** Not offered.
- **Source:** Research notes (unverified)
- **Evidence:** unverified

### Homebrew installed software

**Tier: never** · `homebrew.installed`

- **Pattern:** `/opt/homebrew/Cellar || /opt/homebrew/Caskroom`
- **What it is:** The software Homebrew installed.
- **If you remove it:** Deleting it removes the apps and tools themselves.
- **Condition:** Not offered. The cleanup command removes only outdated versions.
- **Official command:** `brew cleanup`
- **Source:** Homebrew manual
- **Observed:** 15 formulae installed 73 packages with dependencies, taking 1.15 GB in Cellar; 3 casks installed their apps into /Applications and kept 40 KB in Caskroom (Homebrew 7.0, macOS 15.7, 2026-11-08).

### Yarn 1 package cache

**Tier: rebuild** · `yarn.cache`

- **Pattern:** `~/Library/Caches/Yarn`
- **What it is:** Packages Yarn 1 downloaded, kept unpacked so later installs can copy them.
- **If you remove it:** Yarn downloads packages again when you next install.
- **Official command:** `yarn cache clean`
- **Source:** Measured: removed and reinstalled with Yarn 1.22 on macOS 15.7
- **Measured:** Reached 3.0 GB for one project of about 560 packages, five times what npm kept for the same dependencies. `yarn cache clean` emptied it, deleting it freed 2.95 GB of disk, and Yarn installed again afterwards. (1.22.22, macOS 15.7.7, 2026-11-08)

### Yarn package cache

**Tier: rebuild** · `yarn.berry.cache`

- **Pattern:** `~/.yarn/berry/cache`
- **What it is:** Packages Yarn 2 and later downloaded, shared by all your projects.
- **If you remove it:** Yarn downloads packages again when you next install.
- **Official command:** `yarn cache clean --all`
- **Source:** Measured: removed and reinstalled with Yarn 4.9 on macOS 15.7
- **Measured:** Reached 556 MB for one project of about 560 packages. `yarn cache clean --all` emptied it, deleting it freed 492 MB of disk, and Yarn installed again afterwards. (4.9.2, macOS 15.7.7, 2026-11-08)

### Bun package cache

**Tier: rebuild** · `bun.cache`

- **Pattern:** `~/.bun/install/cache`
- **What it is:** Packages Bun downloaded, shared by all your projects.
- **If you remove it:** Bun downloads packages again when you next install, and while your projects keep their node_modules this frees almost no disk space.
- **Official command:** `bun pm cache rm`
- **Source:** Measured: removed and reinstalled with Bun 1.4 on macOS 15.7
- **Measured:** Reached 631 MB for one project of about 560 packages. `bun pm cache rm` emptied it. Deleting it freed no measurable disk space, because Bun on macOS clones files into node_modules, which keep the data. Bun installed again afterwards. (1.4.4, macOS 15.7.7, 2026-11-08)

### nvm downloads

**Tier: safe** · `nvm.cache`

- **Pattern:** `~/.nvm/.cache`
- **What it is:** Node.js archives nvm downloaded to install versions.
- **If you remove it:** Installed Node versions keep working.
- **Official command:** `nvm cache clear`
- **Source:** Measured: nvm 0.40 on macOS 15.7
- **Observed:** Held 30 MB after installing one Node version; `nvm cache clear` emptied it.

### Node versions installed with nvm

**Tier: review** · `nvm.versions`

- **Pattern:** `~/.nvm/versions`
- **What it is:** The Node.js versions nvm installed, with their global packages.
- **If you remove it:** Projects and tools that use a removed version stop working until you install it again.
- **Condition:** Remove versions you no longer use with `nvm uninstall <version>`.
- **Source:** Measured: nvm 0.40 on macOS 15.7
- **Observed:** One Node 26 install took 228 MB.

### Corepack's package manager downloads

**Tier: rebuild** · `corepack.cache`

- **Pattern:** `~/.cache/node/corepack`
- **What it is:** The pnpm and Yarn versions Corepack downloaded for your projects.
- **If you remove it:** Corepack downloads the version a project asks for the next time you use it.
- **Source:** Measured: removed and reran with Corepack on macOS 15.7
- **Measured:** Held 58 MB for pnpm 12 and Yarn 1 and 4. After removal, pnpm and Yarn 4 ran again, and Corepack downloaded 52 MB back. (corepack 0.34, macOS 15.7.7, 2026-11-08)

### Poetry project environments

**Tier: rebuild** · `poetry.virtualenvs`

- **Pattern:** `~/Library/Caches/pypoetry/virtualenvs`
- **What it is:** The virtual environments of your Poetry projects, which Poetry keeps inside its cache folder by default.
- **If you remove it:** Your Poetry projects stop running until you run `poetry install` in each of them.
- **Condition:** These are not caches, even though they sit in ~/Library/Caches.
- **Source:** Measured: removed and reinstalled with Poetry 2.5 on macOS 15.7
- **Measured:** One project with 13 popular packages had a 1.09 GB environment here. Deleting it freed 1,078 MB and the project could no longer import its packages; `poetry install` rebuilt it in 11 seconds and the project worked again. (2.5.1, macOS 15.7.7, 2026-11-08)

### Poetry package cache

**Tier: rebuild** · `poetry.cache`

- **Pattern:** `~/Library/Caches/pypoetry/cache || ~/Library/Caches/pypoetry/artifacts`
- **What it is:** Package metadata and files Poetry downloaded for your projects.
- **If you remove it:** Poetry downloads them again when you next install or update a project.
- **Condition:** `poetry cache clear --all PyPI` freed only 14 of 550 MB in our test.
- **Source:** Measured: removed and reinstalled with Poetry 2.5 on macOS 15.7
- **Measured:** Reached 550 MB (282 MB cache, 268 MB artifacts) for one project with 13 popular packages. After deleting both, Poetry still worked and rebuilt a project environment by downloading again. (2.5.1, macOS 15.7.7, 2026-11-08)

### Python versions installed by uv

**Tier: review** · `uv.pythons`

- **Pattern:** `~/.local/share/uv/python`
- **What it is:** Python interpreters uv downloaded for your projects and tools.
- **If you remove it:** Environments built on a removed Python stop working until uv installs it again.
- **Condition:** Remove versions you no longer use with `uv python uninstall <version>`.
- **Source:** Measured: uv 0.13 on macOS 15.7
- **Observed:** One Python 3.12 took 72 MB.

### Tools installed with uv

**Tier: review** · `uv.tools`

- **Pattern:** `~/.local/share/uv/tools`
- **What it is:** Command-line tools installed with `uv tool install`, each in its own environment.
- **If you remove it:** The tools stop working until you install them again.
- **Condition:** Remove tools with `uv tool uninstall <name>`.
- **Source:** Measured: uv 0.13 on macOS 15.7
- **Observed:** Poetry and pipx installed as uv tools took 49 MB.

### Rust toolchains

**Tier: review** · `rustup.toolchains`

- **Pattern:** `~/.rustup/toolchains`
- **What it is:** The Rust compilers and standard libraries rustup installed.
- **If you remove it:** Rust projects that use a removed toolchain stop building until rustup installs it again.
- **Condition:** Remove toolchains you no longer use with `rustup toolchain uninstall <name>`.
- **Source:** Measured: rustup 1.29 on macOS 15.7
- **Observed:** The stable toolchain with the default profile took 1.4 GB.

### Tool versions installed by mise

**Tier: review** · `mise.installs`

- **Pattern:** `~/.local/share/mise/installs`
- **What it is:** The language and tool versions mise installed, such as Node and Python.
- **If you remove it:** Projects that use a removed version stop working until mise installs it again.
- **Condition:** `mise prune` removes versions no project or global setting uses.
- **Source:** Measured: mise 2026.11.4 on macOS 15.7
- **Observed:** Node 22 and Python 3.12 took 259 MB; `mise prune` found nothing to remove while both were in use.

### mise downloads

**Tier: safe** · `mise.cache`

- **Pattern:** `~/Library/Caches/mise`
- **What it is:** Archives and metadata mise downloaded while installing tools.
- **If you remove it:** Installed tools keep working.
- **Official command:** `mise cache clear`
- **Source:** Measured: mise 2026.11.4 on macOS 15.7
- **Observed:** Held 74 MB after installing Node and Python; `mise cache clear` emptied it.

### Tool versions installed by asdf

**Tier: review** · `asdf.installs`

- **Pattern:** `~/.asdf/installs`
- **What it is:** The language and tool versions asdf installed.
- **If you remove it:** Projects that use a removed version stop working until asdf installs it again.
- **Condition:** Remove versions you no longer use with `asdf uninstall <tool> <version>`.
- **Source:** Measured: asdf v0.20.2 (revision cb72590) on macOS 15.7
- **Observed:** Node 20 took 158 MB, and its plugin 11 MB; asdf removed its downloads after installing.

### SDKMAN downloads

**Tier: safe** · `sdkman.archives`

- **Pattern:** `~/.sdkman/tmp || ~/.sdkman/archives`
- **What it is:** Archives SDKMAN downloaded to install JDKs and tools, kept after installing.
- **If you remove it:** Installed JDKs and tools keep working.
- **Official command:** `sdk flush`
- **Source:** Measured: SDKMAN on macOS 15.7
- **Observed:** Held 304 MB after installing a JDK, Gradle and Maven; `sdk flush` freed 297 MB, and the JDK and Maven kept working.

### JDKs and tools installed by SDKMAN

**Tier: review** · `sdkman.candidates`

- **Pattern:** `~/.sdkman/candidates`
- **What it is:** The JDKs, Gradle, Maven and other tools SDKMAN installed.
- **If you remove it:** Projects and tools that use a removed version stop working until SDKMAN installs it again.
- **Condition:** Remove versions you no longer use with `sdk uninstall <tool> <version>`.
- **Source:** Measured: SDKMAN on macOS 15.7
- **Observed:** A JDK 25, Gradle and Maven took 463 MB. SDKMAN needs Bash 4 or later, which macOS does not include.

### rbenv Ruby versions

**Tier: review** · `rbenv.versions`

- **Pattern:** `~/.rbenv/versions`
- **What it is:** Ruby versions rbenv built, each with the gems installed into it.
- **If you remove it:** Projects that use a removed version stop working until rbenv builds it again and their gems are reinstalled.
- **Source:** Measured: built Ruby 3.4.12 with rbenv 1.3.2 on macOS 15.7
- **Observed:** Ruby 3.4.12 took 115 MB once built. After bundling a Rails 8 app's gems into it the folder was 268 MB, about 30 MB of which was the downloaded .gem files in its gem cache.

### RVM Ruby versions and gems

**Tier: review** · `rvm.rubies`

- **Pattern:** `~/.rvm/rubies || ~/.rvm/gems`
- **What it is:** Ruby versions RVM installed, and the gems installed for each of them.
- **If you remove it:** Projects that use a removed version stop working until RVM installs it again and their gems are reinstalled.
- **Source:** Measured: built Ruby 3.4.12 with RVM 1.29.12-next on macOS 15.7
- **Observed:** Ruby 3.4.12 took 52 MB in rubies, and a Rails 8 app's gems took 153 MB in gems.

### RVM sources and archives

**Tier: safe** · `rvm.sources`

- **Pattern:** `~/.rvm/src || ~/.rvm/archives`
- **What it is:** Source code and downloaded archives RVM keeps after building Ruby.
- **If you remove it:** Installed Rubies and gems keep working, but installing a version again downloads its source again.
- **Official command:** `rvm cleanup all`
- **Source:** Measured: rvm cleanup all, then bundled again with RVM 1.29.12-next on macOS 15.7
- **Measured:** After building Ruby 3.4.12 the folders held 283 MB of source and 23 MB of archives. rvm cleanup all removed both, and Bundler then installed the app's gems with that Ruby as before. (rvm 1.29.12-next (master branch), macOS 15.7.7, 2026-11-08)

### Downloaded gem files

**Tier: rebuild** · `ruby.gem-cache`

- **Pattern:** `**/cache if-sibling:specifications`
- **What it is:** The .gem files RubyGems keeps after installing each gem.
- **If you remove it:** Installed gems keep working, but reinstalling or repairing a gem downloads it again.
- **Source:** Measured: removed with Ruby 3.4.12 from rbenv, RVM and mise on macOS 15.7
- **Measured:** With a Rails 8 app's gems installed, the gem caches held 30 MB under rbenv and 27 MB under RVM. Deleting the .gem files freed that space, bundle install downloaded nothing, and the app still loaded Rails. (Ruby 3.4.12, RubyGems and Bundler as bundled with it, macOS 15.7.7, 2026-11-08)

### Bundler's gem index

**Tier: rebuild** · `bundler.cache`

- **Pattern:** `~/.bundle/cache`
- **What it is:** Bundler's copy of the rubygems.org gem index, which it uses to choose gem versions.
- **If you remove it:** The next bundle install downloads the index again.
- **Source:** Measured: removed and bundled again with Ruby 3.4.12 on macOS 15.7
- **Measured:** After bundling one Rails 8 app it held 776 files and 30 MB. It was removed and came back at the same size on the next bundle install. (Bundler as bundled with Ruby 3.4.12, macOS 15.7.7, 2026-11-08)

### Gems vendored in a project

**Tier: rebuild** · `bundler.vendor`

- **Pattern:** `**/vendor/bundle/ruby`
- **What it is:** Gems Bundler installed inside a project whose bundle path is vendor/bundle.
- **If you remove it:** The project stops running until you run bundle install again, with network access.
- **Source:** Measured: removed and bundled again with Ruby 3.4.12 from mise on macOS 15.7
- **Measured:** A Rails 8 app's gems took 178 MB. After removal, bundle install put them back and the app loaded nokogiri again. (mise 2026.11.4, Ruby 3.4.12, macOS 15.7.7, 2026-11-08)

### Homebrew itself

**Tier: never** · `homebrew.program`

- **Pattern:** `/opt/homebrew/Library`
- **What it is:** Homebrew's own code, its formula lists, and the Ruby and gems it runs on.
- **If you remove it:** brew stops working.
- **Condition:** Use brew cleanup and brew uninstall instead.
- **Source:** Measured: folder contents listed after installing Homebrew on macOS 15.7
- **Observed:** The folder held Homebrew's own portable Ruby and a vendor/bundle of gems, which the generic gem-cache and vendor/bundle rules would otherwise match.

## Logs, Trash, downloads and personal data

Logs, the Trash, installers, and data that belongs to you.


### Trash

**Tier: review** · `trash`

- **Pattern:** `~/.Trash || /Volumes/*/.Trashes`
- **What it is:** Items you already moved to the Trash.
- **If you remove it:** They would be deleted for good.
- **Condition:** Use Empty Trash in Finder. The Trash frees nothing until it is emptied.
- **Source:** Apple Support

### Logs

**Tier: safe** · `logs`

- **Pattern:** `~/Library/Logs/*`
- **What it is:** Records apps and the system wrote about what they did.
- **If you remove it:** You would lose logs that help diagnose a past crash.
- **Condition:** Skip files changed in the last hour.
- **Source:** Apple Support

### Logs macOS writes

**Tier: never** · `logs.apple`

- **Pattern:** `~/Library/Logs/com.apple.*|DiagnosticReports`
- **What it is:** Logs and crash reports that macOS writes for you.
- **If you remove it:** macOS manages these, so they are not offered for removal.
- **Source:** Policy choice

### Downloaded installers

**Tier: review** · `downloads.installers`

- **Pattern:** `~/Downloads/*.dmg|*.pkg|*.iso|*.zip`
- **What it is:** Installers and archives you downloaded.
- **If you remove it:** If this is your only copy, such as licensed software or an old version, it is gone for good.
- **Condition:** Move to Trash only. Whether the app is already installed is a guess.
- **Source:** Research notes (unverified)
- **Evidence:** unverified

### Mail attachment copies

**Tier: rebuild** · `mail.downloads`

- **Pattern:** `~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads`
- **What it is:** Copies of attachments you opened from Mail.
- **If you remove it:** Only the copies go; the originals stay in the messages.
- **Condition:** Close Mail first.
- **Owning app:** `com.apple.mail`
- **Source:** Third-party guides
- **Evidence:** unverified

### Mail data

**Tier: never** · `mail.store`

- **Pattern:** `~/Library/Mail`
- **What it is:** Your mailboxes, messages and attachments.
- **If you remove it:** Manual deletion can corrupt Mail, and some messages may exist nowhere else.
- **Condition:** Use Mail itself.
- **Owning app:** `com.apple.mail`
- **Source:** Third-party guides
- **Evidence:** unverified

### Messages data

**Tier: never** · `messages.data`

- **Pattern:** `~/Library/Messages/Attachments || ~/Library/Messages/chat.db*`
- **What it is:** Your message history and attachments.
- **If you remove it:** Manual deletion can corrupt your history, and it may be the only copy.
- **Condition:** Use the Messages app settings.
- **Owning app:** `com.apple.MobileSMS`
- **Source:** Third-party guides
- **Evidence:** unverified

### Photos library

**Tier: never** · `photos.library`

- **Pattern:** `~/Pictures/*.photoslibrary || ~/Library/Containers/com.apple.photolibraryd || ~/Library/Photos`
- **What it is:** Your photo library and its service data.
- **If you remove it:** Changes inside it can corrupt the library, and the originals may be the only copies.
- **Condition:** Free space from within Photos instead.
- **Owning app:** `com.apple.Photos`
- **Source:** Apple Support

### Embedded browser cache

**Tier: rebuild** · `chromium.caches`

- **Pattern:** `~/Library/Application Support/**/GPUCache || ~/Library/Application Support/**/Code Cache || ~/Library/Application Support/**/Service Worker/CacheStorage`
- **What it is:** A cache kept by an app that embeds a web browser.
- **If you remove it:** It rebuilds on its own, though some web apps keep offline-only data in the service worker cache.
- **Condition:** Close the app first. IndexedDB, Local Storage and Cookies are not caches.
- **Source:** Research notes (unverified)
- **Evidence:** unverified

## Measured app rules

Rules for one app's folders, from [`rules/90-apps.json`](https://github.com/midhunkrishna/deepyellow/blob/master/rules/90-apps.json). Each was measured in a macOS virtual machine: the app was used, quit, the folder moved to the Trash, and the app relaunched to see what came back and whether it stayed signed in. The **Measured** line records what was seen.


### Slack's web cache

**Tier: rebuild** · `slack.cache`

- **Pattern:** `~/Library/Application Support/Slack/Cache`
- **What it is:** Images, files and pages Slack downloaded so it can show them again without fetching them.
- **If you remove it:** Slack downloads them again as you open them, and you stay signed in.
- **Condition:** Quit Slack first.
- **Owning app:** `com.tinyspeck.slackmacgap`
- **Source:** Measured: removed and relaunched Slack 4.53 on macOS 15.7
- **Measured:** Reached 55 MB after about 2 hours of use and grew by about 1 MB a minute while reading channels. After removal Slack relaunched signed in; the folder came back at 0.5 MB and reached 2.5 MB after 5 channels. (Slack 4.53.280, macOS 15.7.7, 2026-11-08)

### Slack's logs

**Tier: safe** · `slack.logs`

- **Pattern:** `~/Library/Application Support/Slack/logs`
- **What it is:** Text logs Slack writes while it runs, used to troubleshoot problems.
- **If you remove it:** Slack starts new logs and you stay signed in.
- **Condition:** Quit Slack first.
- **Owning app:** `com.tinyspeck.slackmacgap`
- **Source:** Measured: removed and relaunched Slack 4.53 on macOS 15.7
- **Measured:** Three log files reached 6.5 MB after about 2 hours of use, 2.1 MB of it in 6 minutes of switching channels, with no rotated copies. After removal Slack relaunched signed in and wrote 0.4 MB of new logs. (Slack 4.53.280, macOS 15.7.7, 2026-11-08)

### Slack's offline app copy

**Tier: review** · `slack.service-worker`

- **Pattern:** `~/Library/Application Support/Slack/Service Worker || ~/Library/Application Support/Slack/Service Worker/CacheStorage`
- **What it is:** A copy of Slack's web app that Slack downloads after you sign in, so it can start without the network.
- **If you remove it:** Slack downloads it again as soon as it starts, so the space is taken again within a minute.
- **Owning app:** `com.tinyspeck.slackmacgap`
- **Source:** Measured: removed and relaunched Slack 4.53 on macOS 15.7
- **Measured:** Appeared at 83 MB right after sign-in and stayed at that size through further use. After removal Slack relaunched signed in and the folder was back at 83 MB within 25 seconds. (Slack 4.53.280, macOS 15.7.7, 2026-11-08)

### Safari's web cache

**Tier: rebuild** · `safari.cache`

- **Pattern:** `~/Library/Containers/com.apple.Safari/Data/Library/Caches/com.apple.Safari`
- **What it is:** Pages, images and video Safari downloaded so it can show them again without fetching them.
- **If you remove it:** Safari downloads them again as you browse, and your history and bookmarks stay.
- **Condition:** Quit Safari first.
- **Owning app:** `com.apple.Safari`
- **Source:** Measured: removed and relaunched Safari 18.6 on macOS 15.7
- **Measured:** Reached 552 MB after 60 page views of 30 public sites in 13 minutes. After removal Safari relaunched normally with its history file unchanged; the folder came back at 0.1 MB and reached 74 MB after 8 pages. (Safari 18.6, macOS 15.7.7, 2026-11-08)

### What websites store in Safari

**Tier: review** · `safari.website-data`

- **Pattern:** `~/Library/Containers/com.apple.Safari/Data/Library/WebKit/WebsiteData`
- **What it is:** Data websites keep in Safari, such as saved settings, offline copies and site databases.
- **If you remove it:** Websites lose what they stored on this Mac, such as settings and offline data.
- **Condition:** Quit Safari first.
- **Owning app:** `com.apple.Safari`
- **Source:** Measured: removed and relaunched Safari 18.6 on macOS 15.7
- **Measured:** Reached 42 MB after 60 page views without signing in to any site. After removal Safari relaunched normally; the folder came back at 0.7 MB and reached 12 MB after 8 pages. Sign-ins to websites were not tested. (Safari 18.6, macOS 15.7.7, 2026-11-08)

### Safari's history and tabs

**Tier: never** · `safari.profile`

- **Pattern:** `~/Library/Safari || ~/Library/Containers/com.apple.Safari/Data/Library/Safari`
- **What it is:** Safari's browsing history, open tabs, per-site settings and AutoFill data.
- **If you remove it:** It deletes your browsing history, tabs and site settings.
- **Owning app:** `com.apple.Safari`
- **Source:** Measured: folder contents listed in Safari 18.6 on macOS 15.7
- **Observed:** Holds History.db, SafariTabs.db, PerSitePreferences.db and AutoFill databases; 36 MB after 60 page views, 12 MB of it AutoFill corrections.

### Chrome's downloaded components

**Tier: review** · `chrome.components`

- **Pattern:** `~/Library/Application Support/Google/Chrome/component_crx_cache || ~/Library/Application Support/Google/Chrome/optimization_guide_model_store || ~/Library/Application Support/Google/Chrome/WasmTtsEngine || ~/Library/Application Support/Google/Chrome/Safe Browsing || ~/Library/Application Support/Google/Chrome/OnDeviceHeadSuggestModel`
- **What it is:** Models, voices and lists Chrome downloads in the background for features such as Safe Browsing, read aloud and search suggestions.
- **If you remove it:** Chrome downloads them again within minutes, so the space is taken again.
- **Owning app:** `com.google.Chrome`
- **Source:** Measured: removed and relaunched Chrome 157 on macOS 15.7
- **Measured:** Took 147 MB after the first launch and 60 page views. After removal Chrome relaunched normally and downloaded 132 MB of it again within 6 minutes. (Chrome 157.0.8103.39, macOS 15.7.7, 2026-11-08)

### Spotify's streaming cache

**Tier: rebuild** · `spotify.cache`

- **Pattern:** `~/Library/Caches/com.spotify.client`
- **What it is:** Songs Spotify streamed, kept so they play again without downloading, plus the cache of its built-in browser.
- **If you remove it:** Spotify streams songs again as you play them, and you stay signed in.
- **Condition:** Quit Spotify first.
- **Owning app:** `com.spotify.client`
- **Source:** Measured: removed and relaunched Spotify 1.3.8 on macOS 15.7
- **Measured:** Reached 334 MB after 40 tracks in 14 minutes, 240 MB of it streamed audio. After removal Spotify relaunched signed in; the folder came back at 57 MB and reached 248 MB after 6 more tracks. (Spotify 1.3.8.620, macOS 15.7.7, 2026-11-08)

### Spotify's account database

**Tier: review** · `spotify.account-data`

- **Pattern:** `~/Library/Application Support/Spotify/PersistentCache`
- **What it is:** A database Spotify keeps for each signed-in account.
- **If you remove it:** Spotify rebuilds it and you stay signed in, though it forgot what was playing.
- **Condition:** Quit Spotify first.
- **Owning app:** `com.spotify.client`
- **Source:** Measured: removed and relaunched Spotify 1.3.8 on macOS 15.7
- **Measured:** Reached 28 MB after 40 tracks on a free account. After removal Spotify relaunched signed in with nothing queued; the folder came back at 8 MB and reached 10 MB after 6 tracks. Songs downloaded for offline listening (Premium) were not tested. (Spotify 1.3.8.620, macOS 15.7.7, 2026-11-08)

### VS Code's extension installer cache

**Tier: safe** · `vscode.extension-installers`

- **Pattern:** `~/Library/Application Support/Code/CachedExtensionVSIXs`
- **What it is:** Copies of the installer files of extensions VS Code has installed.
- **If you remove it:** Your extensions stay installed and keep working.
- **Condition:** Quit VS Code first.
- **Owning app:** `com.microsoft.VSCode`
- **Source:** Measured: removed and relaunched VS Code 1.145 on macOS 15.7
- **Measured:** Reached 174 MB after installing 6 extensions (9 with their dependencies). After removal VS Code relaunched with all 9 extensions installed, and the folder stayed empty after opening a project. (VS 1.145.2, macOS 15.7.7, 2026-11-08)

### VS Code's compiled code cache

**Tier: rebuild** · `vscode.compiled-code`

- **Pattern:** `~/Library/Application Support/Code/CachedData`
- **What it is:** JavaScript that VS Code and its extensions compiled, kept so later starts are faster.
- **If you remove it:** VS Code compiles it again on its next start, which makes that start slower.
- **Condition:** Quit VS Code first.
- **Owning app:** `com.microsoft.VSCode`
- **Source:** Measured: removed and relaunched VS Code 1.145 on macOS 15.7
- **Measured:** Was 15 MB after the first launch. After removal VS Code relaunched normally and rebuilt it at 86 MB right away, now including the installed extensions. (VS 1.145.2, macOS 15.7.7, 2026-11-08)

### VS Code's logs

**Tier: safe** · `vscode.logs`

- **Pattern:** `~/Library/Application Support/Code/logs`
- **What it is:** Text logs VS Code and its extensions write while they run, used to troubleshoot problems.
- **If you remove it:** VS Code starts new logs, and your settings and extensions stay.
- **Condition:** Quit VS Code first.
- **Owning app:** `com.microsoft.VSCode`
- **Source:** Measured: removed and relaunched VS Code 1.145 on macOS 15.7
- **Measured:** Reached 1.1 MB after opening 5 projects. After removal VS Code relaunched normally and wrote 0.2 MB of new logs. (VS 1.145.2, macOS 15.7.7, 2026-11-08)

### VS Code extensions

**Tier: never** · `vscode.extensions`

- **Pattern:** `~/.vscode/extensions`
- **What it is:** The extensions installed in VS Code, including the language tools and libraries they bundle.
- **If you remove it:** Removing files inside breaks the extensions that own them.
- **Condition:** Uninstall extensions from the Extensions view in VS Code instead.
- **Owning app:** `com.microsoft.VSCode`
- **Source:** Measured: folder contents listed in VS Code 1.145 on macOS 15.7
- **Observed:** 6 extensions took 528 MB, 274 MB of it the C/C++ extension. Generic rules matched folders inside them, such as a node_modules bundled with Prettier, where removal would break the extension.

### Zoom's downloaded components

**Tier: review** · `zoom.components`

- **Pattern:** `~/Library/Application Support/zoom.us/asr || ~/Library/Application Support/zoom.us/CefPlugin`
- **What it is:** Speech recognition models for captions and an embedded web engine that Zoom downloads in the background.
- **If you remove it:** Zoom downloads them again as soon as it starts, so the space is taken again within minutes.
- **Owning app:** `us.zoom.xos`
- **Source:** Measured: removed and relaunched Zoom 7.2.5 on macOS 15.7
- **Measured:** Took 498 MB after one session with captions: 217 MB of speech models and 281 MB of web engine. After removal Zoom relaunched signed in and downloaded 464 MB of it again within 90 seconds. On a Mac used for months the speech models were 407 MB, all downloaded in the same month. (Zoom 7.2.5 (90525), macOS 15.7.7, 2026-11-08)

### Zoom's program files

**Tier: never** · `zoom.app-code`

- **Pattern:** `~/Library/Application Support/zoom.us/Plugins`
- **What it is:** Part of the Zoom app itself, unpacked here on first launch and extended with downloaded features.
- **If you remove it:** Zoom puts the files back the next time it starts, so no space stays free.
- **Condition:** Uninstall Zoom to remove it.
- **Owning app:** `us.zoom.xos`
- **Source:** Measured: removed and relaunched Zoom 7.2.5 on macOS 15.7
- **Measured:** First launch unpacked 148 MB here and it reached 276 MB. After removal Zoom relaunched signed in and had put back 196 MB within 90 seconds. (Zoom 7.2.5 (90525), macOS 15.7.7, 2026-11-08)

### Zoom's account data

**Tier: review** · `zoom.account-data`

- **Pattern:** `~/Library/Application Support/zoom.us/data`
- **What it is:** Zoom's databases for the signed-in account, meetings and settings.
- **If you remove it:** Zoom signs you out and starts as if it were newly installed.
- **Condition:** Quit Zoom first.
- **Owning app:** `us.zoom.xos`
- **Source:** Measured: removed and relaunched Zoom 7.2.5 on macOS 15.7
- **Measured:** Reached 189 MB after one session, and 260 MB on a Mac used for months. After removal Zoom relaunched signed out, showing its first-run screen, and the folder came back at 2.3 MB. (Zoom 7.2.5 (90525), macOS 15.7.7, 2026-11-08)

### Teams' web cache

**Tier: rebuild** · `teams.cache`

- **Pattern:** `~/Library/Containers/com.microsoft.teams2/Data/Library/Caches/Microsoft/MSTeams`
- **What it is:** Images, files and pages Teams downloaded so it can show them again without fetching them.
- **If you remove it:** Teams downloads them again as you open them, and you stay signed in.
- **Condition:** Quit Teams first.
- **Owning app:** `com.microsoft.teams2`
- **Source:** Measured: removed and relaunched Teams 26289 on macOS 15.7
- **Measured:** Reached 85 MB after sign-in and 10 minutes of use with a personal account. After removal Teams relaunched signed in and the folder came back at 2.4 MB. (Teams 26289.204.5281.6363, macOS 15.7.7, 2026-11-08)

### Teams' offline app copy

**Tier: review** · `teams.service-worker`

- **Pattern:** `~/Library/Containers/com.microsoft.teams2/Data/Library/Application Support/Microsoft/MSTeams/EBWebView/WV2Profile_*/Service Worker`
- **What it is:** A copy of the Teams web app that Teams downloads after you sign in, so it can start quickly and without the network.
- **If you remove it:** Teams downloads it again as soon as it starts, so the space is taken again within a minute.
- **Owning app:** `com.microsoft.teams2`
- **Source:** Measured: removed and relaunched Teams 26289 on macOS 15.7
- **Measured:** Was 387 MB right after signing in with a personal account. After removal Teams relaunched signed in and the folder was back at 408 MB within 60 seconds. Work and school accounts were not tested. (Teams 26289.204.5281.6363, macOS 15.7.7, 2026-11-08)

### Teams' logs

**Tier: safe** · `teams.logs`

- **Pattern:** `~/Library/Group Containers/UBF8T346G9.com.microsoft.teams/Library/Application Support/Logs`
- **What it is:** Text logs Teams writes while it runs, used to troubleshoot problems.
- **If you remove it:** Teams starts new logs and you stay signed in.
- **Condition:** Quit Teams first.
- **Owning app:** `com.microsoft.teams2`
- **Source:** Measured: removed and relaunched Teams 26289 on macOS 15.7
- **Measured:** Reached 6 MB after sign-in and 10 minutes of use. After removal Teams relaunched signed in and wrote 3.7 MB of new logs within a minute. (Teams 26289.204.5281.6363, macOS 15.7.7, 2026-11-08)

### Teams' app data

**Tier: review** · `teams.data`

- **Pattern:** `~/Library/Containers/com.microsoft.teams2`
- **What it is:** Everything Teams keeps for your account on this Mac: chats, settings, the offline app copy and caches.
- **If you remove it:** Teams signs you out and downloads everything again after you sign back in.
- **Condition:** Quit Teams first.
- **Owning app:** `com.microsoft.teams2`
- **Source:** Measured: removed and relaunched Teams 26289 on macOS 15.7
- **Measured:** Was 540 MB after sign-in and 10 minutes of use. After removing it and the shared Teams group container, Teams relaunched signed out, offering the remembered account, and the folder came back at 28 MB. (Teams 26289.204.5281.6363, macOS 15.7.7, 2026-11-08)

### Discord's web cache

**Tier: rebuild** · `discord.cache`

- **Pattern:** `~/Library/Application Support/discord/Cache`
- **What it is:** Images, GIFs and pages Discord downloaded so it can show them again without fetching them.
- **If you remove it:** Discord downloads them again as you open channels, and you stay signed in.
- **Condition:** Quit Discord first.
- **Owning app:** `com.hnc.Discord`
- **Source:** Measured: removed and relaunched Discord 0.0.421 on macOS 15.7
- **Measured:** Reached 29 MB after sign-in and 10 minutes in a public community, growing by 18 MB during that use. After removal Discord relaunched signed in and the folder came back at 17 MB within a minute. (Discord 0.0.421, macOS 15.7.7, 2026-11-08)

### Discord's program modules

**Tier: never** · `discord.app-code`

- **Pattern:** `~/Library/Application Support/discord/app-*`
- **What it is:** Part of the Discord app itself, such as voice and noise suppression, downloaded on first launch.
- **If you remove it:** Discord stops starting with a fatal error, and does not download the files again.
- **Condition:** Uninstall Discord to remove it.
- **Owning app:** `com.hnc.Discord`
- **Source:** Measured: removed and relaunched Discord 0.0.421 on macOS 15.7
- **Measured:** Took 224 MB after first launch and use, including a 111 MB voice module. After removal Discord showed 'Cannot find module discord_desktop_core' on two launches in a row; putting the folder back from the Trash fixed it, still signed in. (Discord 0.0.421, macOS 15.7.7, 2026-11-08)

## Summary

102 rules in total: 10 safe, 39 rebuild, 30 review, 23 never.
