import DYCore
import Foundation

/// What one row of the Things list stands for.
public enum ThingContent: Sendable, Hashable {
    /// A whole file or directory.
    case node(NodeID)
    /// What is left of `parent` after its big children are listed: `items` smaller entries rolled together.
    case rest(parent: NodeID, items: Int)
}

/// One row of the Things list.
public struct Thing: Sendable, Identifiable, Hashable {
    /// Stable across thresholds: the node id for a node, and `-(parent + 1)` for a rest row.
    public var id: Int
    public var content: ThingContent
    /// The thing's size in the cut's metric.
    public var value: UInt64
    /// Files inside the thing.
    public var files: UInt64
}

/// A disjoint cut of a subtree.
public struct ThingsResult: Sendable {
    /// Sorted by `value` descending.
    public var items: [Thing]
    /// The subtree's value in the cut's metric. Always equals the sum of `items`.
    public var total: UInt64
}

/// Cuts a tree at a size threshold instead of a depth.
public enum ThingsEngine {
    /// Directory names that stay whole.
    private static let atomNames: [[UInt8]] = [
        "node_modules", ".git", "DerivedData", ".venv", "venv", "__pycache__", "Pods", "target", ".gradle", ".next",
        "dist", "build", ".cache", ".pnpm-store",
    ].map { Array($0.utf8) }

    /// Atom names that count only beside a project marker.
    private static let conditionalNames: Set<[UInt8]> = [Array("target".utf8), Array("dist".utf8), Array("build".utf8)]

    /// Files that mark a directory as a project root.
    private static let projectMarkers: [[UInt8]] = [
        "Cargo.toml", "package.json", "pom.xml", "build.gradle", "build.gradle.kts", "settings.gradle", "go.mod",
        "pyproject.toml", "setup.py", "CMakeLists.txt", "Package.swift", "Gemfile", "composer.json", "tsconfig.json",
    ].map { Array($0.utf8) }

    /// Cuts the subtree at `under` into disjoint things of at least `threshold` where possible.
    ///
    /// A node is one thing when it is at least `threshold` and has no child that is. Otherwise its big children are
    /// listed and the remainder becomes a `rest` row, or is carried up to the parent when still under the threshold.
    /// The remainder at `under` is always listed, so items sum exactly to the value at `under`.
    public static func cut(lens: TreeLens, under: NodeID, threshold: UInt64, metric: Metric) -> ThingsResult {
        let total = lens.value(under, metric)
        guard total > 0 else { return ThingsResult(items: [], total: 0) }
        var cutter = Cutter(lens: lens, under: under, threshold: max(threshold, 1), metric: metric)
        _ = cutter.visit(under)
        cutter.items.sort { $0.value != $1.value ? $0.value > $1.value : $0.id < $1.id }
        return ThingsResult(items: cutter.items, total: total)
    }

    /// Whether the node is shown as one unit until the user asks to open it.
    public static func isAtom(tree: FileTree, node: NodeID) -> Bool {
        let flags = tree.flags(node)
        guard flags.contains(.directory) else { return false }
        if flags.contains(.package) { return true }
        return tree.withName(node) { name in
            guard atomNames.contains(where: { $0.count == name.count && $0.elementsEqual(name) }) else { return false }
            if !conditionalNames.contains(Array(name)) { return true }
            return hasProjectMarker(tree: tree, sibling: node)
        }
    }

    /// Whether a sibling of `node` is a project marker file.
    private static func hasProjectMarker(tree: FileTree, sibling node: NodeID) -> Bool {
        let parent = tree.parent(node)
        guard parent >= 0 else { return false }
        for child in tree.children(parent) where child != node {
            let found = tree.withName(child) { name in
                projectMarkers.contains { $0.count == name.count && $0.elementsEqual(name) }
            }
            if found { return true }
        }
        return false
    }

    /// Finds a threshold that yields about `items` things, by bisection on the threshold.
    public static func thresholdForApproximately(items: Int, lens: TreeLens, under: NodeID, metric: Metric) -> UInt64 {
        let total = lens.value(under, metric)
        guard total > 1, items > 0 else { return 1 }
        var low: UInt64 = 1, high = total
        var best = high, bestGap = Int.max
        while low <= high {
            let middle = low + (high - low) / 2
            let count = cut(lens: lens, under: under, threshold: middle, metric: metric).items.count
            let gap = abs(count - items)
            if gap < bestGap || (gap == bestGap && middle > best) { best = middle; bestGap = gap }
            if count == items { break }
            if count > items { low = middle + 1 } else { if middle == 0 { break }; high = middle - 1 }
        }
        return best
    }

    /// What a subtree hands up to its parent when its remainder is too small to list.
    private struct Carry {
        var bytes: UInt64 = 0
        var files: UInt64 = 0
        var items = 0
    }

    private struct Cutter {
        let lens: TreeLens
        let under: NodeID
        let threshold: UInt64
        let metric: Metric
        var items: [Thing] = []

        /// The metric value of a node.
        @inline(__always) func value(_ node: NodeID) -> UInt64 { lens.value(node, metric) }

        /// Lists the things inside `node` and returns what must be carried to its parent.
        mutating func visit(_ node: NodeID) -> Carry {
            let tree = lens.tree
            let nodeValue = value(node)
            var big: [NodeID] = []
            var smallItems = 0
            if nodeValue >= threshold, tree.columns.childCount[Int(node)] > 0, node == under || !isAtomNode(node) {
                for child in tree.children(node) where lens.included[Int(child)] {
                    let childValue = value(child)
                    if childValue >= threshold { big.append(child) } else if childValue > 0 { smallItems += 1 }
                }
            }
            if big.isEmpty {
                emit(node)
                return Carry()
            }
            var bytes = UInt64(lens.size[Int(node)]), files = UInt64(lens.files[Int(node)])
            var carriedItems = smallItems
            for child in big {
                let carry = visit(child)
                bytes -= lens.size[Int(child)] - carry.bytes
                files -= UInt64(lens.files[Int(child)]) - carry.files
                carriedItems += carry.items
            }
            let residue = metric == .bytes ? bytes : files
            if node == under {
                if residue > 0 { emitRest(node, bytes: bytes, files: files, items: carriedItems) }
                return Carry()
            }
            if residue >= threshold {
                emitRest(node, bytes: bytes, files: files, items: carriedItems)
                return Carry()
            }
            return Carry(bytes: bytes, files: files, items: carriedItems)
        }

        /// Whether the node is an atom; leaves never need the check.
        func isAtomNode(_ node: NodeID) -> Bool { ThingsEngine.isAtom(tree: lens.tree, node: node) }

        /// Lists a whole node.
        mutating func emit(_ node: NodeID) {
            items.append(Thing(id: Int(node), content: .node(node), value: value(node), files: UInt64(lens.files[Int(node)])))
        }

        /// Lists the remainder of a split directory.
        mutating func emitRest(_ parent: NodeID, bytes: UInt64, files: UInt64, items count: Int) {
            items.append(Thing(id: -Int(parent) - 1, content: .rest(parent: parent, items: count),
                               value: metric == .bytes ? bytes : files, files: files))
        }
    }
}
