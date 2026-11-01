import DYAdvisor
import DYCore
import DYDecide
import DYScan
import Foundation

/// A Trash mover that only records what it was asked to do. It never touches the disk.
///
/// Fingerprints and existence come from the demo tree plus the mover's own in-memory record of what has been moved.
public final class DemoTrash: TrashMoving, @unchecked Sendable {
    /// One request the mover received.
    public enum Call: Equatable, Sendable {
        case moveToTrash(String)
        case moveBack(from: String, to: String)
    }

    private let lock = NSLock()
    private var recorded: [Call] = []
    /// Trashed location by original path, for items currently in the pretend Trash.
    private var trashed: [String: String] = [:]
    private var counter = 0
    private var refused: Set<String> = []
    private let fingerprint: @Sendable (String) -> Fingerprint?

    /// Creates a mover that looks fingerprints up with `fingerprint`.
    public init(fingerprint: @escaping @Sendable (String) -> Fingerprint?) { self.fingerprint = fingerprint }

    /// Every request so far, in order.
    public var calls: [Call] { lock.withLock { recorded } }

    /// Makes later moves of `paths` fail with a permission error, to show what a failed Apply looks like.
    public func refuseMoves(of paths: [String]) {
        lock.withLock { refused.formUnion(paths) }
    }

    /// Records the request and pretends the item is in the Trash.
    public func moveToTrash(path: String) throws -> String {
        try lock.withLock {
            guard !refused.contains(path) else { throw POSIXError(.EPERM) }
            guard trashed[path] == nil, fingerprint(path) != nil else { throw POSIXError(.ENOENT) }
            counter += 1
            let location = "/.DeepYellowDemoTrash/\(counter)/\((path as NSString).lastPathComponent)"
            trashed[path] = location
            recorded.append(.moveToTrash(path))
            return location
        }
    }

    /// Records the request and pretends the item is back. Refuses when the destination is taken.
    public func moveBack(from: String, to: String) throws {
        try lock.withLock {
            guard trashed[to] == from else { throw POSIXError(.ENOENT) }
            trashed[to] = nil
            recorded.append(.moveBack(from: from, to: to))
        }
    }

    /// The fingerprint the demo tree holds for `path`, unless the item is in the pretend Trash.
    public func currentFingerprint(path: String) throws -> Fingerprint {
        guard !lock.withLock({ trashed[path] != nil }), let found = fingerprint(path) else { throw POSIXError(.ENOENT) }
        return found
    }

    /// Whether `path` is in the demo disk, or is a pretend trashed location.
    public func exists(path: String) -> Bool {
        lock.withLock {
            if trashed[path] != nil { return false }
            return trashed.values.contains(path) || fingerprint(path) != nil
        }
    }
}

/// Builds the sample disk: `SyntheticTree` plus a few deterministic additions that make worklists, leftovers, duplicates
/// and kind refinement show something.
enum DemoDisk {
    static let home = "/Users/demo"
    private static let megabyte: UInt64 = 1_000_000

    /// A file the sample adds, with its place and size.
    struct Extra {
        var parent: String
        var name: String
        var megabytes: UInt64
        var ageDays: Int
        var kind: FileKind = .other
    }

    /// Files whose content the demo reader makes identical, by group. Kept small so a duplicate search is quick.
    static let duplicateGroups: [[(String, String)]] = [
        [("/Users/demo/Downloads", "Receipts-2023.zip"), ("/Users/demo/Downloads", "Receipts-2023 (1).zip")],
        [("/Users/demo/Documents", "lecture-recording.m4a"), ("/Users/demo/Documents/Notes", "lecture-recording copy.m4a")],
        [("/Users/demo/Movies", "intro-take2.mov"), ("/Users/demo/Movies/Exports", "intro-take2.mov")],
    ]

    /// An extensionless file the demo reader gives a ZIP header, so kind refinement has something to find.
    static let mystery = "/Users/demo/Downloads/capture-0412"

    static let extras: [Extra] = [
        Extra(parent: "/Users/demo/Downloads", name: "Receipts-2023.zip", megabytes: 60, ageDays: 480, kind: .archive),
        Extra(parent: "/Users/demo/Downloads", name: "Receipts-2023 (1).zip", megabytes: 60, ageDays: 470, kind: .archive),
        Extra(parent: "/Users/demo/Documents", name: "lecture-recording.m4a", megabytes: 55, ageDays: 600, kind: .audio),
        Extra(parent: "/Users/demo/Documents/Notes", name: "lecture-recording copy.m4a", megabytes: 55, ageDays: 590, kind: .audio),
        Extra(parent: "/Users/demo/Movies", name: "intro-take2.mov", megabytes: 70, ageDays: 350, kind: .video),
        Extra(parent: "/Users/demo/Movies/Exports", name: "intro-take2.mov", megabytes: 70, ageDays: 340, kind: .video),
        Extra(parent: "/Users/demo/Downloads", name: "capture-0412", megabytes: 900, ageDays: 330),
        Extra(parent: "/Users/demo/Library/Application Support/com.vanished.photoeditor", name: "library.db", megabytes: 410, ageDays: 800),
        Extra(parent: "/Users/demo/Library/Application Support/com.vanished.photoeditor", name: "previews.bin", megabytes: 230, ageDays: 800),
        Extra(parent: "/Users/demo/Library/Application Support/Old Editor Pro", name: "projects.dat", megabytes: 150, ageDays: 900),
        Extra(parent: "/Users/demo/Library/Caches/com.example.retiredtool", name: "cache.bin", megabytes: 120, ageDays: 700),
    ]

    /// Builds the sample tree. Deterministic.
    static func make() -> FileTree {
        let base = SyntheticTree.make()
        let builder = TreeBuilder(rootPath: "/", rootRecord: record(base, 0, flagsToAdd: []))
        var mapped = [NodeID](repeating: 0, count: base.count)
        for index in 1..<base.count {
            let id = NodeID(index)
            let extraFlags: NodeFlags = base.name(id) == "Docker.raw" ? [.mayShareBlocks] : []
            mapped[index] = builder.add(parent: mapped[Int(base.parent(id))], name: base.name(id), record: record(base, id, flagsToAdd: extraFlags))
        }
        var folders: [String: NodeID] = [:]
        for index in 0..<base.count { folders[base.path(NodeID(index))] = mapped[index] }
        var inode: UInt64 = 9_000_000
        func folder(_ path: String) -> NodeID {
            if let found = folders[path] { return found }
            let parentPath = (path as NSString).deletingLastPathComponent
            let created = builder.add(parent: folder(parentPath), name: (path as NSString).lastPathComponent,
                                      record: NodeRecord(allocated: 4_096, logical: 4_096, modified: SyntheticTree.referenceNow - 800 * 86_400,
                                                         accessed: SyntheticTree.referenceNow - 800 * 86_400, flags: [.directory], inode: inode))
            inode += 1
            folders[path] = created
            return created
        }
        for extra in extras {
            let size = extra.megabytes * megabyte
            let modified = SyntheticTree.referenceNow - Int32(extra.ageDays * 86_400)
            builder.add(parent: folder(extra.parent), name: extra.name,
                        record: NodeRecord(allocated: size, logical: size, modified: modified, accessed: modified, kind: extra.kind, inode: inode))
            inode += 1
        }
        return builder.freeze(meta: ScanMeta(rootPath: "/", scannedAt: Date(timeIntervalSince1970: TimeInterval(SyntheticTree.referenceNow))))
    }

    /// The node's own attributes, with a directory's children taken out of its subtree totals.
    private static func record(_ tree: FileTree, _ id: NodeID, flagsToAdd: NodeFlags) -> NodeRecord {
        var allocated = tree.allocated(id), logical = tree.logical(id), privateBytes = tree.privateBytes(id)
        for child in tree.children(id) {
            allocated -= min(allocated, tree.allocated(child))
            logical -= min(logical, tree.logical(child))
            privateBytes -= min(privateBytes, tree.privateBytes(child))
        }
        return NodeRecord(allocated: allocated, logical: logical, privateBytes: privateBytes, modified: tree.modified(id),
                          accessed: tree.accessed(id), flags: tree.flags(id).union(flagsToAdd), kind: tree.kind(id), inode: tree.inode(id))
    }
}

/// Builds the sample disk once, when first asked, and shares it.
final class DemoDiskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var built: FileTree?

    /// The sample tree.
    var tree: FileTree {
        lock.withLock {
            if let built { return built }
            let tree = DemoDisk.make()
            built = tree
            return tree
        }
    }
}

/// Deterministic file contents for the demo: duplicate groups read identical bytes, and the mystery file reads as a ZIP.
struct DemoFileReader: FileReading {
    var groups: [String: Int]
    var sizes: [String: UInt64]
    var headers: [String: Data]

    /// Returns the demo content of `path` at `offset`.
    func read(path: String, offset: UInt64, length: Int) throws -> Data {
        if let header = headers[path] {
            guard offset == 0 else { return Data() }
            return header.prefix(length)
        }
        guard let group = groups[path] else {
            let seed = path.utf8.reduce(UInt64(14_695_981_039_346_656_037)) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
            return Data(repeating: UInt8(truncatingIfNeeded: seed), count: min(length, 64))
        }
        let size = sizes[path] ?? 0
        let count = Int(min(UInt64(length), size > offset ? size - offset : 0))
        return Data(repeating: UInt8(truncatingIfNeeded: group + 1), count: count)
    }
}

/// Apps the demo pretends are installed.
struct DemoAppCatalog: AppCatalog {
    private let apps = [AppIdentity(bundleID: "com.apple.Safari", name: "Safari"), AppIdentity(bundleID: "com.spotify.client", name: "Spotify"),
                        AppIdentity(bundleID: "com.google.Chrome", name: "Google Chrome"), AppIdentity(bundleID: "com.docker.docker", name: "Docker"),
                        AppIdentity(bundleID: "com.figma.Desktop", name: "Figma"), AppIdentity(bundleID: "com.apple.dt.Xcode", name: "Xcode")]

    /// The demo app with this bundle identifier.
    func app(bundleID: String) -> AppIdentity? { apps.first { $0.bundleID?.lowercased() == bundleID.lowercased() } }

    /// The demo app with this name.
    func app(named name: String) -> AppIdentity? { apps.first { $0.name.lowercased() == name.lowercased() } }
}

/// Measured figures for the demo: the Docker disk image shares blocks, so deleting it frees less than it occupies.
struct DemoProbe: ReclaimProbing {
    var measured: [String: UInt64]

    /// The measured figure for `path`, or nil.
    func privateBytes(path: String) -> UInt64? { measured[path] }
}

extension WorkspaceEnvironment {
    /// An environment on the sample disk. The Trash mover is in memory and records calls, so Apply and Undo change nothing
    /// on disk. Any scan request returns the sample disk.
    public static func demo(dataDirectory: URL) -> WorkspaceEnvironment {
        let box = DemoDiskBox()
        let trash = DemoTrash(fingerprint: { path in
            let tree = box.tree
            return tree.find(path: path).map { Fingerprint(tree: tree, node: $0) }
        })
        var environment = WorkspaceEnvironment(
            homePath: DemoDisk.home, dataDirectory: dataDirectory, mover: trash, appCatalog: DemoAppCatalog(),
            reader: demoReader(box), probe: demoProbe(box),
            clock: { Date(timeIntervalSince1970: TimeInterval(SyntheticTree.referenceNow)) },
            startScan: { _ in
                ScanHandle(events: AsyncStream { continuation in
                    continuation.yield(.finished(box.tree))
                    continuation.finish()
                }, cancel: {})
            })
        environment.sampleDisk = { box.tree }
        environment.keepsTrashJournal = false
        environment.savesScanCache = false
        environment.kindRefinementMinimumSize = 100_000_000
        environment.duplicateMinimumSize = 50_000_000
        let volume = VolumeInfo(name: "Demo Disk", path: "/", total: 494_384_795_648, available: 88_000_000_000,
                                availableForImportantUsage: 95_000_000_000, isInternal: true)
        environment.sampleLedger = SampleLedger(hardlinkBytesSaved: 2_410_000_000, cloneBytesSaved: 6_180_000_000,
                                                unreadableDirectories: 0, volume: volume)
        environment.volumeForRoot = { _ in volume }
        environment.volumes = { [volume] }
        return environment
    }

    /// The demo reader, with duplicate groups resolved against the sample tree.
    private static func demoReader(_ box: DemoDiskBox) -> FileReading {
        let tree = box.tree
        var groups: [String: Int] = [:], sizes: [String: UInt64] = [:]
        for (index, group) in DemoDisk.duplicateGroups.enumerated() {
            for (parent, name) in group {
                let path = parent + "/" + name
                groups[path] = index
                if let node = tree.find(path: path) { sizes[path] = tree.logical(node) }
            }
        }
        let zip = Data([0x50, 0x4B, 0x03, 0x04] + [UInt8](repeating: 0, count: 64))
        return DemoFileReader(groups: groups, sizes: sizes, headers: [DemoDisk.mystery: zip])
    }

    /// The demo probe: the Docker image frees 60% of what it occupies.
    private static func demoProbe(_ box: DemoDiskBox) -> ReclaimProbing {
        let tree = box.tree
        let path = DemoDisk.home + "/Library/Containers/com.docker.docker/Data/Docker.raw"
        guard let node = tree.find(path: path) else { return DemoProbe(measured: [:]) }
        return DemoProbe(measured: [path: tree.allocated(node) / 10 * 6])
    }
}
