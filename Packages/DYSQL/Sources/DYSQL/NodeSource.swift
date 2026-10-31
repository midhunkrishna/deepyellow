import DYCore
import Foundation

/// What the `nodes` table reads. Holds the captured context and answers each column for a node without copying the tree.
///
/// Used from one thread at a time, because a connection is never shared.
final class NodeSource {
    let tree: FileTree
    let lens: TreeLens
    let decisions: [UInt8]
    let safety: [UInt8]
    let now: Int32
    let count: Int
    private let flags: [UInt16]
    private var depths: [Int32] = []
    /// Scratch space for lower-casing extensions.
    var extensionScratch = [UInt8](repeating: 0, count: 512)

    /// Captures `context`.
    init(_ context: SQLContext) {
        tree = context.tree
        lens = context.lens
        decisions = context.decisions
        safety = context.safety
        now = context.now
        count = context.tree.count
        flags = context.tree.columns.flags
    }

    /// Whether a node has the flag.
    @inline(__always) func has(_ flag: NodeFlags, _ index: Int) -> Bool { flags[index] & flag.rawValue != 0 }

    /// Bytes as the views count them: the lens figure when visible, else the tree's own.
    @inline(__always) func size(_ index: Int) -> Int64 {
        Int64(bitPattern: lens.included[index] ? lens.size[index] : tree.columns.allocated[index])
    }

    /// File count as the views count it.
    @inline(__always) func fileCount(_ index: Int) -> Int64 {
        lens.included[index] ? Int64(lens.files[index]) : Int64(tree.columns.fileCount[index])
    }

    /// The node's distance from the root, computed for the whole tree on first use.
    func depth(_ index: Int) -> Int64 {
        if depths.isEmpty {
            var computed = [Int32](repeating: 0, count: count)
            let parents = tree.columns.parent
            for node in 1..<max(count, 1) { computed[node] = computed[Int(parents[node])] + 1 }
            depths = computed
        }
        return Int64(depths[index])
    }

    /// The raw decision value for a node, or 0.
    @inline(__always) func decision(_ index: Int) -> UInt8 { index < decisions.count ? decisions[index] : 0 }

    /// The raw safety tier for a node, or 0.
    @inline(__always) func tier(_ index: Int) -> UInt8 { index < safety.count ? safety[index] : 0 }

    /// The range of node ids whose parent is `parent`, or empty.
    func childRange(of parent: Int) -> Range<Int> {
        let first = Int(tree.columns.firstChild[parent])
        let number = Int(tree.columns.childCount[parent])
        return first < 0 || number == 0 ? 0..<0 : first..<(first + number)
    }
}

/// C strings that outlive every statement, so text columns that have a fixed set of values never allocate.
enum StaticText {
    /// A NUL-terminated string kept for the life of the process.
    struct Entry {
        let pointer: UnsafePointer<CChar>
        let length: Int32
    }

    private static func make(_ values: [String]) -> [Entry] {
        values.map { value in
            let bytes = Array(value.utf8CString)
            let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: bytes.count)
            buffer.initialize(from: bytes, count: bytes.count)
            return Entry(pointer: UnsafePointer(buffer), length: Int32(bytes.count - 1))
        }
    }

    /// Indexed by `FileKind` raw value.
    static let kinds = make(["video", "image", "audio", "document", "code", "application", "archive", "other"])
    /// Indexed by `Decision` raw value; entry 0 is unused.
    static let marks = make(["", "keep", "remove", "later"])
    /// Indexed by `SafetyTier` raw value; entry 0 is unused.
    static let tiers = make(["", "safe", "rebuild", "review", "never"])
}
