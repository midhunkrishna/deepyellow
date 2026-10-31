# Command line

The `deepyellow` command reads a folder and prints what the app would show. **It is read-only and has no delete command, by design.** Nothing you can type to a subcommand changes a file, and the commands that suggest cleanups only print them.

## Setting it up

The command and the app are one binary: `DeepYellow.app/Contents/MacOS/DeepYellow` serves both. `Contents/Resources/bin/deepyellow` is a small script that follows its own symlink and runs the binary in command mode. The name `deepyellow` is a symlink because `DeepYellow` and `deepyellow` would collide on a case-insensitive disk.

Link it with **DeepYellow > Install Command Line Tool...** (it asks first, and offers `~/.local/bin`, which needs no administrator rights) or with the [one-line installer](install.md#route-2-the-one-line-installer). Check it works:

```
deepyellow --version
```

## Commands

```
deepyellow <path>                        open the app on a folder (works when already running)
deepyellow --demo                        open the app on the sample disk
deepyellow <path> --read-only            open the app on a real scan where nothing can be moved
deepyellow things <path> [--min 100mb] [--top N] [--json]
deepyellow reclaim <path> [--json]
deepyellow spectrum <path> [--json]
deepyellow dupes <path> [--min 1mb] [--json]
deepyellow --version | --help
```

### Open the app

`deepyellow <path>` opens DeepYellow on the folder, and uses the running app if there is one. The same thing works from Finder, because folders are registered as documents: `open -a DeepYellow <path>`, dropping a folder on the Dock icon, and Open With all work.

`deepyellow --demo` opens the built-in sample disk, which is made up and never touches your files. A demo always starts a new instance, so it does not take over a window that is already scanning something real.

**`--read-only` is the natural way to try the app on a real disk with zero risk.** Both `deepyellow <path> --read-only` and `deepyellow --read-only <path>` do a real scan, so the sizes, the map and the advice are real, and in that mode nothing can be moved to the Trash.

`deepyellow --print-open-args <path>` (it can be combined with the other open flags) prints what would be launched, which app, which folder, which arguments and whether a new instance would be used, and launches nothing. It is meant for scripts and tests.

### `things`

Ranked list of the biggest [Things](views.md#things) under a path: files and folders as peers, cut at a size threshold so the list is disjoint and adds up to the total.

| Option | Meaning |
|---|---|
| `--min <size>` | Threshold, for example `100mb` or `1gb`. Without it the threshold is chosen to give about 25 rows. |
| `--top <N>` | Show only the largest N rows. **This truncates the list, so a truncated list does not add up to the total.** The header still shows the whole total. |
| `--json` | Machine-readable output |

Sizes use decimal units, `b kb mb gb tb`.

```
$ deepyellow things ~/Downloads --min 1mb --top 5
Things under ~/Downloads  ·  47.2 MB total  ·  cut at 1.00 MB  ·  5 rows

  ████████████████████    13.6 MB     29%  Install macOS.pkg
  ████████████▎           8.39 MB     18%  Xcode_15.2.zip
  █████████▎              6.29 MB     13%  Ubuntu-24.04.iso
  █████████▎              6.29 MB     13%  old-backup.zip
  █████████▎              6.29 MB     13%  design-handoff/Ubuntu-copy.iso
```

*The output above is real, from a small made-up folder with names like the demo disk.* The header gives the total, the threshold used, and the number of rows shown. Each row has a bar, the size, the share of the total, and the path relative to the folder.

### `reclaim`

Groups what it finds by [safety tier](safety-and-accounting.md#tiers) using the [built-in rules](reclaim-rules.md), then prints the worklists: forgotten large things, leftovers of apps that look gone, and the largest things you have not decided about. Where a rule has an official cleanup command, it is printed, never run. Duplicates are not read here; use `dupes`.

```
$ deepyellow reclaim ~/Downloads
Reclaim under ~/Downloads  ·  47.2 MB scanned

Safety groups
  none of the built-in rules match here

Worklists
  Largest, undecided: 47.2 MB in 8 items
      The 8 biggest things you haven't decided on, 47.2 MB in all.
        13.6 MB  Install macOS.pkg
        8.39 MB  Xcode_15.2.zip
        6.29 MB  Ubuntu-24.04.iso
        6.29 MB  old-backup.zip
        6.29 MB  design-handoff/Ubuntu-copy.iso
  Duplicates: not read here. Run `deepyellow dupes <path>`.
```

(The sample folder is not under a place any rule knows about, so no safety group matches. On a real home folder the groups appear first.)

### `spectrum`

Prints the [Spectrum](views.md#spectrum): how many files and how many bytes fall in each size range, three ranges per decade.

```
$ deepyellow spectrum ~/Downloads
Spectrum of ~/Downloads  ·  8 files  ·  47.2 MB

  size range                    files   bytes
  1.00 MB to 2.00 MB                1   ▉                        1.05 MB
  2.00 MB to 5.00 MB                2   ████▋                    5.24 MB
  5.00 MB to 10.0 MB                4   ████████████████████████ 27.3 MB
  10.0 MB to 20.0 MB                1   ████████████             13.6 MB

The 5 largest files hold 80% of the bytes.
```

### `dupes`

Lists exact duplicates: the same size, the same head and tail, and the same SHA-256. Hard links and clones of the same data are not duplicates, and iCloud placeholders are skipped, never downloaded. Files are read, never changed. `--min` sets the smallest file considered and defaults to `1mb`.

```
$ deepyellow dupes ~/Downloads --min 1mb
Duplicates under ~/Downloads  ·  6.29 MB wasted in 1 sets  ·  13.0 MB read

  ██████████████    6.29 MB wasted  2 copies of 6.29 MB
      Ubuntu-24.04.iso
      design-handoff/Ubuntu-copy.iso
```

## Colour, piping and `NO_COLOR`

- On a terminal you get truecolor bars.
- When output is piped or redirected, or when `NO_COLOR` is set, no colour codes are written. The bars are still drawn with block characters, so the text reads the same.
- `--json` prints one JSON document on standard output.

## JSON

Every subcommand takes `--json`. Keys are written in a stable order and sizes are integer bytes. The shape of each is given by its own `--help`:

```
things    {"path", "total", "thresholdBytes", "things": [{"path", "name", "bytes", "files",
          "kind": "item" | "rest", "items"?}]}
          A "rest" row stands for the smaller items inside "path".
reclaim   {"path", "total", "groups": [{"id", "title", "tier", "bytes", "reclaimableBytes",
          "files", "items", "cleanupCommand"}], "worklists": [{"kind", "title", "why", "bytes",
          "files", "items", "top": [{"path", "bytes"}]}]}
spectrum  {"path", "totalFiles", "totalBytes", "filesHolding80PercentOfBytes",
          "bins": [{"lower", "upper", "files", "bytes"}]}
dupes     {"path", "bytesHashed", "wastedBytes", "sets": [{"size", "copies", "wastedBytes",
          "paths": [...]}]}
```

Real output of `things --json --top 2` on the same folder:

```
{
  "path" : "~/Downloads",
  "things" : [
    {
      "bytes" : 13631488,
      "files" : 1,
      "kind" : "item",
      "name" : "Install macOS.pkg",
      "path" : "~/Downloads/Install macOS.pkg"
    },
    {
      "bytes" : 8388608,
      "files" : 1,
      "kind" : "item",
      "name" : "Xcode_15.2.zip",
      "path" : "~/Downloads/Xcode_15.2.zip"
    }
  ],
  "thresholdBytes" : 1000000,
  "total" : 47185920
}
```

## Exit codes and errors

| Code | Meaning |
|---|---|
| `0` | Success |
| `2` | The path does not exist or is not a folder. A message goes to standard error. |
| `64` | Bad arguments: an unknown option, a missing or extra path, an invalid size. A message goes to standard error. |

## Examples

Anything over 1 GB, as JSON, into `jq`:

```
deepyellow things ~ --min 1gb --json | jq '.things[].path'
```

A report with no colour:

```
NO_COLOR=1 deepyellow reclaim ~ > reclaim-report.txt
```

## Permissions

A scan from a terminal can only read what macOS allows that terminal to read. macOS usually applies the permission of the terminal application, so if protected folders such as parts of `~/Library` are reported as unreadable, grant Full Disk Access to your terminal app. Unreadable folders are counted and reported, not hidden. See [Full Disk Access](install.md#full-disk-access).
