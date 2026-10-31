# Build contract

Product intent: `docs/DESIGN.md`. Shared types: `Packages/DYCore` (complete, tested, read it first, don't edit it; report gaps instead).

**Layout.** Each module is its own SwiftPM package under `Packages/`, depending only on `DYCore`, so an agent's build can't be broken by a sibling. Tools 6.0, `.macOS(.v15)`, `.swiftLanguageMode(.v5)` on every target. Copy `Packages/DYCore/Package.swift` as the template; depend with `.package(path: "../DYCore")`.

**Test command.** `swift test --package-path Packages/<Name>`. All tests: `scripts/test-all.sh`.

**Rules for every module.**
- Every function and method gets a doc comment; one responsibility per type and method. Match the style of `DYCore`.
- Tests use `SyntheticTree` or temp directories. Tests and tools must never modify, trash or delete anything outside their own temp directory, and must never print names from a user's personal files.
- No network code anywhere.
- Long operations accept cancellation and never block the main thread.

## Ownership

| Package | Owner | Wave |
|---|---|---|
| `Packages/DYCore` | orchestrator | 0 |
| `Packages/DYScan` | scan | 1 |
| `Packages/DYAnalysis` | analysis | 1 |
| `Packages/DYAdvisor` | advisor | 1 |
| `Packages/DYDecide` | decide | 1 |
| `Packages/DYRender` | render | 1, Rings and Field added in 2 |
| `Packages/DYPreview` | preview | 1 |
| `Package.swift`, `Sources/DeepYellow`, `scripts/` | app | 2 |

## DYScan
Reference: `docs/research/reclaim-kb.md` Part 3 (accounting), Part 4 (enumeration).

```swift
public struct ScanOptions { public var root: String; public var workers: Int /* default activeProcessorCount */
    public var snapshotInterval: TimeInterval /* 0.25 */; public var snapshotMaxNodes: Int /* 200_000 */; public init(root: String) }
public struct ScanProgress: Sendable { files, directories: Int; bytes: UInt64; unreadable: Int; elapsed: TimeInterval; currentPath: String }
public enum ScanEvent: Sendable { case progress(ScanProgress); case snapshot(FileTree); case finished(FileTree) }
public final class DiskScanner: @unchecked Sendable {
    public init(options: ScanOptions)
    public func start() -> AsyncStream<ScanEvent>   // always ends with .finished, including after cancel (partial tree, meta says so)
    public func cancel()
}
public enum ScanCache { static func save(_: FileTree, to: URL) throws; static func load(from: URL) throws -> FileTree
    static func defaultURL(forRoot: String) -> URL /* ~/Library/Application Support/DeepYellow/scans/ */ }
public struct VolumeInfo: Sendable, Identifiable { id, name, path: String; total, available, availableForImportantUsage: UInt64; isInternal: Bool
    static func mounted() -> [VolumeInfo] }
public enum FullDiskAccess { case granted, denied, unknown; static func probe() -> FullDiskAccess; static func openSettings() }
```
Executable `dy-bench <path>`: scans and prints file count, directories, bytes, seconds, files/sec, unreadable. No file names.

**Decided.** Parallel `getattrlistbulk` work queue feeding one aggregator thread that owns the `TreeBuilder`. Use `add(rollup:false)` plus one `applyRollup` per directory. Honour the KB's findings: `ATTR_CMNEXT_REALDEVID` for device boundaries, not `st_dev`; hard-link dedupe on (real dev, fileid); full-clone dedupe on (real dev, cloneid) with `EF_SHARES_ALL_BLOCKS`; `IOPOL_MATERIALIZE_DATALESS_FILES_OFF` on every worker; read the returned attribute set, never assume. Whole-disk scan of `/` shows familiar real paths (`/Users/…`), doesn't double count the Data volume, and skips `/System/Volumes` plumbing. Never cross into other mounts: flag `.mountBoundary`. Package detection via cached per-extension lookup. A filename longer than `UInt16.max` is impossible on APFS; don't special-case. Target: above 300k files/sec on this M4 for a warm scan of `$HOME`, and report the real number.

**Test seams.** Temp dirs containing hard links, `cp -c` clones, symlinks, unreadable dirs (chmod 000, restored in teardown), deep nesting and non-UTF8-safe names. Assert totals and flags. `ScanCache` round-trips exactly.

## DYAnalysis
```swift
public struct IgnoreRule: Codable, Identifiable, Sendable { id: UUID; pattern: String; enabled: Bool; label: String; isPreset: Bool }
public struct IgnoreRuleSet: Codable, Sendable { rules: [IgnoreRule]; static let defaults: IgnoreRuleSet }
public struct IgnoreResult: Sendable { hidden: [Bool]; perRule: [UUID: (bytes: UInt64, files: UInt64)] }
public enum IgnoreEngine { static func evaluate(_: IgnoreRuleSet, tree: FileTree, home: String, isCancelled: () -> Bool) -> IgnoreResult? }

public struct Query: Sendable, Equatable { static func parse(_: String) -> Query; var isEmpty: Bool; var errors: [String]; var text: String }
public struct QueryContext: Sendable { decisions: [UInt8]; safety: [UInt8]; now: Int32 }
public enum QueryEngine { static func matches(_: Query, tree: FileTree, context: QueryContext, isCancelled: () -> Bool) -> [Bool]? }

public enum ThingContent: Sendable, Hashable { case node(NodeID); case rest(parent: NodeID, items: Int) }
public struct Thing: Sendable, Identifiable, Hashable { id: Int; content: ThingContent; value: UInt64; files: UInt64 }
public struct ThingsResult: Sendable { items: [Thing]  /* sorted by value descending */; total: UInt64 }
public enum ThingsEngine {
    static func cut(lens: TreeLens, under: NodeID, threshold: UInt64, metric: Metric) -> ThingsResult
    static func isAtom(tree: FileTree, node: NodeID) -> Bool
    static func thresholdForApproximately(items: Int, lens: TreeLens, under: NodeID, metric: Metric) -> UInt64
}

public struct SpectrumBin: Sendable { lower, upper: UInt64; count: UInt64; bytes: UInt64; bytesByKind: [UInt64]; countByKind: [UInt64] }
public struct SpectrumResult: Sendable { bins: [SpectrumBin] /* powers of 10 split in 3 per decade */; curve: [(itemShare: Double, byteShare: Double)]; itemsForShare: (Double) -> Int; totalFiles: UInt64; totalBytes: UInt64 }
public enum SpectrumEngine { static func compute(lens: TreeLens, under: NodeID) -> SpectrumResult }

public enum FieldClock: Sendable { case modified, accessed }
public struct FieldData: Sendable { positions: [SIMD2<Float>] /* x: log10 age days, y: log10 bytes */; kinds: [UInt8]; nodes: [NodeID]; ageRange, sizeRange: ClosedRange<Float> }
public enum FieldEngine { static func compute(lens: TreeLens, under: NodeID, clock: FieldClock, maxPoints: Int) -> FieldData }
```
**Decided.**
- Ignore patterns are gitignore-like, `~` expands to home, and `!` keeps visible and beats hide. Defaults from KB Part 2. `~/Library/Caches` must stay visible. Evaluate in one linear pass, inheriting downward, with no per-node path string building for simple name patterns. `perRule` totals count bytes once per topmost hidden node.
- Query terms: `size> size<`, `age> age<` (modified), `opened> opened<` (accessed), `kind:`, `ext:a,b`, `name:`, `path:`, `is:dir|clone|hardlink|package|dataless`, `mark:keep|remove|later|none`, `safe:safe|rebuild|review|never`. Bare words match name or path, case-insensitive. `-` negates. Units: b, kb, mb, gb, tb; s, h, d, w, m (months), y. Malformed terms go in `errors` and don't crash. `matches` sets files only, per the `TreeLens.matches` contract; `is:dir` matches every file beneath a matching directory. Target 5M nodes within 150 ms in release.
- `cut` follows `DESIGN.md` §2.2 exactly. Property to test: items are disjoint and always sum to the value at `under`, for any threshold, in both metrics. Atoms: packages plus `node_modules .git DerivedData .venv venv __pycache__ Pods target .gradle .next dist build .cache .pnpm-store`, where `target`, `dist` and `build` count only when a project marker such as `Cargo.toml` or `package.json` is a sibling. Atoms are cut only when `under` is that atom. Must be fast enough to run on every slider tick: 5M nodes within 50 ms for typical thresholds.
- `curve` has at most 512 points, sorted largest-first. `FieldEngine` keeps every file when under `maxPoints`, otherwise deterministically samples small files but always keeps large ones.

## DYAdvisor
Reference: `docs/research/reclaim-kb.md` Part 1. Evidence tags limit tiers: follow the KB, and never upgrade a row.

```swift
public struct ReclaimRule: Identifiable, Sendable { id, title, pattern: String; tier: SafetyTier; whatItIs, consequence: String; sideCondition, cleanupCommand: String?; ownerBundleIDs: [String]; source: String? }
public struct ReclaimFamily: Identifiable, Sendable { rule: ReclaimRule; nodes: [NodeID]; bytes, reclaimable: UInt64; files: UInt64; newestModified: Int32 }
public struct ReclaimReport: Sendable { families: [ReclaimFamily] /* tier, then bytes */; nodeTier: [UInt8]; func rule(for: NodeID, tree: FileTree) -> ReclaimRule? }
public enum ReclaimEngine { static let builtinRules: [ReclaimRule]; static func analyze(lens: TreeLens, home: String, rules: [ReclaimRule], isCancelled: () -> Bool) -> ReclaimReport? }

public struct DuplicateSet: Identifiable, Sendable { id: String /* hash */; nodes: [NodeID]; size: UInt64; var wastedBytes: UInt64 { get } }
public struct DuplicateReport: Sendable { sets: [DuplicateSet] /* wasted descending */; bytesHashed: UInt64; skippedDataless: Int }
public protocol FileReading: Sendable { func read(path: String, offset: UInt64, length: Int) throws -> Data }
public enum DuplicateFinder { static func find(lens: TreeLens, minimumSize: UInt64, reader: FileReading, progress: @Sendable (Double) -> Void, isCancelled: @Sendable () -> Bool) async -> DuplicateReport }
```
**Decided.** A rule inherits downward, the most specific wins, and a `never` ancestor always wins. Nothing is ever pre-marked; this module only advises. Duplicates: group by size, then head and tail hash, then full SHA-256 (CryptoKit), reading at most 1 MiB at a time. Skip `.dataless`, `.hardlinkDuplicate`, `.cloneDuplicate`, `.restricted` and files in packages. Two members of one clone family are not duplicates. `DuplicateSet.wastedBytes` is size × (members − 1).

**Test seams.** Rule matching on hand-built trees, including a `never` rule beating `safe`. Fake `FileReading` for duplicates.

## DYDecide
```swift
public struct Fingerprint: Codable, Sendable, Equatable { size: UInt64; modified: Int32; inode: UInt64 }
public final class DecisionStore: @unchecked Sendable {
    public init(fileURL: URL?)   // nil = in-memory
    public func set(_: Decision, paths: [String], tree: FileTree)  // one undo step; records fingerprints from tree
    public func undo() -> Bool; public func redo() -> Bool; public var version: Int { get }
    public func resolve(tree: FileTree) -> ResolvedDecisions
}
public struct ResolvedDecisions: Sendable { effective: [UInt8]; partial: [Bool]; stalePaths: [String]; removeBytes, keepBytes: UInt64; removeRoots, undecided: Int }
public struct PlanItem: Identifiable, Sendable { id: String /* path */; node: NodeID; bytes, reclaimable: UInt64; fingerprint: Fingerprint; reclaimIsLowerBound: Bool }
public struct BlockedItem: Sendable { path: String; reason: String }
public struct RemovalPlan: Sendable { items: [PlanItem]; protected: [String]; blocked: [BlockedItem]; totalBytes, totalReclaimable: UInt64 }
public enum RemovalPlanner { static func plan(tree: FileTree, resolved: ResolvedDecisions, nodeTier: [UInt8], home: String) -> RemovalPlan }
public protocol TrashMoving: Sendable { func moveToTrash(path: String) throws -> String /* trashed path */; func moveBack(from: String, to: String) throws; func currentFingerprint(path: String) throws -> Fingerprint }
public struct SystemTrash: TrashMoving
public struct ExecutionReport: Sendable { moved: [(original: String, trashed: String)]; skippedChanged: [String]; failed: [(path: String, error: String)]; bytesMoved: UInt64 }
public final class TrashExecutor: @unchecked Sendable {
    public init(mover: TrashMoving, journalURL: URL?)
    public func execute(_: RemovalPlan, progress: @Sendable (Double) -> Void, isCancelled: @Sendable () -> Bool) async -> ExecutionReport
    public func undoLast() async -> ExecutionReport?; public var canUndo: Bool { get }
}
```
**Decided.** Effective decision inherits downward; the deepest wins. A remove-marked directory holding a keep-marked descendant is split: its siblings are planned individually and the directory itself is never trashed. Plan items are minimal roots: never a parent and its child. Guards, enforced in `RemovalPlanner` regardless of input, go to `blocked`: tree root, `/`, home, ancestors of home, `/System /Applications /Library /Users /usr /bin /sbin /private /Volumes` and direct children of `/` generally, `~/Library` itself, `~/Documents ~/Desktop ~/Pictures ~/Movies ~/Music ~/Downloads` themselves, `.restricted`, `.mountBoundary`, `.unreadable`, tier `never`, and anything inside a `.photoslibrary`. A stale fingerprint is blocked too. `TrashExecutor` re-checks each fingerprint immediately before moving and skips changes. It has no code path that deletes.

**Test seams.** Fake `TrashMoving`; adversarial plans (mark root, mark home, shift-selected ancestor plus child, keep inside remove). One integration test moves a temp file using a fake mover over a temp directory. **Tests never use the real Trash.**

## DYRender
```swift
public struct CanvasEvents { var onHover: ((NodeID?, CGPoint) -> Void)?; var onClick: ((NodeID, NSEvent.ModifierFlags) -> Void)?; var onDoubleClick: ((NodeID) -> Void)?
    var onContextMenu: ((NodeID, NSEvent) -> Void)?; var onFocusChanged: ((NodeID) -> Void)? }
public protocol DiskCanvas: NSView {
    var events: CanvasEvents { get set }
    func update(lens: TreeLens, style: NodeStyle, metric: Metric, selection: Set<NodeID>, animated: Bool)
    func focus(on: NodeID, animated: Bool)
    func snapshot(size: CGSize, scale: CGFloat) -> CGImage?   // offscreen, no window required
}
public final class MapCanvas: NSView, DiskCanvas
public struct DiskCanvasView: NSViewRepresentable   // generic SwiftUI host for any DiskCanvas
```
Executable `dy-snap --canvas map [--focus <path>] [--color kind|age|safety|decision] [--metric bytes|files] --out x.png` renders `SyntheticTree` with decisions and safety. **Look at your own PNGs with the Read tool and iterate until they're beautiful.** Visual quality is an acceptance criterion here.

**Decided.**
- Metal, pipelines compiled at runtime from embedded source. On-demand drawing only, so idle costs zero GPU: no display link unless animating.
- Instanced rounded rects with an SDF fragment shader: cushion lighting, 1 px gaps, hatch for remove, pin for keep, dot for later, gold glow for safe tiers, stipple for dust.
- **Layout is world-space and lazy.** Each directory lays out its children inside its own rect only when visible and large enough; zoom moves a camera, nothing reflows. Use double precision for the camera and draw camera-relative. Target ratio around 3:2, not squares, avoiding extremes.
- **Dust.** A directory lays out its large children plus one tail tile standing for the rest. When the tail is big enough on screen, it recursively lays out the next chunk the same way. So layout per directory is bounded and dust resolves at any zoom.
- Directories large enough on screen get a header band with name and size. Tiles get labels when they fit. Labels are textured quads from a CoreText-rasterised LRU atlas, at most 300 per frame.
- On a lens change (rules, query), tween old to new rects by `NodeID`. Honour Reduce Motion.
- Input: scroll or pinch zooms around the cursor, drag pans, double-click zooms in. Hit testing via the same culled list, within one frame.
- Budgets: 120 fps while zooming on a 5M-node tree, measured in `dy-snap --bench`.

**Test seams.** Layout math is pure and testable with no GPU: tiles sum to the parent's area, no overlaps, ratios bounded, dust tail sums exact, layout deterministic.

## DYPreview
```swift
public struct PreviewItem: Sendable, Equatable { url: URL; name: String; size: UInt64; modified: Date?; kind: FileKind; isDirectory, isDataless: Bool; largestChildren: [PreviewChild] }
public struct PreviewChild: Sendable, Equatable { url: URL; name: String; size: UInt64; kind: FileKind; isDirectory: Bool }
public struct PreviewPane: View { init(item: PreviewItem?, controller: PreviewController) }
@MainActor public final class PreviewController: ObservableObject { func togglePlay(); func seek(by: Double); func zoom(by: Double); func prepare(_ upcoming: [PreviewItem]) }
public actor ThumbnailCache { static let shared: ThumbnailCache; func image(for: URL, side: CGFloat) async -> CGImage? }
```
Executable `dy-preview-demo` opens a window on a generated video, image, audio file, PDF and text file, for manual and screenshot checks.

**Decided.** Video: `AVPlayerView` without default chrome, plus a custom filmstrip scrubber from `AVAssetImageGenerator` (lazy, cached) with hover scrub. Image: ImageIO thumbnail at screen size first, full decode only on zoom; pan and zoom via `NSScrollView` or `CATiledLayer`. Audio: waveform from `AVAssetReader`, cached per URL. PDF: PDFKit. Text: first 256 KB in monospaced type. Everything else: `QLPreviewView`. Directory: composition of `largestChildren` thumbnails sized by share. **Dataless items never open their file**: show metadata and an explicit Download button. Never write to a previewed file. Use `prepare` to preload the next few items so Review advances within one frame. Generate fixtures in tests with `AVAssetWriter` and CoreGraphics into temp dirs.

---

# Wave 2: from modules to a shippable product

Machine safety rules in `CLAUDE.md` bind every agent. Product name **DeepYellow**, bundle id `com.midhunkrishna.deepyellow`, repo `github.com/midhunkrishna/deepyellow`, default branch `master`, licence MIT (Midhun Krishna).

| Owner | Files | Step |
|---|---|---|
| engines | `Packages/DYCore`, `Packages/DYAdvisor`, `Packages/DYDecide`, `Packages/DYScan` | 2a |
| render | `Packages/DYRender`, `docs/screens/map-*.png` | 2a |
| release | `Makefile`, `scripts/` except `build-site-docs.py` and `make-screens.sh`, `.github/`, `LICENSE`, `Resources/`, root `Package.swift`, placeholder `Sources/DeepYellow/main.swift` | 2a |
| site | `web/`, `docs/*.md` except `DESIGN.md`, `README.md`, `scripts/build-site-docs.py` | 2a |
| workspace | `Packages/DYWorkspace` | 2b |
| shell | `Sources/DeepYellow/**`, `scripts/make-screens.sh`, root `Package.swift` from step 2c on, `docs/screens/app-*.png` | 2c |
| lenses | `Packages/DYLenses` | 2c |

## Engines (classification without AI)
Measured on a real 188 GB home folder: 45% of bytes were kind `other`, 35 GB of that with no extension, and 64% had no safety advice. Goal: shrink `other` and turn "no advice" into factual worklists.

```swift
extension FileTree { public func replacingKinds(_ kinds: [UInt8]) -> FileTree } // same ids, shares all other columns
public enum TypeResolver { static func kind(forExtension: String) -> FileKind? } // UTType, cached per extension
public enum SignatureSniffer { static let headerLength: Int; static func kind(header: Data) -> FileKind? }
public struct KindRefinement: Sendable { kinds: [UInt8]; refinedFiles: Int; refinedBytes: UInt64 }
public enum KindRefiner { static func refine(lens: TreeLens, reader: FileReading, minimumSize: UInt64, isCancelled: @Sendable () -> Bool) async -> KindRefinement? }

public struct AppIdentity: Sendable, Equatable { bundleID: String?; name: String }
public protocol AppCatalog: Sendable { func app(bundleID: String) -> AppIdentity?; func app(named: String) -> AppIdentity? }
public struct SystemAppCatalog: AppCatalog
public enum Ownership: Sendable, Equatable { case installed(AppIdentity); case notInstalled(bundleID: String); case possiblyNotInstalled(name: String) }
public struct OwnedFolder: Sendable { node: NodeID; ownership: Ownership; bytes: UInt64; newestModified: Int32 }
public struct OwnershipReport: Sendable { folders: [OwnedFolder]; func owner(of: NodeID, tree: FileTree) -> OwnedFolder? }
public enum OwnershipEngine { static func analyze(lens: TreeLens, home: String, catalog: AppCatalog, isCancelled: () -> Bool) -> OwnershipReport? }

public enum WorklistKind: Sendable { case forgotten, duplicates, leftovers, largestUndecided }
public struct Worklist: Identifiable, Sendable { kind: WorklistKind; title, why: String; nodes: [NodeID]; bytes: UInt64; files: UInt64 }
public enum WorklistEngine { static func compute(lens: TreeLens, report: ReclaimReport, ownership: OwnershipReport, duplicates: DuplicateReport?, decisions: [UInt8], now: Int32) -> [Worklist] }

// DYDecide
public protocol ReclaimProbing: Sendable { func privateBytes(path: String) -> UInt64? }
extension RemovalPlanner { static func refine(_: RemovalPlan, probe: ReclaimProbing, isCancelled: @Sendable () -> Bool) async -> RemovalPlan }
// DYScan
public struct PrivateSizeProbe: Sendable { public init(); public func privateBytes(path: String) -> UInt64? }
```
**Decided.**
- Fix `.raw`: `Docker.raw` and any `.raw` above 1 GB is `archive`; extend the extension table using the measured list (`jsonl gguf safetensors weights img dat pack litertlm` and similar). Add `FileKind` only by table, never new cases.
- `KindRefiner` reads only `headerLength` bytes of files at or above `minimumSize` that are still `other`. Skip `.dataless` and `.restricted`. Never trigger a download.
- Ownership looks only at direct children of `~/Library/{Containers,Group Containers,Caches,Application Support,Preferences,Saved Application State,HTTPStorages,WebKit,Logs}`. `notInstalled` requires a bundle-id-shaped name and never applies to `com.apple.*` or a group container whose team id or suffix matches an installed app. A plain name in Application Support that matches nothing is only `possiblyNotInstalled`. Ownership never raises a tier: leftovers remain "look first".
- Worklists: **Forgotten** is a `ThingsEngine`-style cut, so files and folders are peers: items of at least 100 MB whose newest modification in the subtree is over a year old. **Duplicates** come from `DuplicateReport`. **Leftovers** are `notInstalled` plus `possiblyNotInstalled`, the latter labelled as a guess. **Largest undecided** is the top of a cut with no decision. All exclude `never`, `.restricted` and decided items. `why` is one concrete sentence with no hype.
- `DYAdvisor` may depend on `DYAnalysis` for the cut.
- Fingerprints: `Fingerprint.current` must compare the same size the scanner records (all forks, `ATTR_FILE_TOTALSIZE`). Add a test with a real resource fork in a temp directory.
- `RemovalPlanner.refine` sums probed private bytes per plan item, recursing nothing itself; `PrivateSizeProbe` walks a directory. Where a probe fails, keep the item's value and set `reclaimIsLowerBound` false, so "frees at least" is only ever stated when true. Add `RemovalPlan.estimateIsLowerBound: Bool`.

## Workspace
Headless `@MainActor @Observable` model all UI binds to. **No SwiftUI views, no Metal.** Testable with `SyntheticTree` and fake movers. Responsibilities: source selection (scan path, demo, cached scan); scan lifecycle with live snapshots and progress; recomputing `TreeLens` off the main thread with cancellation when rules, query or Trash state change; selection keyed by path so it survives snapshots, with count and bytes always available; focus and zoom; metric and colour mode; `NodeStyle` assembly; hide rules; query; decisions with undo and redo; plan and apply with Trash undo; reclaim report, ownership, worklists, duplicates (background), kind refinement; Things, Spectrum and Field results; ledger reconciliation; review session; building `PreviewItem`s.

**Decided.** `--demo` injects an in-memory `TrashMoving` that never touches disk, enforced by a test. All persistence goes under `DEEPYELLOW_HOME` when set, else `~/Library/Application Support/DeepYellow`. Unknown or partial data is exposed as such, never as zero. `Workspace` must not reference `SystemTrash` directly: the real mover is injected by the app's entry point only.

## Shell and CLI
`DeepYellow.app/Contents/MacOS/DeepYellow` is one binary for both GUI and CLI, since `DeepYellow` and `deepyellow` collide on a case-insensitive disk. `Contents/Resources/bin/deepyellow` is a small script that resolves its own symlink and runs the binary with `--cli "$@"`.

```
deepyellow <path>                        open the app on a path; works when already running
deepyellow --demo                        open the app on the sample disk
deepyellow things <path> [--min 100mb] [--top N] [--json]    ranked list in the terminal
deepyellow reclaim <path> [--json]       safety groups and worklists
deepyellow spectrum <path> [--json]      size histogram in the terminal
deepyellow dupes <path> [--json]         exact duplicates
deepyellow --version | --help
```
**The CLI is read-only and has no delete command, by design.** Truecolor bars on a TTY; plain when piped or under `NO_COLOR`; JSON is stable and documented. Unknown path: message on stderr, exit 2. Add a menu item "Install Command Line Tool…", which creates a symlink only after an explicit click, and offers `~/.local/bin` without admin rights. Register folders in `CFBundleDocumentTypes` so `open -a DeepYellow <path>`, drag onto the Dock and Open With all work.

Screenshot harness: `DeepYellow --demo --shot <name> --out <file>` renders offscreen with the sample disk, compositing `DiskCanvas.snapshot` into the window image. `scripts/make-screens.sh` produces every file below at 1600×1000, then `web/images/*.webp` with `cwebp`.

`app-map app-map-safety app-map-files app-things app-spectrum app-field app-rings app-browse app-reclaim app-worklists app-review app-plan app-ledger app-palette app-welcome` (`docs/screens/<name>.png`).

## Release
- **Could anyone build it?** Yes: `git clone … && make app` needs only Swift 6 tools. Verify from a clean clone in a temp directory.
- `make test | app | dmg | install PREFIX=…`. `scripts/build-app.sh`: universal binary (arm64, x86_64), `Info.plist`, generated icon, resources, ad-hoc signature, version stamped from `VERSION` env or `git describe`, else `0.0.0-dev`. Stable asset names: `DeepYellow.dmg`, `DeepYellow.zip`, `SHA256SUMS`.
- `scripts/install.sh`: `curl … | sh` installer: downloads the latest zip, verifies its checksum, installs to `~/Applications` by default or `--dir`, clears quarantine only on what it installed, symlinks the CLI into `~/.local/bin` or `--bin`, and prints exactly what it did. It never uses sudo silently and supports `--dry-run` and `--from-file`. An uninstall section in the docs lists the same paths.
- `scripts/next-version.sh`: semver from conventional commits since the last `vX.Y.Z` tag: `feat` minor, `fix` and anything else patch, `!` or `BREAKING CHANGE` major. No tag yet gives `0.1.0`. `chore(release)` and docs-only pushes make no release. Tested in temp repos.
- `.github/workflows/ci.yml` on PRs; `release.yml` on push to `master`: test, compute version, build universal, package, tag `vX.Y.Z`, publish a GitHub Release with generated notes. **No bot commit back to master; the tag is the source of truth.** If optional secrets (`MACOS_CERTIFICATE_P12`, `MACOS_CERTIFICATE_PASSWORD`, `NOTARY_*`) exist, sign with them and notarize; otherwise ad-hoc. Tests needing a GPU skip when `MTLCreateSystemDefaultDevice()` is nil. Use the toolchain's Swift 6 on `macos-15`.

## Site and docs
- `docs/*.md` is the single source of truth: `getting-started`, `install` (including Gatekeeper), `cli`, `views`, `query-language`, `safety-and-accounting`, `reclaim-rules`, `building-from-source`, `architecture`, `faq`, `uninstall`. Every page is linked from `docs/README.md`.
- `scripts/build-site-docs.py` (stdlib only) renders them to `web/docs/*.html` with the site's chrome. Output is committed.
- `README.md` is a sales page for a potential user: what it does, why it's different, screenshots, install; links into `docs/` for everything else.
- `web/` is plain static HTML and CSS with no build step or external requests. Structure is inspired by the owner's Marginalia site (https://marginalia.midhun-krishna-usa.workers.dev/) (index and features pages, read it; don't copy its branding) but it should feel like a **system tool**. Download buttons point at `https://github.com/midhunkrishna/deepyellow/releases/latest/download/DeepYellow.dmg`, and a Releases link at `/releases`.
- **"If macOS blocks it"** is a prominent section, on the site and in `docs/install.md`. Because the build is not notarized: why it happens, the System Settings > Privacy & Security > Open Anyway steps on macOS 15+ (Control-click no longer bypasses Gatekeeper since macOS 15), the `xattr` alternative with an honest note on what it does, how to verify the checksum, and building from source as the zero-trust route. Full Disk Access steps too, including that ad-hoc signed updates may require re-granting it.
- Only claim what's measured or tested. Real figures: Things cut under 3 ms and queries 23–42 ms on 4.86M nodes; map zoom about 200 fps estimated at p95 on M4 offscreen, 4.86M nodes; scan about 150k files/sec on a home folder of 2.18M files while the machine was under load. Use careful wording, and no competitor bashing.
