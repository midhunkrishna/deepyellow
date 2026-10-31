import DYCore

/// Helpers for walking a subtree of a breadth-first tree without recursion.
enum Subtree {
    /// Marks `root` and everything beneath it. Children always have larger ids than parents, so one forward pass suffices.
    static func membership(of root: NodeID, in tree: FileTree) -> [Bool] {
        var inside = [Bool](repeating: false, count: tree.count)
        guard Int(root) < tree.count, root >= 0 else { return inside }
        inside[Int(root)] = true
        let parent = tree.columns.parent
        for index in (Int(root) + 1)..<max(tree.count, Int(root) + 1) where inside[Int(parent[index])] { inside[index] = true }
        return inside
    }

    /// Whether the node is a plain file visible through the lens.
    @inline(__always) static func isVisibleFile(_ index: Int, lens: TreeLens) -> Bool {
        let columns = lens.tree.columns
        return lens.included[index] && columns.childCount[index] == 0 && columns.flags[index] & NodeFlags.directory.rawValue == 0
    }
}
