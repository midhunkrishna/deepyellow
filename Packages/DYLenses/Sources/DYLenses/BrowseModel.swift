import DYCore
import Foundation

/// Pure navigation logic for the Miller columns.
enum BrowseModel {
    /// The directories shown as columns, from the focus down to the selection's folder.
    ///
    /// A selected folder opens as the last column; a selected file shows its parent. A selection outside the focus is ignored.
    static func columnParents(tree: FileTree, focus: NodeID, selected: NodeID?) -> [NodeID] {
        guard let selected, selected >= 0, Int(selected) < tree.count,
              selected == focus || tree.isAncestor(focus, of: selected) else { return [focus] }
        var last = tree.isDirectory(selected) ? selected : tree.parent(selected)
        if last < focus { last = focus }
        var chain = [last]
        while chain[0] != focus, chain[0] > 0 { chain.insert(tree.parent(chain[0]), at: 0) }
        return chain.first == focus ? chain : [focus]
    }

    /// Where an arrow key moves the selection, or nil when it can't move.
    enum Arrow { case up, down, left, right }

    /// The node an arrow key selects next.
    static func move(_ arrow: Arrow, from selected: NodeID?, lens: TreeLens, focus: NodeID) -> NodeID? {
        let tree = lens.tree
        guard let selected else { return lens.visibleChildren(of: focus).first }
        switch arrow {
        case .up, .down:
            let siblings = lens.visibleChildren(of: selected == focus ? focus : tree.parent(selected))
            guard let index = siblings.firstIndex(of: selected) else { return siblings.first }
            let next = arrow == .down ? index + 1 : index - 1
            return siblings.indices.contains(next) ? siblings[next] : nil
        case .right:
            return tree.isDirectory(selected) ? lens.visibleChildren(of: selected).first : nil
        case .left:
            return selected != focus && tree.parent(selected) != focus ? tree.parent(selected) : nil
        }
    }
}
