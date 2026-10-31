import Foundation

/// A view of a `FileTree` with hidden, filtered and removed nodes taken out and sizes re-totalled.
///
/// Building one is a single linear pass, so toggling an ignore rule or applying a query never needs a rescan.
/// All views read sizes through a lens rather than directly from the tree. Immutable and safe to read from any thread.
public final class TreeLens: @unchecked Sendable {
    public let tree: FileTree
    /// Effective bytes per node. Zero for excluded nodes.
    public let size: [UInt64]
    /// Effective file count per node. Zero for excluded nodes.
    public let files: [UInt32]
    /// Whether each node is visible through this lens.
    public let included: [Bool]
    /// Bytes hidden by ignore rules, counted at the topmost hidden node so nothing is counted twice.
    public let hiddenBytes: UInt64
    public let hiddenFiles: UInt64
    /// Bytes that aren't hidden but don't match the active query.
    public let filteredBytes: UInt64
    public let filteredFiles: UInt64
    /// Bytes for nodes already moved to the Trash in this session.
    public let removedBytes: UInt64

    /// Computes a lens.
    ///
    /// - Parameters:
    ///   - hidden: `true` hides a node and its entire subtree. From ignore rules.
    ///   - matches: `true` means the node passes the query. Only consulted for leaves, which includes directories
    ///     childless in a live snapshot. Nil means no query.
    ///   - removed: `true` means the node and its subtree are gone. Nil means none.
    public init(tree: FileTree, hidden: [Bool]? = nil, matches: [Bool]? = nil, removed: [Bool]? = nil) {
        let count = tree.count
        let columns = tree.columns
        var size = [UInt64](repeating: 0, count: count)
        var files = [UInt32](repeating: 0, count: count)
        var included = [Bool](repeating: false, count: count)
        var state = [UInt8](repeating: 0, count: count) // 0 visible, 1 hidden, 2 removed
        var hiddenBytes: UInt64 = 0, hiddenFiles: UInt64 = 0, removedBytes: UInt64 = 0

        for index in 0..<count {
            let parentState = index == 0 ? 0 : state[Int(columns.parent[index])]
            if parentState != 0 {
                state[index] = parentState
            } else if removed?[index] == true {
                state[index] = 2
                removedBytes &+= columns.allocated[index]
            } else if hidden?[index] == true {
                state[index] = 1
                hiddenBytes &+= columns.allocated[index]
                hiddenFiles &+= UInt64(columns.fileCount[index])
            }
        }

        // Children have larger ids than parents, so a reverse pass totals every subtree in one sweep.
        for index in stride(from: count - 1, through: 0, by: -1) where state[index] == 0 {
            let childCount = columns.childCount[index]
            var childrenRaw: UInt64 = 0
            var anyChildIncluded = false
            if childCount > 0 {
                let first = Int(columns.firstChild[index])
                for child in first..<(first + Int(childCount)) {
                    childrenRaw &+= columns.allocated[child]
                    size[index] &+= size[child]
                    files[index] &+= files[child]
                    anyChildIncluded = anyChildIncluded || included[child]
                }
            }
            let own = columns.allocated[index] &- childrenRaw
            if childCount == 0 {
                guard matches?[index] ?? true else { continue }
                size[index] = own
                files[index] = columns.fileCount[index]
                included[index] = true
            } else if matches == nil || anyChildIncluded {
                size[index] &+= own
                included[index] = true
            }
        }

        let rootTotal = columns.allocated.first ?? 0
        let rootFiles = UInt64(columns.fileCount.first ?? 0)
        self.tree = tree
        self.size = size
        self.files = files
        self.included = included
        self.hiddenBytes = hiddenBytes
        self.hiddenFiles = hiddenFiles
        self.removedBytes = removedBytes
        let visibleBytes = size.first ?? 0
        self.filteredBytes = rootTotal &- min(rootTotal, hiddenBytes &+ removedBytes &+ visibleBytes)
        self.filteredFiles = rootFiles &- min(rootFiles, hiddenFiles &+ UInt64(files.first ?? 0))
    }

    /// The value of `metric` for a node.
    @inline(__always) public func value(_ id: NodeID, _ metric: Metric) -> UInt64 {
        metric == .bytes ? size[Int(id)] : UInt64(files[Int(id)])
    }

    /// A node's visible children, largest first by `metric`. Excludes those whose value is zero.
    public func visibleChildren(of id: NodeID, metric: Metric = .bytes) -> [NodeID] {
        var result: [NodeID] = []
        for child in tree.children(id) where included[Int(child)] && value(child, metric) > 0 {
            result.append(child)
        }
        result.sort { a, b in
            let valueA = value(a, metric), valueB = value(b, metric)
            return valueA != valueB ? valueA > valueB : a < b
        }
        return result
    }

    /// For each node, the raw value of the `FileKind` holding the most bytes beneath it. Files report their own kind.
    public func dominantKinds() -> [UInt8] {
        let count = tree.count
        let kinds = FileKind.allCases.count
        var totals = [UInt64](repeating: 0, count: count * kinds)
        var result = [UInt8](repeating: FileKind.other.rawValue, count: count)
        let columns = tree.columns
        for index in stride(from: count - 1, through: 0, by: -1) {
            if columns.childCount[index] == 0 {
                result[index] = columns.kind[index]
                totals[index * kinds + Int(columns.kind[index])] = size[index]
            } else {
                var best = 0
                for kind in 0..<kinds where totals[index * kinds + kind] > totals[index * kinds + best] { best = kind }
                result[index] = UInt8(best)
            }
            if index > 0 {
                let parent = Int(columns.parent[index])
                for kind in 0..<kinds { totals[parent * kinds + kind] &+= totals[index * kinds + kind] }
            }
        }
        return result
    }
}
