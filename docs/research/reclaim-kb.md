# Reclaim knowledge base: safe-removal advice and size accounting (macOS 15+, Apple Silicon)

Purpose: factual basis for a disk analyzer's "what can I safely remove?" advice and its size accounting.
Research date: 2026-10-31. Test machine: macOS 15.7.9 (24G830), APFS, Xcode SDK `MacOSX.sdk` (attr.h dated 2025-11-18).

## Evidence tags (used everywhere below)

| Tag | Meaning |
|---|---|
| `[LOCAL]` | Observed on this machine by experiment, or read from the SDK header / man page. Reproducible. |
| `[DOC url]` | From first-party or tool-vendor documentation fetched during this research. |
| `[WEB url]` | Third-party or forum source. Weaker. Never the sole basis for SAFE. |
| `[KNOWLEDGE]` | Author knowledge, not re-verified in this session. Treat as UNVERIFIED for decisions. |
| `UNVERIFIED` | Could not be confirmed. Must be shown to the user as uncertain. |

Tier definitions: SAFE = regenerates automatically with no user-visible loss. REBUILD = recoverable but costs time, network or re-login. REVIEW = may hold personal or unique data, the user must look. NEVER = must not be offered.

Design rule: a tier is only as high as the weakest fact behind it. Rows tagged `[KNOWLEDGE]` or UNVERIFIED are capped at REVIEW in the rules engine, even where the "Tier" column shows the likely tier.

---

# PART 1. Reclaim rules

## 1.0 Global policy

1. Prefer the owning tool's own cleanup command over `rm`. The tool knows about locks, indexes and cross-project references.
2. Never delete under a running owner. If the owning app/daemon is running, show "close app first" and do not offer.
3. Offer "Move to Trash" for REVIEW rows. Offer direct deletion only for SAFE/REBUILD rows where the official CLI does the deletion.
4. The Trash frees nothing until emptied [WEB https://www.igeeksblog.com/how-to-delete-iphone-backup-from-mac-computer/]. See 1.5.
5. Show "would free" using summed `ATTR_CMNEXT_PRIVATESIZE` (Part 3.4), not allocated size, so clones and snapshots are not over-promised.
6. SIP-protected/sealed items (`SF_RESTRICTED`, `/System`) are never actionable. Show and size them only.
7. Everything under `~/Library/Containers/*` and `~/Library/Group Containers/*` belongs to an app. Default REVIEW unless a row says otherwise.
8. `~/Library/Caches` hygiene rests on Apple's developer contract, which third parties sometimes violate (1.1 exceptions).

## 1.1 ~/Library/Caches and exceptions

Apple's contract: Caches is for "app-specific support files that your app can re-create easily"; "the system may delete the Caches/ directory to free up disk space, so your app must be able to re-create or download these files as needed" [DOC https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/FileSystemOverview/FileSystemOverview.html]. That guide is iOS-oriented; applicability to macOS is by convention. macOS itself, when space is needed, "clears caches and logs that are safe to delete, including temporary database files" [DOC https://support.apple.com/guide/mac-help/free-up-storage-space-sysp4ee93ca4/mac].

Local fact: `~/Library/Caches` has 181 top-level entries on the test machine, many `com.apple.*` [LOCAL].

| Path / glob | What it is | Tier | Exact consequence of deletion | Side conditions | Source |
|---|---|---|---|---|---|
| `~/Library/Caches/<non-Apple bundle id or vendor dir>` (default) | Third-party app caches | REBUILD | Slower next launch, re-download/re-index. If the app violates the contract, unique data can be lost (exceptions below). | App closed. Show owner app. Do not offer when owner unknown. | Apple FS guide [DOC] |
| `~/Library/Caches/com.apple.*` | System/Apple-app caches (CloudKit, Safari, Mail, akd, accountsd, ...) | NEVER (policy) | Mostly harmless, but owned by running daemons, partly TCC-protected, and some may hold unsynced state. Benefit small, risk not bounded by any source. | Do not offer; macOS purges them itself. | Policy choice. Unsynced-state concern is `[KNOWLEDGE]`, UNVERIFIED |
| `~/Library/Caches/Homebrew` (exists [LOCAL]) | Homebrew download cache | SAFE via CLI | Re-download if a formula is reinstalled. | Use `brew cleanup` (default: stale lock files, downloads older than 120 days, old versions of installed formulae). `brew cleanup -n` is the dry run; `--prune=all` or `-s` removes more. Do not `rm`. | [DOC https://docs.brew.sh/Manpage] |
| `~/Library/Caches/JetBrains/<Product><ver>` | IDE "system" dir: indexes, caches, logs, and Local History | REVIEW | Indexes rebuild slowly. Local History (edit history outside VCS) is not regenerable. | IDE closed. Never offer as one blob. | `[KNOWLEDGE]`, UNVERIFIED |
| `~/Library/Caches/com.spotify.client/Storage` | Spotify offline tracks | REBUILD | Offline content must be re-downloaded (network + account). | Spotify closed. | `[KNOWLEDGE]`, UNVERIFIED |
| `~/Library/Caches/com.apple.dt.Xcode` | Xcode caches | REBUILD | Re-index, re-download metadata. | Xcode closed. | `[KNOWLEDGE]`, UNVERIFIED |
| Browser caches (`Caches/Google/Chrome`, `Caches/Firefox/Profiles/*/cache2`, `Caches/com.apple.Safari`) | HTTP caches | REBUILD | Pages load slower. Cookies/logins are not in Caches. | Browser closed. Safari path is TCC-protected. | `[KNOWLEDGE]`, UNVERIFIED |
| Any `Caches/<x>` containing names like Offline, Downloads, Drafts, Recordings, or a non-cache-looking `*.sqlite` | Possible non-regenerable data kept in Caches | REVIEW | Possible permanent loss. | Name heuristic only; label it as a heuristic in the UI. | Heuristic, no source |

The set of apps that keep unique data under Caches cannot be enumerated from sources. Use REBUILD by default, REVIEW when the heuristic fires, and an allowlist of entries verified by delete-relaunch-compare tests.

## 1.2 Xcode and developer toolchain

| Path / glob | What it is | Tier | Exact consequence | Side conditions | Source |
|---|---|---|---|---|---|
| `~/Library/Developer/Xcode/DerivedData` (exists [LOCAL]) | Build products, indexes, module caches | REBUILD | Full rebuild and re-index of every project. | Quit Xcode and any `xcodebuild`. Delete contents, not the directory. | [WEB https://mole.fit/blog/how-to-clean-up-xcode-mac] (consistent across sources; no Apple page fetched) |
| `~/Library/Developer/Xcode/Archives` (absent on test machine [LOCAL]) | `.xcarchive` bundles with dSYMs and shipped binaries | REVIEW | Loses symbolication of crashes for shipped builds and the ability to re-export that exact build. Not regenerable. | Show per-archive date/app/version. Trash only. | [WEB https://mole.fit/blog/how-to-clean-up-xcode-mac] (one cleanup script deletes it by default; conservative guidance adopted) |
| `~/Library/Developer/Xcode/iOS DeviceSupport/<device ver (build)>` and watchOS/tvOS siblings (exists [LOCAL]) | Device symbol caches copied from a connected device | REBUILD | Xcode re-copies symbols (slow, needs the device attached). Old crash logs for that OS lose symbolication until then. | Delete subfolders only, never the parent. Xcode closed. Keep newest two OS versions by default. | [WEB https://developer.apple.com/forums/thread/18387], [WEB https://www.kodeco.com/19998365-understanding-and-managing-xcode-space?page=2] |
| `~/Library/Developer/CoreSimulator/Devices/<UDID>` (exists [LOCAL]) | Per-simulator data: installed apps, keychain, app sandboxes | REVIEW | Loses installed apps and test state of that simulator. | Do not `rm`. | [WEB https://mole.fit/blog/how-to-clean-up-ios-simulator-mac] |
| Unavailable simulators | Device records whose runtime is gone | REBUILD | Records removed; runtime images untouched. | `xcrun simctl delete unavailable`. `simctl delete` accepts "specified devices, unavailable devices, or all devices" [LOCAL: `simctl help`]. | [LOCAL]; [WEB https://storageradar.chama.pro/blog/xcode-simulator-taking-up-space-on-mac] |
| `/Library/Developer/CoreSimulator/{Volumes,Images,Cryptex}` | Simulator runtime images. One is mounted at `/Library/Developer/CoreSimulator/Volumes/iOS_23D8133` as its own sealed read-only APFS volume (`disk5s1`) [LOCAL] | REBUILD | Runtime must be downloaded again (GBs). | Use Xcode Settings > Components or `xcrun simctl runtime list` / `runtime delete` (`runtime` subcommand exists [LOCAL]). Never `rm`; never unmount by hand. | [LOCAL]; [WEB https://mole.fit/blog/how-to-clean-up-ios-simulator-mac] |
| `~/Library/Developer/Xcode/UserData` | User snippets, themes, key bindings | NEVER | User-authored settings. | Exclude. | `[KNOWLEDGE]`, UNVERIFIED |

## 1.3 Containers, VMs, backups, system

| Path / glob | What it is | Tier | Exact consequence | Side conditions | Source |
|---|---|---|---|---|---|
| `~/Library/Application Support/MobileSync/Backup/<UDID>` (exists [LOCAL]) | Local iPhone/iPad backups | REVIEW | Permanent loss of that backup; if the device is lost and no iCloud backup exists, data is unrecoverable. The phone's data is unaffected. | Delete via Finder or Apple Devices app > General > Manage Backups > right-click > Delete/Archive, not by hand. Show device name and date. Folder access may need FDA (UNVERIFIED). | [DOC https://support.apple.com/108809] |
| `~/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw` (absent on test machine [LOCAL]) | Docker Desktop VM disk (sparse): all images, containers, volumes | REVIEW | Deleting or shrinking the file destroys all images, containers and volumes (including database data). | Never offer the file. Offer the command `docker system prune` ("removes all stopped containers, unused networks, dangling images, and build cache"; named volumes need an explicit `--volumes`, `[KNOWLEDGE]`). Host file may not shrink right away ("might take a few minutes to reclaim space on the host"). Reducing max size in Settings deletes the image: "all containers and images are lost". Logical size = configured maximum (e.g. 64 GB), real usage is much less: use ALLOCSIZE. | [DOC https://docs.docker.com/desktop/troubleshoot-and-support/faqs/macfaqs/] |
| Other VM disks (`~/Parallels`, `~/Virtual Machines.localized`, UTM container, `~/.lima`, `~/.colima`, OrbStack) | VM images | REVIEW | Loss of the VM and its data. | Display only. | `[KNOWLEDGE]` |
| Time Machine local APFS snapshots | Hourly local restore points kept 24 h, one for the last successful backup "until space is needed", one before each macOS update | REVIEW | Loses local restore points only. Apple: "Your Mac counts the space used by snapshots as available storage" and deletes them "as they age or as space is needed". | `tmutil listlocalsnapshots /`, `tmutil thinlocalsnapshots <mount> <bytes> <urgency 1-4>`, `tmutil deletelocalsnapshots <date>` [LOCAL man tmutil]. Apple's documented manual route: turn off automatic backups, wait, turn on. Not offered by default since the system already counts it as available. | [DOC https://support.apple.com/en-us/102154]; [LOCAL] |
| Snapshots `com.apple.os.update-*` | OS-update snapshots. Test machine lists two; `/` is mounted from sealed snapshot `disk3s1s1` [LOCAL] | NEVER | Can break the sealed system volume / rollback. | Never list as reclaimable. | [LOCAL] |
| `/System/Volumes/VM/swapfile*` (test machine: swapfile0..3) and `/private/var/vm` | Swap. `/private/var/vm` is empty on the Data volume; swap lives on the separate VM volume [LOCAL] | NEVER | Kernel-managed. Space returns automatically. | Display under "system volumes", not user folders. | [LOCAL] |
| `/private/var/vm/sleepimage` | Hibernation image | NEVER | Kernel-managed. Absent on the test machine. | Whether Apple Silicon ever creates it is UNVERIFIED; claim nothing. | [LOCAL] (absent) |
| `/Library/Updates`, `/System/Library/AssetsV2`, `/System/Library/Assets` | Update staging and OS assets (several are firmlinked to Data per `/usr/share/firmlinks`) | NEVER | Managed by the OS. | Only System Settings > Software Update. | [LOCAL] for firmlinks; rest `[KNOWLEDGE]` |

## 1.4 Package manager and language caches

Default locations; each tool has overrides, so prefer the tool's own "where is the cache" command.

| Path / glob | What it is | Tier | Exact consequence | Side conditions | Source |
|---|---|---|---|---|---|
| `**/node_modules` | Installed JS dependencies | REBUILD | Reinstall from lockfile + network/store. Local patches, `npm link` targets, offline-only installs are lost. | Offer only when a lockfile sits next to it. Without a lockfile cap at REVIEW. | `[KNOWLEDGE]`, UNVERIFIED |
| `~/.npm` (`_cacache`) (exists [LOCAL]) | npm download cache | REBUILD | Re-download. | `npm cache clean --force` (`npm cache verify` is gentler). | `[KNOWLEDGE]` (npm docs not fetched) |
| pnpm store (`pnpm store path`) | Content-addressable store; `node_modules` files are hard-linked into it | REBUILD | Re-download. | `pnpm store prune` removes only unreferenced packages: "not harmful and has no side effects on your projects". Do not `rm` the store. Hard links make naive sums double count (3.3). | [DOC https://pnpm.io/cli/store] |
| Yarn cache (`yarn cache dir`) | Global cache; Berry "zero-install" projects commit `.yarn/cache` to git | REBUILD | Re-download. For zero-install repos the committed cache IS the dependency source. | `yarn cache clean`. Never touch a git-tracked `.yarn/cache`. | `[KNOWLEDGE]`, UNVERIFIED |
| `~/Library/Caches/pip`, `~/.cache/pip` | pip cache | REBUILD | Re-download/rebuild wheels. | `pip cache purge`; `pip cache dir` to locate. | `[KNOWLEDGE]` (pip docs not fetched) |
| uv: `$UV_CACHE_DIR`, else `$XDG_CACHE_HOME/uv` or `$HOME/.cache/uv` (`~/.cache` exists [LOCAL]) | Wheels, sdists, "centralized project environments" | REBUILD | Re-download/rebuild. Effect on existing virtualenvs is not stated by the docs: UNVERIFIED. | `uv cache clean` (all; keeps dir and lock) or `uv cache prune` ("removes unused cache entries and all centralized project environments, which are recreated as needed"; `--ci` keeps wheels built from source). uv locks the cache; do not touch it while uv runs (`--force` skips the lock). | [DOC https://docs.astral.sh/uv/concepts/cache/] |
| conda `pkgs` (`~/miniconda3`, `~/anaconda3`, `~/miniforge3`) | Package tarballs/extracted packages; envs hard-link into `pkgs` | REBUILD | Only unused packages should go. | `conda clean --all --dry-run`, then `conda clean --all`. Never `rm` `pkgs`. `envs/*` are user work: REVIEW. | `[KNOWLEDGE]` (conda docs not fetched) |
| `~/.cargo/registry`, `~/.cargo/git` (`~/.cargo` absent [LOCAL]) | Crate downloads, git checkouts | REBUILD | "you can always remove any part of the cache and Cargo will do its best to restore sources". Needs network. | Delete `registry/cache`, `registry/src`, `git/checkouts` (and `git/db`). | [DOC https://doc.rust-lang.org/cargo/guide/cargo-home.html] |
| `~/.cargo/bin`, `credentials.toml`, `config.toml`, `.crates.toml`, `.crates2.json` | Installed binaries, registry token, user config, install records | NEVER | `bin` removes installed tools, not auto-rebuilt. `credentials.toml` needs `cargo login`. `config.toml` is hand-written settings. | Exclude from any `.cargo` rule. | [DOC https://doc.rust-lang.org/cargo/guide/cargo-home.html] (the "not regenerable" reading is inference from the descriptions) |
| `<project>/target` next to a `Cargo.toml` | Rust build output | REBUILD | Full rebuild. | `cargo clean` in that project; require the `Cargo.toml` sibling. | `[KNOWLEDGE]`, UNVERIFIED |
| `~/.gradle/{caches,wrapper/dists,daemon}` (`~/.gradle` exists [LOCAL]) | Gradle user home | REBUILD | Re-download dependencies/distributions; slower next build. Gradle already auto-cleans: released wrapper dists 30 d, snapshots 7 d, downloaded resources 30 d, created resources 7 d, build cache 7 d, daemon logs 14 d. | Not while a daemon runs. `gradle.properties`, `init.d`, `init.gradle` are user config: NEVER. | [DOC https://docs.gradle.org/current/userguide/directory_layout.html] (the doc does not say what is safe to delete; consequences inferred) |
| `~/.m2/repository` (absent [LOCAL]) | Maven local repository | REBUILD with a catch | Re-download remote artifacts. Artifacts installed locally with `mvn install` that exist nowhere else are lost. | `settings.xml`, `settings-security.xml` are NEVER. Cap at REVIEW. | `[KNOWLEDGE]`, UNVERIFIED |
| `~/go/pkg/mod`, GOCACHE (`go env GOCACHE`; macOS default believed `~/Library/Caches/go-build`, UNVERIFIED) (`~/go` exists [LOCAL]) | Go module and build caches | REBUILD | Re-download/recompile. | `go clean -modcache` ("remove the entire module download cache"), `-cache` ("remove the entire go build cache"), `-testcache`, `-fuzzcache` (does not touch `testdata`). Module cache files are read-only so plain `rm -rf` fails: use the go command. Never touch `~/go/bin` or `~/go/src`. | [DOC https://pkg.go.dev/cmd/go#hdr-Remove_object_files_and_cached_files] |
| `~/.cocoapods`, `~/Library/Caches/CocoaPods` (`~/.cocoapods` exists [LOCAL]) | Spec repos, pod download cache | REBUILD | Re-clone specs (large) and re-download pods. | `pod cache clean --all`. Per-project `Pods/` may be committed to git: check. | `[KNOWLEDGE]`, UNVERIFIED |
| `~/Library/Caches/org.swift.swiftpm`, `.build`; `~/Library/org.swift.swiftpm/security` | SwiftPM caches/build output; trust data | caches/.build REBUILD; `security` NEVER | Re-fetch/rebuild. | `swift package purge-cache`, `swift package clean`. | `[KNOWLEDGE]`, UNVERIFIED |
| `/opt/homebrew/Cellar`, `/opt/homebrew/Caskroom` | Installed software | NEVER via rm | They are the installed apps. | `brew cleanup` removes only outdated versions. | [DOC https://docs.brew.sh/Manpage] |

## 1.5 User-visible folders and personal data

| Path / glob | What it is | Tier | Exact consequence | Side conditions | Source |
|---|---|---|---|---|---|
| `~/.Trash` (exists [LOCAL]), `/Volumes/*/.Trashes/<uid>` | The Trash | REVIEW | Permanent deletion of what the user trashed. Counts as used until emptied. | Use Finder "Empty Trash" semantics. Auto-empty after 30 days exists as a user option. Do not hide `.Trashes` (Part 2). | [DOC https://support.apple.com/guide/mac-help/free-up-storage-space-sysp4ee93ca4/mac] |
| `~/Library/Logs`, `/Library/Logs`, `~/Library/Logs/DiagnosticReports` (`~/Library/Logs` exists [LOCAL]) | App and crash logs | SAFE (loss: diagnostic history) | Loses logs useful for debugging a past crash. | Skip files modified in the last hour. `/var/log` and `/var/db/diagnostics` are NEVER. | Apple says macOS clears "caches and logs that are safe to delete" [DOC]; tier assisted by `[KNOWLEDGE]` |
| `~/Downloads/*.dmg, *.pkg, *.iso, *.zip` | Downloaded installers | REVIEW | Permanent loss if it is the only copy (licensed software, old versions). | Trash only, show date. "Already installed" detection (matching app in /Applications) is a heuristic and must be labelled so. Unmount mounted `.dmg` first. | `[KNOWLEDGE]`, UNVERIFIED |
| `~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads` (path varies by macOS version) | Copies of attachments opened in Mail | REBUILD (low risk) | Copies only; originals are in the message. Leftovers and path differences are reported. | Mail closed. For message data use Mail > Message > Remove Attachments. | [WEB https://www.imore.com/running-out-storage-space-your-mac-try-deleting-your-mac-mail-downloads], [WEB https://setapp.com/how-to/delete-mail-downloads]; no Apple page: UNVERIFIED |
| `~/Library/Mail` (messages, `Envelope Index`, attachments) | Mail store | NEVER via rm | Corrupts Mail's consistency; for POP / "On My Mac" mailboxes messages may exist nowhere else. | FDA-protected. Advise only via Mail UI. | [WEB https://mole.tw93.fun/blog/how-to-reduce-mail-storage-mac]; POP point `[KNOWLEDGE]` |
| `~/Library/Messages/Attachments`, `chat.db*` | Messages history and attachments | NEVER via rm | Database and files must change together; manual deletion can orphan/corrupt history, and local history may be the only copy if Messages in iCloud is off. | FDA-protected. Advise Messages' own Keep Messages setting or deleting in the app. | [WEB https://mole.fit/blog/how-to-clear-messages-storage-mac] (popular how-tos delete them by hand; conservative position adopted) |
| `~/Pictures/*.photoslibrary`, `~/Library/Containers/com.apple.photolibraryd`, `~/Library/Photos` | Photos library package and service data | NEVER (internals) | Editing/deleting inside the package can corrupt the library; with iCloud Photos off, the originals are the only copies. | Show the package as one opaque item. Reclaim only through Photos (delete photos; Optimize Mac Storage: "Optimized versions of your photos are always on your Mac") or by the user moving the whole library. `.photoslibrary` is a package by UTType `com.apple.photos.library` [LOCAL]; one exists in `~/Pictures` on the test machine, contents not inspected [LOCAL]. | [DOC https://support.apple.com/guide/mac-help/free-up-storage-space-sysp4ee93ca4/mac] for Optimize; "do not edit internals" is `[KNOWLEDGE]` (Apple Photos page fetch returned unrelated content) |
| iCloud placeholders / dataless files: `~/Library/Mobile Documents/**`, `~/Library/CloudStorage/**`, synced Desktop/Documents | Files whose data lives remotely, flagged `SF_DATALESS` | Not reclaimable (0 B local) | Nothing to free. Deleting a placeholder deletes the cloud file everywhere. Materialized files can be evicted by the user (Remove Download / Optimize Storage). | Never present deletion of placeholders as space saving. Scanning must not materialize them (3.8). `~/Library/Mobile Documents` is EPERM to a process without FDA [LOCAL]. `/usr/bin/brctl` exists [LOCAL]; its eviction subcommand is UNVERIFIED. | [DOC https://developer.apple.com/documentation/technotes/tn3150-getting-ready-for-data-less-files.md] |
| `/Applications/*.app/Contents/Resources/*.lproj` (language packs) | Localizations inside signed bundles | NEVER | Changing a signed bundle can invalidate its code signature: the signature "covers the whole bundle". Some localizations are marked optional, so results vary by app. Apps may restore files on update. | Do not offer. If displayed, say "removing may invalidate the app's signature". | [WEB https://eclecticlight.co/2020/11/03/code-signatures-3-fixing-signature-problems/], [WEB https://forums.macrumors.com/threads/monolingual.1984089] |
| `~/Library/Application Support/<App>` of uninstalled apps | Settings, databases, licences, saves, documents | REVIEW | Possible loss of settings, offline licences, local databases, saved work. | "App not found" is only a hint (CLI tools, helper apps, nonstandard install locations). Never auto-select. Check Preferences, Containers, Group Containers separately. | `[KNOWLEDGE]` |
| Chromium/Electron caches inside Application Support (`GPUCache`, `Code Cache`, `Service Worker/CacheStorage`) | Embedded browser caches | REBUILD | Rebuild/re-download. `Service Worker/CacheStorage` can hold offline-only web-app data. | App closed. `IndexedDB`, `Local Storage`, `Cookies` are NOT caches. | `[KNOWLEDGE]`, UNVERIFIED |
| `/private/var/folders/**` (exists [LOCAL]) | Per-user system temp and caches | NEVER | In use by processes. App translocation mounts live here (a nullfs mount of `Visual Studio Code.app` under `.../AppTranslocation` on the test machine [LOCAL]). | Display only. | [LOCAL] |

## 1.6 Summary for the rules engine

1. SAFE: tool-driven cleanup of logs and Homebrew outdated items only.
2. REBUILD: caches whose owner documents regeneration (cargo, pnpm, uv, Go, Gradle) plus Xcode DerivedData, DeviceSupport, unavailable simulators.
3. REVIEW: user-authored data; Archives, backups, Trash, Downloads installers, VM images, Application Support leftovers, Time Machine snapshots.
4. NEVER: Photos/Mail/Messages internals, system volumes, swap, OS snapshots, signed bundle contents, toolchain credentials/configs, `/private/var/folders`.

---

# PART 2. Ignore defaults

Core rule: "hidden by default" means collapsed in the UI, not excluded from byte totals. Otherwise totals will not reconcile with the volume's used space. Show one "Hidden system items: N GB" line with a toggle. Caches stay visible.

## 2.1 Flags observed at the roots [LOCAL]

`getattrlistbulk` on `/` (21 entries) and `/System/Volumes/Data` (19 entries) returned these `ATTR_CMN_FLAGS`:

| Value | Name | Seen on |
|---|---|---|
| `0x00008000` | `UF_HIDDEN` | `home`, `.vol`, `opt`, `mnt`, `sw`, `dev`, `cores`, `Volumes`, `private` |
| `0x00080000` | `SF_RESTRICTED` | `/System`, `usr`, `bin`, `sbin`, `etc`, `var`, `tmp` |
| `0x00100000` | `SF_NOUNLINK` | `Library`, `Users`, `Applications` (Data side) |
| `0x00800000` | `SF_FIRMLINK` | `Library`, `private`, `Users`, `Applications`, `opt`, `Volumes`, `cores` (System-volume side only) |
| `0x40000000` | `SF_DATALESS` | none in the test directories |

Synthetic root entries on `/`: `.resolve`, `.file`, `.nofollow`, `.vol`, `.VolumeIcon.icns`. Plumbing, ~0 size.

## 2.2 Hidden-by-default list

Size impact is qualitative; none of these were measured (most need root/FDA). Magnitudes are UNVERIFIED.

| Name / path | What it is | Default | Size impact | Delete? |
|---|---|---|---|---|
| `.DS_Store` | Finder view settings per folder | Hide | KB each, one per visited folder; matters mostly for entry counts | Harmless; not worth offering `[KNOWLEDGE]` |
| `.Spotlight-V100` (exists on Data root [LOCAL]) | Spotlight index | Hide, count | Can reach hundreds of MB to GBs | Regenerable (`mdutil -E`), protected; not offered |
| `.fseventsd` (exists on Data root [LOCAL]) | FSEvents log | Hide, count | Small to moderate | Not offered |
| `.DocumentRevisions-V100` (exists on Data root [LOCAL]) | Versions database for documents | Hide, count | Can be large | NEVER offered: holds prior versions of user documents |
| `.Trashes` (other volumes; absent on Data root [LOCAL]) | Trash on that volume | DO NOT HIDE | Full size of trashed files | It is the Trash (1.5) |
| `~/.Trash` | User Trash | DO NOT HIDE | Full size | See 1.5 |
| `.TemporaryItems`, `.PreviousSystemInformation`, `.com.apple.templatemigration.boot-install` (on Data root [LOCAL]) | OS temp, upgrade leftovers | Hide, count | Small to moderate | Not offered (safety unconfirmed) |
| `._*` (AppleDouble) | Xattr/resource-fork companion on exFAT/FAT/SMB/NFS volumes | Hide, count | Tiny each | Removing loses the base file's xattrs (tags, quarantine, comments). Orphans are removable. REVIEW. `[KNOWLEDGE]` |
| `Icon\r` (name "Icon" + CR) | Custom folder icon (resource fork) | Hide | ~0 data fork; ALLOCSIZE includes the resource fork | Removing resets the custom icon `[KNOWLEDGE]` |
| `.localized`, `.CFUserTextEncoding`, `.apdisk`, `.VolumeIcon.icns`, `.hidden` | Markers | Hide | ~0 | Leave |
| `/System` (sealed, `SF_RESTRICTED`) | macOS | One non-actionable "macOS" node | `/` Used 17 GiB vs Data 391 GiB on the test machine [LOCAL `df`] | NEVER |
| `/System/Volumes/*` other than Data (VM, Preboot, Update, xarts, iSCPreboot, Hardware) | Support volumes in the same container, `nobrowse` [LOCAL `mount`] | Hide children; one "System volumes" aggregate | Swap lives on VM | NEVER |
| `.vol`, `.file`, `.nofollow`, `.resolve` at `/` | Synthetic APFS entries | Skip entirely | 0 | n/a |
| `dev`, `home`, `net` (devfs/autofs), `Volumes`, `cores`, `mnt`, `sw` | Mount points / system dirs. `home` is `map auto_home on /System/Volumes/Data/home` (autofs) [LOCAL] | Skip `dev`, `home`, `net`: descending can trigger automounts | 0 | n/a |

## 2.3 What must stay visible

Everything under `~/Library/Caches`, `~/Library/Logs`, `~/Library/Developer`, `~/Library/Application Support`, `~/.Trash`, `/Library/Caches`, `~/.cache`, `~/.npm`, `~/.gradle`, `~/.cocoapods`, package-manager dirs, and project artifacts (`node_modules`, `target`, `.build`, `.git`). `~/Library` carries a Finder-hidden flag, yet is the main reclaim target, and developer caches are dot-directories. Hiding by leading dot or `UF_HIDDEN` alone would hide most reclaimable space. Hide only by the explicit list above.

---

# PART 3. Accounting facts

## 3.1 Why totals differ from Finder

1. Logical vs allocated. Test machine examples [LOCAL]: a 3-byte file has total 3, alloc 4096; a 100 MiB sparse file (`truncate -s 100m`) has total 104857600, alloc 0, `EF_IS_SPARSE` set; a 1 MiB random file has total = alloc = 1048576.
2. Finder's exact algorithm (decimal units, package handling, dataless logical sizes, purgeable) was not verified: UNVERIFIED.
3. Clones, hard links and snapshots make a sum of per-file ALLOCSIZE differ from real use (3.3, 3.4).
4. Firmlinks and volume groups cause double counting on a naive walk from `/` (3.6).
5. Purgeable space is "used" to `df` but "available" to the system's important-usage figure (3.5).
6. `ATTR_DIR_ALLOCSIZE` is the directory's own allocation, not recursive. Directory total = sum of children.

Constants (SDK `usr/include/sys/attr.h`, `sys/stat.h`, `sys/clonefile.h`, `sys/resource.h`, verified present) [LOCAL]:

| Constant | Value |
|---|---|
| `ATTR_FILE_LINKCOUNT` | 0x00000001 |
| `ATTR_FILE_TOTALSIZE` | 0x00000002 (logical, all forks) |
| `ATTR_FILE_ALLOCSIZE` | 0x00000004 (physical, all forks) |
| `ATTR_FILE_DATALENGTH` / `ATTR_FILE_DATAALLOCSIZE` | 0x00000200 / 0x00000400 |
| `ATTR_FILE_RSRCLENGTH` / `ATTR_FILE_RSRCALLOCSIZE` | 0x00001000 / 0x00002000 |
| `ATTR_CMNEXT_RELPATH` | 0x00000004 |
| `ATTR_CMNEXT_PRIVATESIZE` | 0x00000008 |
| `ATTR_CMNEXT_LINKID` | 0x00000010 |
| `ATTR_CMNEXT_NOFIRMLINKPATH` | 0x00000020 |
| `ATTR_CMNEXT_REALDEVID` | 0x00000040 |
| `ATTR_CMNEXT_REALFSID` | 0x00000080 |
| `ATTR_CMNEXT_CLONEID` | 0x00000100 |
| `ATTR_CMNEXT_EXT_FLAGS` | 0x00000200 |
| `ATTR_CMNEXT_CLONE_REFCNT` | 0x00001000 |
| `ATTR_CMNEXT_VALIDMASK` | 0x00001ffc |
| `FSOPT_ATTR_CMN_EXTENDED` | 0x00000020 (required for any `ATTR_CMNEXT_*`; forkattr is reinterpreted) |
| `FSOPT_RETURN_REALDEV` | 0x00000200 |
| `FSOPT_PACK_INVAL_ATTRS` | 0x00000008 |
| `FSOPT_REPORT_FULLSIZE` | 0x00000004 |
| `FSOPT_NOFOLLOW` / `FSOPT_NOFOLLOW_ANY` | 0x1 / 0x800 |
| `SF_FIRMLINK` | 0x00800000 |
| `SF_DATALESS` | 0x40000000 (read-only, outside `SF_SUPPORTED`) |
| `SF_RESTRICTED` | 0x00080000 |
| `UF_COMPRESSED` | 0x00000020 |
| `DIR_MNTSTATUS_MNTPOINT` | 0x1 |
| `CLONE_NOFOLLOW` / `CLONE_NOOWNERCOPY` / `CLONE_ACL` / `CLONE_NOFOLLOW_ANY` | 0x1 / 0x2 / 0x4 / 0x8 |
| `VOL_CAP_FMT_CLONE_MAPPING` | 0x04000000 ("supports full clone tracking"; see CLONE_REFCNT and CLONEID) |
| `VOL_CAP_INT_CLONE` | 0x00010000 |
| `VOL_CAP_FMT_DIR_HARDLINKS` | 0x00040000 |
| `IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES` | 3 (`..._OFF` = 1, `..._DEFAULT` = 0) |

The `EF_*` extended-flag constants are NOT defined in the SDK header nor in the public xnu `bsd/sys/attr.h` (both searched) [LOCAL][WEB]. The man page names them; the app must define the values:

| Name | Value | Evidence |
|---|---|---|
| `EF_MAY_SHARE_BLOCKS` | 0x1 | [LOCAL] set alone on a partially modified clone |
| `EF_IS_SPARSE` | 0x10 | [LOCAL] set on the sparse test file |
| `EF_SHARES_ALL_BLOCKS` | 0x40 | [LOCAL] inferred: a full-clone pair shows 0x41; man says SHARES_ALL implies MAY_SHARE |
| `EF_NO_XATTRS` | UNVERIFIED (0x2 suspected) | not observed |
| `EF_IS_SYNC_ROOT` | UNVERIFIED (0x4 suspected) | |
| `EF_IS_PURGEABLE` | UNVERIFIED (0x8 suspected) | |
| `EF_IS_SYNTHETIC` | UNVERIFIED (0x20 suspected) | |

`CLONE_NOOWNERCOPY` is a flag to `clonefile(2)` ("Don't copy ownership information from the source when run called with superuser privileges") [LOCAL man clonefile]. It plays no part in size accounting; the analyzer never clones. Clone detection uses `ATTR_CMNEXT_CLONEID`, `ATTR_CMNEXT_EXT_FLAGS`, `ATTR_CMNEXT_CLONE_REFCNT`.

## 3.2 Which sizes to report

| Label | Source | Use |
|---|---|---|
| Logical | `ATTR_FILE_TOTALSIZE` | Finder-like "Size" |
| Allocated | `ATTR_FILE_ALLOCSIZE`, with hard-link and full-clone dedupe | "Size on disk" |
| Reclaimable | summed `ATTR_CMNEXT_PRIVATESIZE` | "Would free if deleted", excludes blocks trapped in clones/snapshots |

Use `ALLOCSIZE`, not `DATAALLOCSIZE`, so resource forks are included. On test files without resource forks they were equal [LOCAL].

## 3.3 Hard links

[LOCAL] `a.bin` and `ln a.bin c_hard.bin`:
- Both report `LINKCOUNT` 2 and the same `ATTR_CMN_FILEID` (152724142).
- `ATTR_CMNEXT_LINKID` differs per link (152724144 vs 152724145). The man page says no relation to FILEID should be implied.
- A clone gets its own FILEID.

Rule:
- `LINKCOUNT` == 1: count normally.
- `LINKCOUNT` > 1: dedupe on (real device id, `ATTR_CMN_FILEID`); count ALLOCSIZE the first time only. Use the real device id (3.6), since `st_dev` is not unique per volume in a volume group.
- Keep a set only for LINKCOUNT>1 files; it stays small.
- Directory hard links exist only as legacy Time Machine (`VOL_CAP_FMT_DIR_HARDLINKS`); need for loop protection on modern volumes is UNVERIFIED.
- pnpm store, uv cache, conda `pkgs` use hard links heavily; naive sums overcount.

## 3.4 APFS clones

[LOCAL] `cp -c a.bin b_clone.bin` (full clone) and a clone later edited by 8 bytes:

| File | FILEID | CLONEID | PRIVATESIZE | ALLOCSIZE | EXT_FLAGS | CLONE_REFCNT |
|---|---|---|---|---|---|---|
| original `a.bin` (+ hard link) | 152724142 | 152724142 | 0 | 1048576 | 0x41 | 2 |
| full clone `b_clone.bin` | 152724143 | 152724142 | 0 | 1048576 | 0x41 | 2 |
| clone after 8-byte edit | own | 152724296 (new) | 16384 | 1048576 | 0x1 | not recorded |
| unrelated 1 MiB file | own | own | 1048576 | 1048576 | 0 | 1 |

Findings:
- Full clones share CLONEID (= the original's FILEID); CLONE_REFCNT counts the family. PRIVATESIZE is 0 for every member since all blocks are shared, so a sum of PRIVATESIZE undercounts real use by the shared blocks (1 MiB invisible here).
- After a modification the file gets a new CLONEID, loses `EF_SHARES_ALL_BLOCKS`, keeps `EF_MAY_SHARE_BLOCKS`, and reports PRIVATESIZE 16384 (one allocation unit of its own).
- ALLOCSIZE always reports the full file size, so summing it across clones overcounts physical use.
- PRIVATESIZE also excludes blocks held by snapshots (man page: bytes "not trapped inside a clone or snapshot, and which would be freed immediately if the file were deleted").

Recommended algorithm:
1. Allocated (deduped): if `EF_SHARES_ALL_BLOCKS`, count ALLOCSIZE once per (real dev, CLONEID). Else count ALLOCSIZE and, if `EF_MAY_SHARE_BLOCKS`, flag "may share blocks". A better partial-clone model is UNVERIFIED.
2. Reclaimable for a selection: sum PRIVATESIZE of selected files, plus a clone family's shared size once if all `CLONE_REFCNT` members are selected (validated for full clones only; otherwise present as "at least").
3. Never claim that the sum of ALLOCSIZE equals the volume's used space.

Availability: the constants are in the SDK and were returned by `getattrlistbulk` with `FSOPT_ATTR_CMN_EXTENDED` on APFS (Data volume) [LOCAL]. On HFS+/exFAT/SMB/NFS: unverified. Use `FSOPT_PACK_INVAL_ATTRS` and read the returned set; treat absent attributes as "unknown", not zero.

## 3.5 Purgeable space and volume capacity

- `volumeAvailableCapacityKey`: free space excluding purgeable. `volumeAvailableCapacityForImportantUsageKey`: includes purgeable, for user-initiated work. `volumeAvailableCapacityForOpportunisticUsageKey`: for optional work. These descriptions are `[KNOWLEDGE]`; the Apple page fetch returned no body.

Measured on the test machine via `URLResourceValues` [LOCAL]:

| Key | Bytes |
|---|---|
| total | 494,384,795,648 |
| available | 32,582,746,112 |
| availableForImportantUsage | 32,606,818,304 |
| availableForOpportunisticUsage | 20,235,538,138 |

Surprise: opportunistic (20.2 GB) is lower than plain available (32.6 GB). Do not assume opportunistic >= available; do not use it for a "free space" display. Reason UNVERIFIED.

`/` and `/System/Volumes/Data` return identical capacity numbers: one APFS container, one free pool. `df` shows `/` Used 17 GiB and Data Used 391 GiB of the same 460 GiB [LOCAL]. Do not add the free space of each volume.

`EF_IS_PURGEABLE` exists (man page) but its bit value is UNVERIFIED. Time Machine local snapshots count as available space per Apple [DOC https://support.apple.com/en-us/102154].

Display "Free" = important-usage figure (what an app can actually obtain). "Used" = total - important. Label the gap to `df` "purgeable".

## 3.6 Data volume, firmlinks, volume groups, device boundaries

Facts [LOCAL]:
- `/` is a sealed read-only snapshot of the System volume (`/dev/disk3s1s1`). User data is on `/dev/disk3s5` mounted at `/System/Volumes/Data`. Other volumes of the container are `nobrowse` mounts under `/System/Volumes/` (VM, Preboot, Update, xarts, iSCPreboot, Hardware).
- Firmlinks are defined in `/usr/share/firmlinks` (tab-separated: `/path<TAB>relative-path-on-Data`). On the test machine: `/AppleInternal`, `/Applications`, `/Library`, `/System/Library/Caches`, `/System/Library/Assets`, `/System/Library/PreinstalledAssets`, `/System/Library/AssetsV2`, `/System/Library/PreinstalledAssetsV2`, `/System/Library/CoreServices/CoreTypes.bundle/Contents/Library`, `/System/Library/Speech`, `/Users`, `/Volumes`, `/cores`, `/opt`, `/private`, `/usr/local`, `/usr/libexec/cups`, `/usr/share/snmp`.
- `/Users` and `/System/Volumes/Data/Users` have identical dev and inode under `stat` (16777233 / 16985): same directory.
- `getattrlistbulk` on `/` sets `SF_FIRMLINK` on firmlinked directories. Man page: attributes returned for a firmlink "will be those from the firmlink, not the firmlink's target". Data-side entries are not flagged.
- Plain `st_dev` cannot separate System from Data: `/` and `/System/Volumes/Data` both report 0x1000011. Real device ids differ (via `ATTR_CMNEXT_REALDEVID` or `ATTR_CMN_DEVID` + `FSOPT_RETURN_REALDEV`):

| Path | st_dev | real dev | from |
|---|---|---|---|
| `/`, `/System` | 0x1000011 | 0x1000013 | /dev/disk3s1s1 |
| `/System/Volumes/Data`, `/Users`, `/private/var/vm` | 0x1000011 | 0x1000011 | /dev/disk3s5 |
| `/System/Volumes/VM` | 0x100000f | 0x100000f | /dev/disk3s6 |
| `/System/Volumes/Preboot` | 0x100000e | 0x100000e | /dev/disk3s2 |
| CoreSimulator runtime volume | 0x1000017 | 0x1000017 | /dev/disk5s1 |

Recommended roots and de-duplication:
1. Whole-disk view: scan two roots. (a) `/System/Volumes/Data`, displayed with that prefix stripped so `/Users/x` looks normal. (b) `/` for the System volume only.
2. On (b): skip entries with `SF_FIRMLINK` (content is covered by (a)), skip `/System/Volumes`, skip synthetic entries (`.vol`, `.file`, `.nofollow`, `.resolve`).
3. The flag is the primary signal (no parsing needed). Use `/usr/share/firmlinks` as a test-time sanity check. On the test machine they agree for the top-level entries observed.
4. Home-folder scans (`~`, `/Users`) are unaffected as long as firmlinks are never followed from the System side.
5. Device boundary: do not use `st_dev` for System vs Data. Request `ATTR_CMNEXT_REALDEVID` and compare with the root's real dev. Also stop at `ATTR_DIR_MOUNTSTATUS & DIR_MNTSTATUS_MNTPOINT` (seen set on `/dev` and on Data `home`) [LOCAL].
6. Do not descend into `/Volumes/*` (external/network volumes: user choice) nor autofs `home`/`net` by default.
7. Reconcile: container used minus (System + Data scanned) = "Other APFS volumes (VM, Preboot, Update, ...)".

## 3.7 Mount points, symlinks

- `getattrlistbulk` reports a symlink's own attributes, not its target's [LOCAL man]. Never follow symlinks. `/Applications/Safari.app` is a symlink (flags `restricted,hidden`) to `/System/Cryptexes/App/System/Applications/Safari.app` [LOCAL]: system apps live in cryptexes.
- A mount-point directory returns the covered directory's attributes; call `getattrlist` on the path for the mounted root's attributes [LOCAL man].
- `etc`, `var`, `tmp` at `/` are symlinks (object type 5, VLNK) [LOCAL].

## 3.8 Dataless files

- Detect: `SF_DATALESS` in `ATTR_CMN_FLAGS` or `st_flags`. It is "a feature of APFS" and read-only [LOCAL header][DOC TN3150 https://developer.apple.com/documentation/technotes/tn3150-getting-ready-for-data-less-files.md].
- Accounting: logical size is non-zero, local allocation ~0 (UNVERIFIED: no dataless file was reachable without FDA; exact TOTALSIZE/ALLOCSIZE values not observed). Count in Logical, exclude from Allocated and Reclaimable, badge as cloud.
- Do not materialize: TN3150 says `stat` and `getattrlist` "both trigger the materialization of any intermediate folders in the file's path, if they themselves are dataless", and its trace shows `getattrlistbulk` reaching `apfs_materialize_dataless_file_ext` (that trace is for a directory enumeration, so listing a dataless directory downloads it).
- Apple's mitigation: per-thread `setiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD, IOPOL_MATERIALIZE_DATALESS_FILES_OFF)`, restore afterwards, and handle `EDEADLK`.
- Do not parse `.icloud` placeholder files: DTS says the format is not public API [WEB https://developer.apple.com/forums/thread/722654].
- Without FDA `~/Library/Mobile Documents` cannot even be listed (EPERM) [LOCAL]: show "unknown (needs Full Disk Access)", never 0.

## 3.9 Packages and bundles

[LOCAL] `UTType(filenameExtension:)` then `conforms(to: .package)`:

| Extension | UTType | package |
|---|---|---|
| app, bundle, plugin, kext, appex, prefPane, qlgenerator, mdimporter | com.apple.application-bundle, generic-bundle, ... | yes |
| photoslibrary, musiclibrary, tvlibrary, imovielibrary, photolibrary, aplibrary | com.apple.photos.library, ... | yes |
| xcarchive, xcodeproj, xcworkspace, playground, dSYM, mlmodelc | Xcode types | yes |
| rtfd, logicx, band, sparsebundle, numbers, pages, key | | yes |
| framework | com.apple.framework | NO (bundle yes, package no) |
| fcpbundle, lrdata, savedState, tmbackup, backupdb, lproj | dynamic (`dyn.*`) | NO (unknown to the type system here) |
| pkg, dmg | installer-package-archive, disk-image-udif | NO (flat files) |

- Apple: Finder/Launch Services treat a directory as a package by its extension when the type is registered with `LSTypeIsPackage` [DOC https://developer.apple.com/library/archive/documentation/CoreFoundation/Conceptual/CFBundles/DocumentPackages/DocumentPackages.html]. No filesystem attribute marks a package; the FinderInfo "bundle bit" is UNVERIFIED on APFS and is not used.
- Without per-file Launch Services calls: cache `UTType(filenameExtension:)` per distinct extension. 100,000 lookups over 50 distinct extensions took 0.21 s (~2 us each) [LOCAL]. Whether a cache miss contacts Launch Services is UNVERIFIED. Per-URL `isPackage` also works (true for an app [LOCAL]) but is a per-file call and unnecessary.
- Policy: treat a directory as a package when its extension is in the cached `conforms(to: .package)` set; unknown (dynamic) extensions are plain folders. Collapse in the display but still walk it for sizing; allow expansion; no deletions inside system packages (Photos: 1.5).
- Frameworks are bundles but not packages: show as ordinary folders.

## 3.10 Sparse files

`ALLOCSIZE` < `TOTALSIZE`; `VOL_CAP_FMT_SPARSE_FILES` states volume support and `EF_IS_SPARSE` (0x10) marks the file [LOCAL] (test: 100 MiB logical, 0 allocated). Docker.raw is sparse; its logical size equals the configured maximum [DOC Docker FAQ]. Always use ALLOCSIZE.

## 3.11 Compression

`UF_COMPRESSED` (0x20) marks transparently compressed files [LOCAL header]. That compressed files report logical size in TOTALSIZE and compressed size in ALLOCSIZE was not verified by experiment here: UNVERIFIED.

---

# PART 4. Fast enumeration with getattrlistbulk

Checked against local man pages (`getattrlistbulk(2)`, `getattrlist(2)`), the SDK header, and a C program that walked a scratch directory on APFS [LOCAL]. The test program lives in the session scratchpad only.

## 4.1 Call shape

```
int n = getattrlistbulk(dirfd, &attrlist, buf, bufsize, options);
```
- `dirfd`: open with `O_RDONLY | O_DIRECTORY` (plus `O_NOFOLLOW` on descent).
- `attrlist.bitmapcount = ATTR_BIT_MAP_COUNT` (else EINVAL).
- Required: `ATTR_CMN_NAME | ATTR_CMN_RETURNED_ATTRS` (`ATTR_BULK_REQUIRED`), else EINVAL. Volume attributes: EINVAL.
- Returns the entry count; 0 = end; -1 with errno.
- Entry order unspecified. Mixing `readdir` and `getattrlistbulk` on one fd is undefined.
- `.` and `..` were not returned in the tests (10 real entries in a 10-file directory) [LOCAL]; the man page is silent.
- After 0, no further entries are returned even if added; restart with `lseek(fd, 0, SEEK_SET)` or reopen.

Attribute set used in the test (all returned on APFS):

| Group | Attributes |
|---|---|
| commonattr | `ATTR_CMN_RETURNED_ATTRS`, `ATTR_CMN_ERROR`, `ATTR_CMN_NAME`, `ATTR_CMN_DEVID`, `ATTR_CMN_OBJTYPE`, `ATTR_CMN_FLAGS`, `ATTR_CMN_FILEID` |
| dirattr | `ATTR_DIR_MOUNTSTATUS` |
| fileattr | `ATTR_FILE_LINKCOUNT`, `ATTR_FILE_TOTALSIZE`, `ATTR_FILE_ALLOCSIZE`, `ATTR_FILE_DATALENGTH`, `ATTR_FILE_DATAALLOCSIZE` |
| forkattr (needs `FSOPT_ATTR_CMN_EXTENDED`) | `ATTR_CMNEXT_PRIVATESIZE`, `ATTR_CMNEXT_LINKID`, `ATTR_CMNEXT_CLONEID`, `ATTR_CMNEXT_EXT_FLAGS`, `ATTR_CMNEXT_CLONE_REFCNT`, and `ATTR_CMNEXT_REALDEVID` when the device boundary is needed |

Always request `ATTR_CMN_OBJTYPE`: the man page recommends using it to parse, and dir vs file groups are returned only for the matching type.

## 4.2 Buffer layout and alignment

- Each entry begins with a `uint32_t` total length (including itself). Step with `entry += length`. The man page says this leading length "will always be 8-byte aligned". In the tests every entry started on an 8-byte boundary and lengths were multiples of 8 (104, 136, 144) [LOCAL]. Allocate `buf` 8-byte aligned (`posix_memalign`/`aligned_alloc`).
- Fields inside an entry are only 4-byte aligned, "including 64-bit data types" (`getattrlist(2)`). Never cast a field pointer to `uint64_t*`/`off_t*`. Use `memcpy` or, in Swift, `UnsafeRawPointer.loadUnaligned(fromByteOffset:as:)`.
- Order in an entry: length; `attribute_set_t` returned (20 bytes: commonattr, volattr, dirattr, fileattr, forkattr); `ATTR_CMN_ERROR` if in the returned set; then common attributes ascending by bit; then dir, file and fork groups, each ascending by bit. Verified by a parse driven only by the returned set [LOCAL].
- Variable-length name: `attrreference_t {int32 attr_dataoffset; uint32 attr_length}`; the string lies at (address of the attrreference) + `attr_dataoffset`, NUL-terminated. The offset is always a multiple of 4 [LOCAL man]. UTF-8; do not renormalize names before opening them.
- Parse presence strictly from the returned set, never from the request. Observed: `ATTR_CMN_ERROR` (0x20000000) is absent from the returned commonattr (0x8204000b) unless `FSOPT_PACK_INVAL_ATTRS` is set (then 0xa204000b) or an error occurs [LOCAL]. A parser that assumes ERROR is always present reads garbage.
- Directory entries do not carry file attributes (returned fileattr was 0), and file entries carry no dir attributes [LOCAL].

## 4.3 Options

| Option | Behaviour |
|---|---|
| `FSOPT_PACK_INVAL_ATTRS` (0x8) | Packs all requested attributes even when unsupported, with default values; the returned set says which are valid. Makes `ATTR_CMN_ERROR` appear in the returned set [LOCAL]. Recommended. |
| `FSOPT_ATTR_CMN_EXTENDED` (0x20) | Reinterprets `forkattr` as `ATTR_CMNEXT_*` (also allows `ATTR_CMN_GEN_COUNT`, `ATTR_CMN_DOCUMENT_ID`). Needed for PRIVATESIZE, CLONEID, EXT_FLAGS, REALDEVID. |
| `FSOPT_RETURN_REALDEV` (0x200) | Per `getattrlist(2)`, DEVID/FSID return the physical volume's values instead of the volume group's. Not listed on the bulk man page: whether bulk honours it is UNVERIFIED. Prefer `ATTR_CMNEXT_REALDEVID`. |
| `FSOPT_NOFOLLOW` | For bulk, symlink entries are reported as links regardless [LOCAL man]. |
| `FSOPT_REPORT_FULLSIZE` | Length reporting for truncated buffers (getattrlist semantics); not needed. |

## 4.4 Errors and edge cases

| Situation | Behaviour |
|---|---|
| Buffer too small for one entry | -1, `errno = ERANGE` [LOCAL: a 100-byte buffer gave errno 34]. |
| Last batch exactly fills the buffer | A developer reported on APFS (macOS 10.13) that the next call fails with ERANGE instead of returning 0, and that calling again returns 0; not seen on 10.14. Not confirmed by Apple [WEB https://developer.apple.com/forums/thread/98262]. UNVERIFIED on macOS 15+. Mitigation: treat ERANGE after a full previous buffer as end-of-directory, or retry once. Use buffers of at least 64 KiB so any single entry fits (a 1024-byte name plus ~200 bytes of attributes). |
| Per-entry failure | The entry arrives with `ATTR_CMN_ERROR` non-zero. Skip its remaining fields (the man example prints the name then continues). Count it as unreadable. Not seen in tests (0 errors). |
| Directory open fails | `EPERM` on TCC/FDA-protected dirs (`~/Library/Safari`, `~/Library/Mobile Documents`, `/Library/Application Support/com.apple.TCC`) [LOCAL]. The parent listing still works and the entry's own attributes are readable. Report "restricted", never 0. `EACCES` for ordinary permission denial. |
| EINVAL | Wrong bitmapcount, invalid or volume attribute, missing NAME/RETURNED_ATTRS. |
| EIO | Underlying I/O error. |
| EDEADLK | Documented by TN3150 for the dataless-materialization iopolicy when materialization is disabled. Not demonstrated for bulk here. |
| `ATTR_CMN_FULLPATH` | "may not be valid on all directory entries" in bulk; do not request it. Build paths from the name stack. |
| Mount point | `DIR_MNTSTATUS_MNTPOINT` set; attributes are the covered directory's [LOCAL man]. |
| Firmlink | `SF_FIRMLINK` in flags; attributes are the firmlink's, not the target's [LOCAL man]. |

`RDIRENT`: the term appears nowhere in the SDK headers, `getattrlistbulk(2)`, `getattrlist(2)`, nor the current public xnu `bsd/sys/attr.h` [LOCAL][WEB]. UNVERIFIED what is meant; no RDIRENT-specific handling is documented. The only directory-reading warning on record is that mixing `readdir` with `getattrlistbulk` on one fd is undefined.

## 4.5 Descent strategy

1. Open the root with `open(path, O_RDONLY|O_DIRECTORY|O_NOFOLLOW)`; open children with `openat(parentfd, name, O_RDONLY|O_DIRECTORY|O_NOFOLLOW)` to avoid path-length limits and TOCTOU.
2. Per directory: loop `getattrlistbulk` until 0 (with the ERANGE rule), tally files inline, queue subdirectories, close the fd. Bound the number of open fds.
3. Skip before opening: `SF_FIRMLINK` entries on the System-root walk, mount points, real-dev mismatches, synthetic names.
4. Cross-directory parallelism is fine. No performance numbers were measured: UNVERIFIED.

## 4.6 Dataless handling

Set the per-thread materialization policy to OFF on scanner threads (3.8) so listing a dataless iCloud folder does not download it, and handle `EDEADLK`. That the policy also governs `getattrlistbulk`'s own materialization is inferred from TN3150, not demonstrated here: UNVERIFIED.

## 4.7 Full Disk Access: what it protects, how to detect it

Observed EPERM without FDA [LOCAL]: `~/Library/Safari`, `~/Library/Mobile Documents`, `/Library/Application Support/com.apple.TCC`.
Also protected according to general knowledge, not probed here (UNVERIFIED): `~/Library/Mail`, `~/Library/Messages`, Time Machine backups, Address Book/Calendars data, other apps' Containers/Group Containers, Photos library content. Desktop/Documents/Downloads/removable-volume access is governed by separate per-folder TCC prompts.

Consequences for accuracy:
- Without FDA the home folder is undercounted. Record every EPERM directory as "restricted" and show a banner "totals exclude N protected folders".
- stat and the parent's bulk listing still return the protected directory's own entry, so it appears with unknown content size.

Non-prompting detection:
- Probe: `open(O_RDONLY|O_DIRECTORY)` on a known FDA-protected directory, e.g. `~/Library/Safari`. Result here: EPERM (no FDA) [LOCAL]. Success means access is available. ENOENT is inconclusive (Safari never run). EPERM can also come from Endpoint Security or MDM, so it means "not granted or blocked".
- No prompt appeared in the headless test; whether a GUI app triggers one for `~/Library/Safari` is UNVERIFIED. Do not probe Desktop/Documents/Downloads/Photos (those prompt).
- Apple provides no supported API. DTS (Aug 2026, macOS 27 thread): the answer to "is there an API / a supported method / a reliable path" is "no", "there isn't currently a 'general' solution"; the advice is to spot-check known critical locations and tell the user FDA "might be the issue". Endpoint Security can make access fail even with FDA [WEB https://developer.apple.com/forums/thread/841091].
- Do not use `TCC.db`: the same thread reports reading `~/Library/Application Support/com.apple.TCC/TCC.db` returns access denied on macOS 27 even with FDA (false negative), and its location/format are unsupported details [WEB].
- Implement as a tri-state `granted | notGranted | unknown` over a short list of probe directories. Only `~/Library/Safari` is verified as a silent probe, and only on macOS 15.7.9; re-verify on macOS 26 and 27 before shipping.
- Deep link to the Full Disk Access pane: `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles` (`[KNOWLEDGE]`, UNVERIFIED).

---

# Open items not resolved

1. Apple's own text for the `volumeAvailableCapacity*` keys (page fetched empty); why Opportunistic < Available.
2. Numeric values of `EF_NO_XATTRS`, `EF_IS_SYNC_ROOT`, `EF_IS_PURGEABLE`, `EF_IS_SYNTHETIC`.
3. Size attributes and EF flags of a real `SF_DATALESS` file.
4. Whether bulk honours `FSOPT_RETURN_REALDEV`.
5. Partial-clone family accounting (validated for full clones only).
6. The ERANGE-at-end-of-directory quirk on macOS 15, 26, 27.
7. FDA probe behaviour and prompting on macOS 26 and 27, and in a GUI process.
8. Vendor-doc verification of npm, pip, conda, Yarn, Maven, CocoaPods, SwiftPM and Docker `--volumes` claims tagged `[KNOWLEDGE]`; those rows are capped at REVIEW until verified.
9. Sizes of the Part 2 plumbing items (need root/FDA and a populated volume).
10. Apple confirmation for "do not modify the Photos library package" and the Archives/dSYM consequences.
11. What `RDIRENT` refers to.
