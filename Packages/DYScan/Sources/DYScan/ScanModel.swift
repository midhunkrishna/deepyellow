import DYCore
import Foundation

/// Which global duplicate-detection a file takes part in.
enum LinkDedupe: UInt8 {
    case none, hardLink, clone
}

/// One directory entry as measured by a worker, before it has a node id.
struct ScannedEntry {
    var nameOffset: Int32
    var nameLength: UInt16
    var flags: NodeFlags
    var kind: FileKind
    var dedupe: LinkDedupe
    /// Index into `DirectoryBatch.subdirectoryPaths`, or -1 when the scanner won't descend.
    var subdirectoryIndex: Int32
    /// For a directory, how many entries it holds, or -1 when unknown.
    var entryCount: Int32
    var allocated: UInt64
    var logical: UInt64
    var privateBytes: UInt64
    var modified: Int32
    var accessed: Int32
    var fileID: UInt64
    var cloneID: UInt64
    var device: UInt32
}

/// Names a directory before it has a node id: the worker that discovered it and that worker's running count.
///
/// Workers hand out tokens themselves, so reading a directory never waits for the aggregator. The scan root is `root`.
struct DirectoryToken: Hashable {
    static let root = DirectoryToken(rawValue: UInt64.max)
    private static let sequenceBits: UInt64 = 40

    let rawValue: UInt64

    /// Creates the token for the `sequence`-th directory discovered by `worker`.
    init(worker: Int, sequence: UInt64) { rawValue = UInt64(worker) << Self.sequenceBits | sequence }

    private init(rawValue: UInt64) { self.rawValue = rawValue }

    /// The worker that discovered this directory.
    var worker: Int { Int(rawValue >> Self.sequenceBits) }

    /// This directory's position in its worker's discovery order.
    var sequence: Int { Int(rawValue & ((1 << Self.sequenceBits) - 1)) }

    /// The token `offset` places after this one in the same worker's order.
    func advanced(by offset: Int) -> DirectoryToken { DirectoryToken(rawValue: rawValue + UInt64(offset)) }
}

/// A directory still to be read. `path` is NUL-terminated so it can go straight to the C calls.
struct ScanJob {
    var token: DirectoryToken
    var path: [UInt8]
    var context: PhaseContext
    /// Only the scan root is opened through a symlink; everything below it is opened without following.
    var followSymlink: Bool
    /// How many entries the directory is known to hold, or -1. Zero means there is nothing to open.
    var expectedEntries: Int32 = -1
}

/// Everything a worker learned about one directory.
struct DirectoryBatch {
    var token: DirectoryToken
    var path: [UInt8]
    var entries: [ScannedEntry] = []
    var names: [UInt8] = []
    var subdirectoryPaths: [[UInt8]] = []
    /// Token of the first subdirectory; the rest follow consecutively in `subdirectoryPaths` order.
    var firstSubdirectoryToken = DirectoryToken.root
    /// `errno` from opening the directory, or 0.
    var openError: Int32 = 0
    /// `errno` from a listing that failed part-way, or 0.
    var listError: Int32 = 0
    /// True when cancellation stopped the scan before this directory was read.
    var skipped = false
    var context: PhaseContext
}

/// What differs between the passes of one scan.
struct ScanPolicy {
    var skipFirmlinks: Bool

    private static let rootPath = Array("/".utf8) + [0]
    private static let systemPath = Array("/System".utf8) + [0]
    private static let syntheticNames = [".vol", ".file", ".nofollow", ".resolve"].map { Array($0.utf8) }
    private static let volumesName = Array("Volumes".utf8)

    /// Whether an entry should be left out of the tree entirely, because another pass covers it or it is plumbing.
    func skips(directory path: [UInt8], name: UnsafeBufferPointer<UInt8>, fsFlags: UInt32) -> Bool {
        guard skipFirmlinks else { return false }
        if fsFlags & Bulk.sfFirmlink != 0 { return true }
        if path == Self.rootPath { return Self.syntheticNames.contains { name.elementsEqual($0) } }
        if path == Self.systemPath { return name.elementsEqual(Self.volumesName) }
        return false
    }
}

/// The per-pass facts every worker needs to decide whether to cross a directory boundary.
struct PhaseContext {
    var rootDevice: UInt32?
    var policy: ScanPolicy
    /// Ask the kernel for every file's private size, at roughly twice the cost per entry.
    var exactPrivateSize = false
}

/// One pass over a root directory. A whole-disk scan is two passes that merge into one tree.
struct ScanPhase {
    var path: String
    var policy: ScanPolicy
    /// Remember the directories this pass creates, so a later pass can merge into them.
    var recordsOverlay: Bool
    /// Merge directories of the same name into those an earlier pass recorded.
    var usesOverlay: Bool
}

/// Chooses the passes for a root path.
enum ScanPlan {
    static let dataVolumePath = "/System/Volumes/Data"

    /// A whole-disk scan reads the sealed System volume without its firmlinks, then merges the Data volume over it.
    static func phases(forRoot root: String) -> [ScanPhase] {
        guard root == "/" else {
            return [ScanPhase(path: root, policy: ScanPolicy(skipFirmlinks: false), recordsOverlay: false, usesOverlay: false)]
        }
        return [
            ScanPhase(path: "/", policy: ScanPolicy(skipFirmlinks: true), recordsOverlay: true, usesOverlay: false),
            ScanPhase(path: dataVolumePath, policy: ScanPolicy(skipFirmlinks: false), recordsOverlay: false, usesOverlay: true),
        ]
    }

    /// Strips trailing slashes and makes the path absolute, without resolving symlinks.
    static func normalize(_ root: String) -> String {
        var path = root.hasPrefix("/") ? root : FileManager.default.currentDirectoryPath + "/" + root
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        return path
    }
}
