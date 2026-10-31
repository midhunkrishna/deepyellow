import Foundation

/// The raw columns of a `FileTree`. Exposed so `ScanCache` can persist them without copying node by node.
///
/// Invariants, established by `TreeBuilder.freeze` and relied on everywhere:
/// - Nodes are in breadth-first order, so `parent[i] < i` for all `i > 0`.
/// - A node's children are contiguous, starting at `firstChild`, and sorted by `allocated` descending.
/// - Directory `allocated`, `logical`, `privateBytes` and `fileCount` are subtree totals.
public struct FileTreeColumns: Sendable {
    public var parent: [Int32] = []
    public var firstChild: [Int32] = []
    public var childCount: [Int32] = []
    public var allocated: [UInt64] = []
    public var logical: [UInt64] = []
    public var privateBytes: [UInt64] = []
    public var fileCount: [UInt32] = []
    public var modified: [Int32] = []
    public var accessed: [Int32] = []
    public var flags: [UInt16] = []
    public var kind: [UInt8] = []
    public var inode: [UInt64] = []
    public var nameOffset: [UInt32] = []
    public var nameLength: [UInt16] = []
    public var nameBytes: [UInt8] = []

    public init() {}
}

/// An immutable, struct-of-arrays snapshot of a scanned directory tree. Safe to read from any thread.
public final class FileTree: @unchecked Sendable {
    public let columns: FileTreeColumns
    public let meta: ScanMeta
    public let count: Int

    /// Wraps columns that already satisfy the `FileTreeColumns` invariants.
    public init(columns: FileTreeColumns, meta: ScanMeta) {
        self.columns = columns
        self.meta = meta
        self.count = columns.parent.count
    }

    /// The root node. Its name is the full root path.
    public var root: NodeID { 0 }

    /// The parent of a node, or `noNode` for the root.
    @inline(__always) public func parent(_ id: NodeID) -> NodeID { columns.parent[Int(id)] }

    /// The ids of a node's children, sorted by `allocated` descending.
    @inline(__always) public func children(_ id: NodeID) -> Range<NodeID> {
        let first = columns.firstChild[Int(id)]
        return first < 0 ? 0..<0 : first..<(first + columns.childCount[Int(id)])
    }

    /// Bytes on disk after dedupe. For a directory, the subtree total.
    @inline(__always) public func allocated(_ id: NodeID) -> UInt64 { columns.allocated[Int(id)] }

    /// Finder-style logical bytes. For a directory, the subtree total.
    @inline(__always) public func logical(_ id: NodeID) -> UInt64 { columns.logical[Int(id)] }

    /// Bytes that deleting this node would free immediately. A lower bound when blocks are shared.
    @inline(__always) public func privateBytes(_ id: NodeID) -> UInt64 { columns.privateBytes[Int(id)] }

    /// Number of files in the subtree. A file reports 1.
    @inline(__always) public func fileCount(_ id: NodeID) -> UInt32 { columns.fileCount[Int(id)] }

    /// Modification time, in seconds since 1970.
    @inline(__always) public func modified(_ id: NodeID) -> Int32 { columns.modified[Int(id)] }

    /// Access time, in seconds since 1970. Filesystems update this loosely, so label it as approximate.
    @inline(__always) public func accessed(_ id: NodeID) -> Int32 { columns.accessed[Int(id)] }

    /// The node's flags.
    @inline(__always) public func flags(_ id: NodeID) -> NodeFlags { NodeFlags(rawValue: columns.flags[Int(id)]) }

    /// The node's file category.
    @inline(__always) public func kind(_ id: NodeID) -> FileKind { FileKind(rawValue: columns.kind[Int(id)]) ?? .other }

    /// The file id recorded at scan time. Used to detect that a path now refers to a different file.
    @inline(__always) public func inode(_ id: NodeID) -> UInt64 { columns.inode[Int(id)] }

    /// Whether the node is a directory, including packages.
    @inline(__always) public func isDirectory(_ id: NodeID) -> Bool { columns.flags[Int(id)] & NodeFlags.directory.rawValue != 0 }

    /// Calls `body` with the node's raw UTF-8 name without allocating.
    @inline(__always) public func withName<R>(_ id: NodeID, _ body: (UnsafeBufferPointer<UInt8>) -> R) -> R {
        let offset = Int(columns.nameOffset[Int(id)]), length = Int(columns.nameLength[Int(id)])
        return columns.nameBytes.withUnsafeBufferPointer { body(UnsafeBufferPointer(rebasing: $0[offset..<(offset + length)])) }
    }

    /// The node's name. For the root, the full root path.
    public func name(_ id: NodeID) -> String { withName(id) { String(decoding: $0, as: UTF8.self) } }

    /// The node's distance from the root.
    public func depth(_ id: NodeID) -> Int {
        var depth = 0
        var current = id
        while current > 0 { current = parent(current); depth += 1 }
        return depth
    }

    /// The node's absolute path.
    public func path(_ id: NodeID) -> String {
        var parts: [String] = []
        var current = id
        while current > 0 { parts.append(name(current)); current = parent(current) }
        let rootPath = name(0)
        guard !parts.isEmpty else { return rootPath }
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        return prefix + parts.reversed().joined(separator: "/")
    }

    /// Finds a node by absolute path, or returns nil if it isn't in this tree.
    public func find(path target: String) -> NodeID? {
        let rootPath = name(0)
        if target == rootPath { return 0 }
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard target.hasPrefix(prefix) else { return nil }
        var current: NodeID = 0
        for part in target.dropFirst(prefix.count).split(separator: "/") {
            let wanted = Array(part.utf8)
            let match = children(current).first { child in
                withName(child) { $0.elementsEqual(wanted) }
            }
            guard let match else { return nil }
            current = match
        }
        return current
    }

    /// Node ids from the root down to `id`, inclusive.
    public func ancestry(_ id: NodeID) -> [NodeID] {
        var chain: [NodeID] = []
        var current = id
        while current >= 0 { chain.append(current); current = parent(current) }
        return chain.reversed()
    }

    /// Whether `ancestor` is `id` or one of its ancestors.
    public func isAncestor(_ ancestor: NodeID, of id: NodeID) -> Bool {
        var current = id
        while current > ancestor { current = parent(current) }
        return current == ancestor
    }
}

extension FileTree {
    /// A tree with the same nodes and columns but different file kinds, sharing every other column.
    ///
    /// `kinds` must hold one `FileKind` raw value per node. A column of the wrong length changes nothing and returns `self`.
    public func replacingKinds(_ kinds: [UInt8]) -> FileTree {
        guard kinds.count == count else { return self }
        var replaced = columns
        replaced.kind = kinds
        return FileTree(columns: replaced, meta: meta)
    }
}
