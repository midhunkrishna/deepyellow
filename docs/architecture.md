# Architecture

DeepYellow is native Swift with Metal for the map. Each module is its own Swift package under `Packages/`, depends only on `DYCore`, and has its own tests, so a change in one cannot break the build of another.

## Modules

| Package | Responsibility |
|---|---|
| `DYCore` | The shared vocabulary: the compact file tree, file kinds, safety tiers, decisions, the colour palette, number formatting, and the synthetic tree used for demos and tests |
| `DYScan` | The scanner, the scan cache, volume information, and the Full Disk Access probe |
| `DYAnalysis` | Ignore rules, the [query language](query-language.md), Things, Spectrum and Field |
| `DYAdvisor` | The [reclaim rules](reclaim-rules.md), duplicate finding, app ownership and worklists |
| `DYDecide` | Decisions, the removal Plan and its guards, and the Trash executor with its journal |
| `DYRender` | The Metal map, Rings and Field canvases |
| `DYPreview` | Preview of video, images, audio, PDFs and text |
| `DYWorkspace` | A headless model that all of the interface binds to: scan lifecycle, selection, lenses, decisions, plan and apply |
| `DYLenses` | The SwiftUI views for each lens |
| `Sources/DeepYellow` | The app and command-line entry point |

There is no network code in any module. The only way a file is ever moved is through one protocol, `TrashMoving`, and the real implementation is handed to the workspace by the app's entry point alone. The `--demo` mode hands it an in-memory fake, which is enforced by a test.

## The file tree

A scan produces one flat, columnar tree: parallel arrays for size, file count, timestamps, kind and flags, indexed by a node number. A million-node tree is a handful of arrays rather than a million objects, which is what makes scanning, queries and the map fast on millions of nodes. A `TreeLens` is a filtered view of that tree, which is how a query or a hide rule changes every lens without copying.

## Scanning

The scanner reads directories in bulk with `getattrlistbulk`, with several workers feeding a single thread that owns the tree builder. Accounting follows macOS rules rather than adding up file sizes:

- Allocated size, not logical size, is the default measure.
- Hard links are counted once, and so are APFS clones that share all their data.
- Device boundaries use the real device id, so other mounted volumes are not entered and the Data volume is not double counted when scanning `/`.
- iCloud placeholders are detected and are never materialized by a read.
- Unreadable folders are counted and reported.

Scans publish snapshots while they run, so the map is interactive from the first second, and every scan can be cancelled and ends with a tree that says whether it is partial. Finished scans are cached under `~/Library/Application Support/DeepYellow/scans/`.

## Things

Things cuts the tree at a size threshold `T`, not at a depth. A file or folder is a thing when it is at least `T` and cannot be split into anything at least `T`. A folder with a big child is split and the remainder is rolled into one "N smaller items" row, or carried upward if that is still under `T`. A test asserts, for every threshold and in both bytes and file-count metrics, that results are disjoint and sum exactly to the total. The cut is fast enough to run on every slider tick.

## Kinds without guessing

Every file has a kind. It is resolved in three steps that never involve a model:

1. A table of extensions, then macOS's own type information for extensions not in the table.
2. For files still classed as `other` above a size limit, a signature check on the first bytes of the file. Only a short header is read. Placeholders and restricted files are skipped, so nothing is downloaded.
3. A few corrections where size changes the answer, such as a very large `.raw` file, which is a disk image rather than a camera file.

## Reclaim

A rule has a path pattern, a tier, one sentence on what the place is, one on what removing it costs, optional conditions, an optional cleanup command (displayed, never run) and a source. The matcher supports `~`, `**`, alternatives, exclusions and `if-sibling:` conditions, so `node_modules` is offered as rebuildable when a lockfile sits next to it and as review when it does not. The most specific rule wins, and a `never` ancestor always wins. See [Reclaim rules](reclaim-rules.md).

Ownership adds facts without changing tiers: it looks only at the direct children of a fixed list of `~/Library` folders and decides whether the owning app appears to be installed. It never applies to `com.apple.*`, and a plain name that matches nothing is only "possibly not installed".

## Plan and Trash

`RemovalPlanner` turns decisions into the minimal set of roots and applies the guards listed in [Safety and accounting](safety-and-accounting.md#the-plan). The guards run inside the planner regardless of input, so no caller can bypass them. `TrashExecutor` re-checks each fingerprint just before moving, writes a journal so a step can be undone, and has no code path that deletes.

## Rendering

The map is drawn with Metal using instanced rounded rectangles and a fragment shader for lighting, hatches and stipple. Layout is lazy and in world space: each folder lays out its children only when it is visible and large enough, and zooming moves a camera instead of recomputing the layout. Tiles too small to see become one dust tile per folder, which lays out the next chunk recursively when you zoom in. Drawing is on demand, so there is no display link while nothing animates and idle costs no GPU.

## Measured

| Measure | Figure | Conditions |
|---|---|---|
| Things cut | under 3 ms | 4.86 million nodes |
| Queries | 23 to 42 ms | 4.86 million nodes |
| Map zoom | about 200 fps, estimated at p95 | M4, offscreen, 4.86 million nodes |
| Scan | about 150,000 files per second | A home folder of 2.18 million files, machine under load |

These are single measurements on one machine, and your results will differ.

## The site

`docs/*.md` is the single source of the documentation. `python3 scripts/build-site-docs.py` renders it into `web/docs/` with the site's chrome, using only the Python standard library, and `python3 scripts/check-site-links.py` verifies every link and image. The site in `web/` is plain HTML, CSS and a little JavaScript, with no build step and no external requests.
