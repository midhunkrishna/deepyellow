import Foundation

/// The measured attributes of one node, before tree layout is known.
public struct NodeRecord: Sendable {
    public var allocated: UInt64
    public var logical: UInt64
    public var privateBytes: UInt64
    public var modified: Int32
    public var accessed: Int32
    public var flags: NodeFlags
    public var kind: FileKind
    public var inode: UInt64

    /// Creates a record. Attributes left out default to zero.
    public init(allocated: UInt64 = 0, logical: UInt64 = 0, privateBytes: UInt64? = nil, modified: Int32 = 0,
                accessed: Int32 = 0, flags: NodeFlags = [], kind: FileKind = .other, inode: UInt64 = 0) {
        self.allocated = allocated
        self.logical = logical
        self.privateBytes = privateBytes ?? allocated
        self.modified = modified
        self.accessed = accessed
        self.flags = flags
        self.kind = kind
        self.inode = inode
    }
}

/// Assembles a tree incrementally from a single thread, keeping directory totals current so live snapshots are cheap.
///
/// Not thread-safe. Scanner workers must funnel their results through one aggregator.
public final class TreeBuilder {
    private var parent: [Int32] = []
    private var firstChild: [Int32] = []
    private var nextSibling: [Int32] = []
    private var allocated: [UInt64] = []
    private var logical: [UInt64] = []
    private var privateBytes: [UInt64] = []
    private var fileCount: [UInt32] = []
    private var modified: [Int32] = []
    private var accessed: [Int32] = []
    private var flags: [UInt16] = []
    private var kind: [UInt8] = []
    private var inode: [UInt64] = []
    private var nameOffset: [UInt32] = []
    private var nameLength: [UInt16] = []
    private var nameBytes: [UInt8] = []
    private let rootPath: String

    /// Creates a builder whose root node is named `rootPath`.
    public init(rootPath: String, rootRecord: NodeRecord = NodeRecord(flags: .directory), reserving capacity: Int = 1 << 16) {
        self.rootPath = rootPath
        reserve(capacity)
        var path = rootPath
        path.withUTF8 { _ = appendNode(parent: noNode, name: $0, record: rootRecord) }
    }

    /// Number of nodes added so far, including the root.
    public var count: Int { parent.count }

    /// The running total of allocated bytes under the root.
    public var totalAllocated: UInt64 { allocated[0] }

    /// The running total of files under the root.
    public var totalFiles: UInt32 { fileCount[0] }

    /// Adds a node under `parent`, returning its id, which is valid only within this builder.
    ///
    /// With `rollup` true the record's sizes are added to every ancestor. Pass false when adding a directory's
    /// entries in bulk, then call `applyRollup` once, which avoids walking the ancestors for each entry.
    @discardableResult
    public func add(parent parentID: NodeID, name: UnsafeBufferPointer<UInt8>, record: NodeRecord, rollup: Bool = true) -> NodeID {
        let id = appendNode(parent: parentID, name: name, record: record)
        nextSibling[Int(id)] = firstChild[Int(parentID)]
        firstChild[Int(parentID)] = id
        if rollup {
            applyRollup(from: parentID, allocated: record.allocated, logical: record.logical,
                        privateBytes: record.privateBytes, files: record.flags.contains(.directory) ? 0 : 1)
        }
        return id
    }

    /// Adds a node with a `String` name. Convenient for tests and synthetic trees; slower than the buffer form.
    @discardableResult
    public func add(parent parentID: NodeID, name: String, record: NodeRecord, rollup: Bool = true) -> NodeID {
        var name = name
        return name.withUTF8 { add(parent: parentID, name: $0, record: record, rollup: rollup) }
    }

    /// Adds sizes to `start` and all of its ancestors.
    public func applyRollup(from start: NodeID, allocated bytes: UInt64, logical logicalBytes: UInt64, privateBytes reclaimable: UInt64, files: UInt32) {
        var current = start
        while current >= 0 {
            let index = Int(current)
            allocated[index] &+= bytes
            logical[index] &+= logicalBytes
            privateBytes[index] &+= reclaimable
            fileCount[index] &+= files
            current = parent[index]
        }
    }

    /// Sets flags on an existing node, for example marking a directory unreadable after it failed to open.
    public func insertFlags(_ newFlags: NodeFlags, on id: NodeID) {
        flags[Int(id)] |= newFlags.rawValue
    }

    /// Produces the complete tree, with children sorted and nodes in breadth-first order.
    public func freeze(meta: ScanMeta? = nil) -> FileTree {
        build(expanding: nil, meta: meta ?? ScanMeta(rootPath: rootPath))
    }

    /// Produces a bounded copy for live display during a scan, keeping the largest directories expanded.
    ///
    /// Directories left unexpanded keep their true totals but appear childless, so the snapshot's sizes still add
    /// up. Cost is proportional to `maxNodes`, not to the number of nodes scanned.
    public func snapshot(maxNodes: Int = 200_000, meta: ScanMeta? = nil) -> FileTree {
        build(expanding: chooseExpandedDirectories(budget: maxNodes), meta: meta ?? ScanMeta(rootPath: rootPath))
    }

    private func reserve(_ capacity: Int) {
        parent.reserveCapacity(capacity)
        firstChild.reserveCapacity(capacity)
        nextSibling.reserveCapacity(capacity)
        allocated.reserveCapacity(capacity)
        logical.reserveCapacity(capacity)
        privateBytes.reserveCapacity(capacity)
        fileCount.reserveCapacity(capacity)
        modified.reserveCapacity(capacity)
        accessed.reserveCapacity(capacity)
        flags.reserveCapacity(capacity)
        kind.reserveCapacity(capacity)
        inode.reserveCapacity(capacity)
        nameOffset.reserveCapacity(capacity)
        nameLength.reserveCapacity(capacity)
    }

    private func appendNode(parent parentID: NodeID, name: UnsafeBufferPointer<UInt8>, record: NodeRecord) -> NodeID {
        let id = NodeID(parent.count)
        parent.append(parentID)
        firstChild.append(noNode)
        nextSibling.append(noNode)
        allocated.append(record.allocated)
        logical.append(record.logical)
        privateBytes.append(record.privateBytes)
        fileCount.append(record.flags.contains(.directory) ? 0 : 1)
        modified.append(record.modified)
        accessed.append(record.accessed)
        flags.append(record.flags.rawValue)
        kind.append(record.kind.rawValue)
        inode.append(record.inode)
        let storedLength = min(name.count, Int(UInt16.max))
        nameOffset.append(UInt32(nameBytes.count))
        nameLength.append(UInt16(storedLength))
        nameBytes.append(contentsOf: UnsafeBufferPointer(rebasing: name[0..<storedLength]))
        return id
    }

    /// Picks directories to expand, largest first, until their children would exceed the budget.
    private func chooseExpandedDirectories(budget: Int) -> Set<Int32> {
        var expanded = Set<Int32>()
        var frontier = MaxHeap { [allocated] (a: Int32, b: Int32) in allocated[Int(a)] < allocated[Int(b)] }
        frontier.push(0)
        var used = 1
        while let id = frontier.pop(), used < budget {
            expanded.insert(id)
            var child = firstChild[Int(id)]
            while child >= 0 {
                used += 1
                if firstChild[Int(child)] >= 0 { frontier.push(child) }
                child = nextSibling[Int(child)]
            }
        }
        return expanded
    }

    /// Lays nodes out breadth-first with sorted children, copying each column into its final order.
    private func build(expanding expanded: Set<Int32>?, meta: ScanMeta) -> FileTree {
        var order: [Int32] = [0]
        var newParent: [Int32] = [noNode]
        var newFirst: [Int32] = []
        var newCount: [Int32] = []
        order.reserveCapacity(expanded == nil ? parent.count : 1 << 12)
        var scratch: [Int32] = []
        var cursor = 0
        while cursor < order.count {
            let old = order[cursor]
            scratch.removeAll(keepingCapacity: true)
            if expanded?.contains(old) ?? true {
                var child = firstChild[Int(old)]
                while child >= 0 {
                    scratch.append(child)
                    child = nextSibling[Int(child)]
                }
            }
            if scratch.isEmpty {
                newFirst.append(noNode)
                newCount.append(0)
            } else {
                sortBySizeDescending(&scratch)
                newFirst.append(Int32(order.count))
                newCount.append(Int32(scratch.count))
                order.append(contentsOf: scratch)
                newParent.append(contentsOf: repeatElement(Int32(cursor), count: scratch.count))
            }
            cursor += 1
        }
        return FileTree(columns: copyColumns(order: order, parent: newParent, first: newFirst, count: newCount), meta: meta)
    }

    /// Sorts by allocated size descending, breaking ties by id so ordering is deterministic.
    private func sortBySizeDescending(_ ids: inout [Int32]) {
        allocated.withUnsafeBufferPointer { sizes in
            ids.sort { a, b in
                let sizeA = sizes[Int(a)], sizeB = sizes[Int(b)]
                return sizeA != sizeB ? sizeA > sizeB : a < b
            }
        }
    }

    private func copyColumns(order: [Int32], parent newParent: [Int32], first: [Int32], count: [Int32]) -> FileTreeColumns {
        var columns = FileTreeColumns()
        columns.parent = newParent
        columns.firstChild = first
        columns.childCount = count
        columns.allocated = order.map { allocated[Int($0)] }
        columns.logical = order.map { logical[Int($0)] }
        columns.privateBytes = order.map { privateBytes[Int($0)] }
        columns.fileCount = order.map { fileCount[Int($0)] }
        columns.modified = order.map { modified[Int($0)] }
        columns.accessed = order.map { accessed[Int($0)] }
        columns.flags = order.map { flags[Int($0)] }
        columns.kind = order.map { kind[Int($0)] }
        columns.inode = order.map { inode[Int($0)] }
        columns.nameOffset = order.map { nameOffset[Int($0)] }
        columns.nameLength = order.map { nameLength[Int($0)] }
        columns.nameBytes = nameBytes
        return columns
    }
}

/// A small binary max-heap over node ids, ordered by the given comparison.
struct MaxHeap {
    private var items: [Int32] = []
    private let isLess: (Int32, Int32) -> Bool

    /// Creates an empty heap. `isLess(a, b)` returns true when `a` should come out after `b`.
    init(isLess: @escaping (Int32, Int32) -> Bool) { self.isLess = isLess }

    /// Adds an item.
    mutating func push(_ item: Int32) {
        items.append(item)
        var child = items.count - 1
        while child > 0 {
            let parent = (child - 1) / 2
            guard isLess(items[parent], items[child]) else { break }
            items.swapAt(parent, child)
            child = parent
        }
    }

    /// Removes and returns the greatest item, or nil when empty.
    mutating func pop() -> Int32? {
        guard let top = items.first else { return nil }
        let last = items.removeLast()
        guard !items.isEmpty else { return top }
        items[0] = last
        var parent = 0
        while true {
            let left = 2 * parent + 1, right = left + 1
            var largest = parent
            if left < items.count, isLess(items[largest], items[left]) { largest = left }
            if right < items.count, isLess(items[largest], items[right]) { largest = right }
            if largest == parent { break }
            items.swapAt(parent, largest)
            parent = largest
        }
        return top
    }
}
