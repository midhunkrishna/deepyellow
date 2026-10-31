# FAQ

## Is it safe to use?

It is built so that mistakes are hard. Nothing is marked for you, nothing happens until you open the Plan and apply it, apply only moves items to the Trash, and one step undoes it. Protected places such as your home folder, system folders and Photos libraries can never be planned for removal. Details: [Safety and accounting](safety-and-accounting.md).

Reading a disk is also safe. DeepYellow never modifies the files it scans.

## Can I try it on my real disk without any risk?

Yes: `deepyellow ~ --read-only` does a real scan in which nothing can be moved to the Trash. See [Command line](cli.md#open-the-app). `deepyellow --demo` uses a made-up disk instead.

## Does it phone home?

No. There is no network code in the app, and no telemetry or analytics. You can check: the source is open, and [building it yourself](building-from-source.md) is a supported route.

## Does it use AI?

No, and that is on purpose. Advice comes from a table of rules written down in the open ([Reclaim rules](reclaim-rules.md)), plus facts the app can measure: size, age, kind, which app owns a folder, whether two files are identical. A guess about your own files would be the wrong thing to automate, so you decide.

Measured on one 188 GB home folder with 2.18 million files: the built-in rules and file signatures brought bytes of unknown kind from 45% down to 12%. About 65% of the bytes there still have no safety advice, which is the honest part only the owner can judge, and the factual [worklists](views.md#worklists) cover 68 GB of that. This is one folder, not a promise about yours.

## Why does it say "no advice" for most of my files?

Because the honest answer for photos, documents, downloads and projects is that DeepYellow cannot know whether you still want them. It would rather say nothing than round up to "safe". The [worklists](views.md#worklists) give you factual ways to look: large and untouched for a year, exact duplicates, leftovers of apps that are gone.

## Why does macOS block it?

The release build is not notarized, because notarization needs a paid Apple developer account. See [If macOS blocks it](install.md#if-macos-blocks-it) for the steps on macOS 15 and later, or [build it yourself](building-from-source.md) and macOS will not complain at all.

## Can I really clone it and build it?

Yes. `git clone https://github.com/midhunkrishna/deepyellow` then `make app`. It needs the Swift 6 toolchain.

## Why are the numbers different from Finder?

Finder and DeepYellow answer slightly different questions. DeepYellow measures allocated space, counts hard links and APFS clones once, and reports snapshots and purgeable space separately. The [Ledger](safety-and-accounting.md#the-ledger) reconciles the total against the volume and puts anything left over in a labelled remainder rather than hiding it.

## Why is there a gap between what I free and what the Plan said?

The Plan says "frees at least" only when that is true. Space shared with something you keep, such as cloned files, may not come back, and Trash frees nothing until you empty it.

## Does it handle iCloud Drive?

Files that live only in iCloud are shown as placeholders with their size, and DeepYellow never downloads them: not in a scan, a preview or a duplicate check. A preview of one shows metadata and a Download button you must press yourself.

## Which macOS versions?

macOS 15 or later, on Apple silicon and Intel.

## Do I need Full Disk Access?

For a complete scan of your whole disk, yes. Without it macOS hides some folders from the app, and DeepYellow counts and reports them as unreadable instead of leaving them out silently. You can scan one folder you own without the permission. See [Full Disk Access](install.md#full-disk-access).

## Can the command-line tool delete anything?

No. It is read-only, and there is no delete command, by design. See [Command line](cli.md).

## Is there a light mode?

Not in this version. The idea of the app depends on a dark canvas where gold stands out.

## Can I scan a network drive or an external disk?

External disks that macOS mounts as volumes are listed and can be scanned. Network volumes are not a tested target.

## Does it keep scanning in the background or update live?

No. A scan is a snapshot, and you rescan to refresh. Live updates and rescanning a single folder are not in this version. The app does not draw, and uses no GPU, while nothing is changing on screen.

## What does it store, and where?

Decisions, the scan cache and the removal journal under `~/Library/Application Support/DeepYellow`. [Uninstall](uninstall.md) lists every path.

## What does it cost?

Nothing. It is open source under the MIT licence.

## How do I report a problem?

Open an issue on [GitHub](https://github.com/midhunkrishna/deepyellow/issues). Please do not paste real file names if they are private.
