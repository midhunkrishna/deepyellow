import DYCore
import Foundation

/// Selection is keyed by path, so it survives snapshots, rescans and kind refinement. Nothing is hidden: the count and
/// bytes are always current, and the scan root can be selected (the planner refuses to remove it).
extension Workspace {
    /// Click semantics: a plain click selects only this node, or clears it when it is the only one selected.
    /// An additive click toggles this node.
    public func click(_ node: NodeID, additive: Bool) {
        guard let tree, node >= 0, Int(node) < tree.count else { return }
        let path = tree.path(node)
        if additive {
            if selectionPaths.contains(path) { selectionPaths.remove(path) } else { selectionPaths.insert(path) }
        } else {
            selectionPaths = (selectionPaths == [path]) ? [] : [path]
        }
        primarySelectionPath = selectionPaths.contains(path) ? path : selectionPaths.sorted().last
        refreshSelection()
    }

    /// Replaces the selection.
    public func select(_ nodes: [NodeID]) {
        guard let tree else { return }
        selectionPaths = Set(nodes.filter { $0 >= 0 && Int($0) < tree.count }.map { tree.path($0) })
        primarySelectionPath = nodes.last.map { tree.path($0) }
        refreshSelection()
    }

    /// Replaces the selection with paths, which need not exist in the current tree yet.
    public func select(paths: [String]) {
        selectionPaths = Set(paths)
        primarySelectionPath = paths.last
        refreshSelection()
    }

    /// Adds nodes to the selection.
    public func addToSelection(_ nodes: [NodeID]) {
        guard let tree else { return }
        for node in nodes where node >= 0 && Int(node) < tree.count { selectionPaths.insert(tree.path(node)) }
        refreshSelection()
    }

    /// Clears the selection.
    public func clearSelection() {
        selectionPaths = []
        primarySelectionPath = nil
        refreshSelection()
    }

    /// Whether a node is selected.
    public func isSelected(_ node: NodeID) -> Bool {
        guard let tree, node >= 0, Int(node) < tree.count else { return false }
        return selectionPaths.contains(tree.path(node))
    }

    /// Resolves the selected paths against the current tree and recomputes the count and bytes.
    ///
    /// Cost is proportional to the selection, never to the tree.
    func refreshSelection() {
        selectionCount = selectionPaths.count
        guard let tree else {
            selectedNodes = []
            selectionBytes = 0
            return
        }
        let nodes = selectionPaths.compactMap { tree.find(path: $0) }.sorted()
        let chosen = Set(nodes)
        var bytes: UInt64 = 0
        for node in nodes {
            var ancestor = tree.parent(node)
            var covered = false
            while ancestor >= 0 {
                if chosen.contains(ancestor) { covered = true; break }
                ancestor = tree.parent(ancestor)
            }
            if !covered { bytes &+= lens?.size[Int(node)] ?? tree.allocated(node) }
        }
        selectedNodes = nodes
        selectionBytes = bytes
    }
}
