# Reclaim rules

Every built-in rule DeepYellow uses to advise on a place on disk. This page is generated from the rule table in [`BuiltinRules.swift`](https://github.com/midhunkrishna/deepyellow/blob/master/Packages/DYAdvisor/Sources/DYAdvisor/BuiltinRules.swift), so it lists exactly what the app contains.

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
- **What it is:** Installer files Homebrew downloaded earlier.
- **If you remove it:** Homebrew will download a package again if you reinstall it.
- **Condition:** Use the command, not manual deletion. Add -n for a dry run.
- **Official command:** `brew cleanup`
- **Source:** Homebrew manual

### JetBrains IDE data

**Tier: review** · `caches.jetbrains`

- **Pattern:** `~/Library/Caches/JetBrains/*`
- **What it is:** Indexes, caches and logs for a JetBrains IDE, including its Local History.
- **If you remove it:** Indexes rebuild slowly, and Local History (your edit history outside version control) cannot be recovered.
- **Condition:** Close the IDE first. Never offer this as one blob.
- **Source:** Research notes (unverified)

### Spotify offline songs

**Tier: rebuild** · `caches.spotify`

- **Pattern:** `~/Library/Caches/com.spotify.client/Storage`
- **What it is:** Songs Spotify saved for offline listening.
- **If you remove it:** You will need to download the songs again, with network access and your account.
- **Condition:** Close Spotify first.
- **Owning app:** `com.spotify.client`
- **Source:** Research notes (unverified)

### Xcode cache

**Tier: rebuild** · `caches.xcode`

- **Pattern:** `~/Library/Caches/com.apple.dt.Xcode`
- **What it is:** Cached data that Xcode uses for indexing.
- **If you remove it:** Xcode will re-index and fetch some information again.
- **Condition:** Close Xcode first.
- **Owning app:** `com.apple.dt.Xcode`
- **Source:** Research notes (unverified)

### Chrome cache

**Tier: rebuild** · `caches.chrome`

- **Pattern:** `~/Library/Caches/Google/Chrome`
- **What it is:** Web pages and images Chrome saved to load sites faster.
- **If you remove it:** Pages load more slowly the first time you visit them again; your logins are not stored here.
- **Condition:** Close the browser first.
- **Owning app:** `com.google.Chrome`
- **Source:** Research notes (unverified)

### Firefox cache

**Tier: rebuild** · `caches.firefox`

- **Pattern:** `~/Library/Caches/Firefox/Profiles/*/cache2`
- **What it is:** Web pages and images Firefox saved to load sites faster.
- **If you remove it:** Pages load more slowly the first time you visit them again; your logins are not stored here.
- **Condition:** Close the browser first.
- **Owning app:** `org.mozilla.firefox`
- **Source:** Research notes (unverified)

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

### Xcode archives

**Tier: review** · `xcode.archives`

- **Pattern:** `~/Library/Developer/Xcode/Archives`
- **What it is:** Saved builds of apps you shipped, with their debugging symbols.
- **If you remove it:** You would lose the ability to read crash reports for those builds or re-export them.
- **Condition:** Review each archive by date and version. Move to Trash only.
- **Source:** Third-party guides

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

### OS update area

**Tier: never** · `system.osupdate`

- **Pattern:** `/Library/Updates || /System/Library/AssetsV2 || /System/Library/Assets`
- **What it is:** Files macOS uses to stage and apply updates.
- **If you remove it:** Removing them could interfere with system updates.
- **Condition:** Manage only through System Settings.
- **Source:** Research notes (unverified)

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

- **Pattern:** `/var/log || /private/var/log || /var/db/diagnostics || /private/var/db/diagnostics`
- **What it is:** System logs and diagnostics.
- **If you remove it:** They are needed by the system and are not offered for removal.
- **Source:** Research notes

### App language files

**Tier: never** · `system.lproj`

- **Pattern:** `/Applications/*.app/Contents/Resources/*.lproj`
- **What it is:** Language files inside an installed app.
- **If you remove it:** Removing them may invalidate the app's signature so it will not open.
- **Condition:** Not offered.
- **Source:** Eclectic Light Company

## Package managers and build output

Language caches, dependencies and build folders.


### JavaScript dependencies

**Tier: rebuild** · `node.modules`

- **Pattern:** `**/node_modules if-sibling:package-lock.json|npm-shrinkwrap.json|yarn.lock|pnpm-lock.yaml`
- **What it is:** Libraries a JavaScript project installed.
- **If you remove it:** You will need to run the install again, with network access, and any local patches are lost.
- **Condition:** Offered because a lockfile sits next to it.
- **Source:** Research notes (unverified)

### JavaScript dependencies without a lockfile

**Tier: review** · `node.modules.nolock`

- **Pattern:** `**/node_modules`
- **What it is:** Libraries a JavaScript project installed, with no lockfile beside them.
- **If you remove it:** Without a lockfile the same versions may not come back, and local patches are lost.
- **Source:** Research notes (unverified)

### Yarn committed cache

**Tier: never** · `yarn.zeroinstall`

- **Pattern:** `**/.yarn/cache`
- **What it is:** A Yarn cache that some projects keep in version control as their dependency source.
- **If you remove it:** The project may be unable to install its dependencies.
- **Condition:** Not offered.
- **Source:** Research notes (unverified)

### npm download cache

**Tier: rebuild** · `npm.cache`

- **Pattern:** `~/.npm`
- **What it is:** Packages npm downloaded earlier.
- **If you remove it:** npm will download them again when needed.
- **Official command:** `npm cache clean --force`
- **Source:** Research notes (unverified)

### pnpm package store

**Tier: rebuild** · `pnpm.store`

- **Pattern:** `~/Library/pnpm/store || ~/.local/share/pnpm/store`
- **What it is:** The shared store that pnpm links project dependencies from.
- **If you remove it:** Packages will be downloaded again when needed.
- **Condition:** Use the command, which removes only unreferenced packages. Do not delete by hand.
- **Official command:** `pnpm store prune`
- **Source:** pnpm documentation

### pip cache

**Tier: rebuild** · `pip.cache`

- **Pattern:** `~/Library/Caches/pip || ~/.cache/pip`
- **What it is:** Python packages pip downloaded earlier.
- **If you remove it:** pip will download or rebuild them when needed.
- **Official command:** `pip cache purge`
- **Source:** Research notes (unverified)

### uv cache

**Tier: rebuild** · `uv.cache`

- **Pattern:** `~/.cache/uv`
- **What it is:** Python packages uv downloaded earlier.
- **If you remove it:** uv will download or rebuild them when needed.
- **Condition:** Do not touch it while uv is running.
- **Official command:** `uv cache clean`
- **Source:** uv documentation

### conda packages

**Tier: rebuild** · `conda.pkgs`

- **Pattern:** `~/miniconda3/pkgs || ~/anaconda3/pkgs || ~/miniforge3/pkgs`
- **What it is:** Package files shared by your conda environments.
- **If you remove it:** Only unused packages should be removed, and conda will download them again if needed.
- **Condition:** Use the command, never delete by hand.
- **Official command:** `conda clean --all`
- **Source:** Research notes (unverified)

### conda environments

**Tier: review** · `conda.envs`

- **Pattern:** `~/miniconda3/envs/* || ~/anaconda3/envs/* || ~/miniforge3/envs/*`
- **What it is:** Python environments you created.
- **If you remove it:** You would lose the environment and its installed packages.
- **Source:** Research notes (unverified)

### Cargo downloads

**Tier: rebuild** · `cargo.cache`

- **Pattern:** `~/.cargo/registry || ~/.cargo/git`
- **What it is:** Rust libraries Cargo downloaded earlier.
- **If you remove it:** Cargo will download them again, which needs the network.
- **Source:** Cargo documentation

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
- **Source:** Research notes (unverified)

### Gradle downloads

**Tier: rebuild** · `gradle.cache`

- **Pattern:** `~/.gradle/caches || ~/.gradle/wrapper/dists || ~/.gradle/daemon`
- **What it is:** Libraries and tools Gradle downloaded earlier.
- **If you remove it:** Gradle will download them again and the next build will be slower.
- **Condition:** Not while a Gradle daemon is running.
- **Source:** Gradle documentation

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
- **Source:** Research notes (unverified)

### Maven settings

**Tier: never** · `maven.keep`

- **Pattern:** `~/.m2/settings.xml || ~/.m2/settings-security.xml`
- **What it is:** Maven settings and credentials.
- **If you remove it:** You would lose your own configuration.
- **Condition:** Not offered.
- **Source:** Research notes (unverified)

### Go modules

**Tier: rebuild** · `go.modcache`

- **Pattern:** `~/go/pkg/mod`
- **What it is:** Go libraries downloaded earlier.
- **If you remove it:** Go will download them again.
- **Condition:** These files are read-only, so use the command.
- **Official command:** `go clean -modcache`
- **Source:** Go documentation

### Go build cache

**Tier: rebuild** · `go.buildcache`

- **Pattern:** `~/Library/Caches/go-build`
- **What it is:** Compiled Go packages kept to speed up builds.
- **If you remove it:** The next builds will be slower.
- **Official command:** `go clean -cache`
- **Source:** Go documentation

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

### Swift package cache

**Tier: rebuild** · `swiftpm.cache`

- **Pattern:** `~/Library/Caches/org.swift.swiftpm`
- **What it is:** Swift packages downloaded earlier.
- **If you remove it:** They will be fetched again.
- **Official command:** `swift package purge-cache`
- **Source:** Research notes (unverified)

### Swift build output

**Tier: rebuild** · `swiftpm.build`

- **Pattern:** `**/.build if-sibling:Package.swift`
- **What it is:** Files produced by building a Swift package.
- **If you remove it:** The package will rebuild in full next time.
- **Official command:** `swift package clean`
- **Source:** Research notes (unverified)

### Swift package trust data

**Tier: never** · `swiftpm.security`

- **Pattern:** `~/Library/org.swift.swiftpm/security`
- **What it is:** Records of packages you chose to trust.
- **If you remove it:** You would lose those trust decisions.
- **Condition:** Not offered.
- **Source:** Research notes (unverified)

### Homebrew installed software

**Tier: never** · `homebrew.installed`

- **Pattern:** `/opt/homebrew/Cellar || /opt/homebrew/Caskroom`
- **What it is:** The software Homebrew installed.
- **If you remove it:** Deleting it removes the apps and tools themselves.
- **Condition:** Not offered. The cleanup command removes only outdated versions.
- **Official command:** `brew cleanup`
- **Source:** Homebrew manual

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

- **Pattern:** `~/Library/Logs || /Library/Logs`
- **What it is:** Records apps and the system wrote about what they did.
- **If you remove it:** You would lose logs that help diagnose a past crash.
- **Condition:** Skip files changed in the last hour.
- **Source:** Apple Support

### Downloaded installers

**Tier: review** · `downloads.installers`

- **Pattern:** `~/Downloads/*.dmg|*.pkg|*.iso|*.zip`
- **What it is:** Installers and archives you downloaded.
- **If you remove it:** If this is your only copy, such as licensed software or an old version, it is gone for good.
- **Condition:** Move to Trash only. Whether the app is already installed is a guess.
- **Source:** Research notes (unverified)

### Mail attachment copies

**Tier: rebuild** · `mail.downloads`

- **Pattern:** `~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads`
- **What it is:** Copies of attachments you opened from Mail.
- **If you remove it:** Only the copies go; the originals stay in the messages.
- **Condition:** Close Mail first.
- **Owning app:** `com.apple.mail`
- **Source:** Third-party guides

### Mail data

**Tier: never** · `mail.store`

- **Pattern:** `~/Library/Mail`
- **What it is:** Your mailboxes, messages and attachments.
- **If you remove it:** Manual deletion can corrupt Mail, and some messages may exist nowhere else.
- **Condition:** Use Mail itself.
- **Owning app:** `com.apple.mail`
- **Source:** Third-party guides

### Messages data

**Tier: never** · `messages.data`

- **Pattern:** `~/Library/Messages/Attachments || ~/Library/Messages/chat.db*`
- **What it is:** Your message history and attachments.
- **If you remove it:** Manual deletion can corrupt your history, and it may be the only copy.
- **Condition:** Use the Messages app settings.
- **Owning app:** `com.apple.MobileSMS`
- **Source:** Third-party guides

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

## Summary

56 rules in total.
