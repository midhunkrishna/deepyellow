import DYAdvisor
import DYAnalysis
import DYCore
import DYDecide
import DYPreview
import Foundation

/// What the HUD shows for a node.
public struct NodeSummary: Equatable, Sendable {
    public var name: String
    public var path: String
    public var bytes: UInt64
    public var files: UInt64
    /// "12%" of the parent, or nil for the root.
    public var shareOfParent: String?
    public var modified: Date?
    public var kind: FileKind
    public var isDirectory: Bool
    public var tier: SafetyTier
    /// The reclaim rule's title and consequence, when a rule applies.
    public var ruleTitle: String?
    public var consequence: String?
    public var decision: Decision
}

/// Read-only views of the model for the HUD, the preview pane and the ledger.
extension Workspace {
    /// The HUD figures for a node. Cheap enough to call on every hover.
    public func summary(for node: NodeID) -> NodeSummary? {
        guard let tree, node >= 0, Int(node) < tree.count else { return nil }
        let bytes = lens?.size[Int(node)] ?? tree.allocated(node)
        let parentBytes = node > 0 ? (lens?.size[Int(tree.parent(node))] ?? tree.allocated(tree.parent(node))) : 0
        let rule = reclaimReport?.rule(for: node, tree: tree)
        let modified = tree.modified(node)
        return NodeSummary(
            name: tree.name(node), path: tree.path(node), bytes: bytes, files: UInt64(lens?.files[Int(node)] ?? tree.fileCount(node)),
            shareOfParent: node > 0 ? Format.percent(bytes, of: parentBytes) : nil,
            modified: modified > 0 ? Date(timeIntervalSince1970: TimeInterval(modified)) : nil, kind: tree.kind(node),
            isDirectory: tree.isDirectory(node),
            tier: SafetyTier(rawValue: reclaimReport?.nodeTier[Int(node)] ?? 0) ?? .unknown,
            ruleTitle: rule?.title, consequence: rule?.consequence,
            decision: Decision(rawValue: resolved?.effective[Int(node)] ?? 0) ?? .none)
    }

    /// The preview pane's input for a node: metadata and, for a directory, its largest children.
    public func previewItem(for node: NodeID) -> PreviewItem? {
        guard let tree, node >= 0, Int(node) < tree.count else { return nil }
        let flags = tree.flags(node)
        let isDirectory = tree.isDirectory(node)
        var children: [PreviewChild] = []
        if isDirectory, let lens {
            children = lens.visibleChildren(of: node).prefix(8).map { child in
                PreviewChild(url: location(of: child, in: tree), name: tree.name(child), size: lens.size[Int(child)],
                             kind: tree.kind(child), isDirectory: tree.isDirectory(child))
            }
        }
        let modified = tree.modified(node)
        return PreviewItem(url: location(of: node, in: tree), name: tree.name(node),
                           size: lens?.size[Int(node)] ?? tree.allocated(node),
                           modified: modified > 0 ? Date(timeIntervalSince1970: TimeInterval(modified)) : nil, kind: tree.kind(node),
                           isDirectory: isDirectory, isDataless: flags.contains(.dataless), largestChildren: children)
    }

    /// Where a node's content is read from: the environment's override for files, else the node's own path.
    private func location(of node: NodeID, in tree: FileTree) -> URL {
        let path = tree.path(node)
        if !tree.isDirectory(node), let url = environment.previewLocation?(path, tree.kind(node)) { return url }
        return URL(fileURLWithPath: path)
    }

    /// The preview input for a path, or nil when it isn't in the tree.
    public func previewItem(path: String) -> PreviewItem? { tree?.find(path: path).flatMap { previewItem(for: $0) } }

    /// The preview input for the last-clicked selection.
    public var selectionPreview: PreviewItem? { primarySelectionPath.flatMap { previewItem(path: $0) } }

    /// The preview input for the review item.
    public var reviewPreview: PreviewItem? { review?.current.flatMap { previewItem(path: $0.path) } }

    /// The next few review items, for `PreviewController.prepare`, so advancing is instant.
    public func reviewUpcoming(count: Int = 3) -> [PreviewItem] {
        guard let review else { return [] }
        return review.items.dropFirst(review.index + 1).prefix(count).compactMap { previewItem(path: $0.path) }
    }

    /// The ledger: where every byte went. Nil before a tree is shown.
    public var reconciliation: Reconciliation? {
        guard let baseLens else { return nil }
        let root: String? = tree.map { $0.name(0) }
        let volume = root.flatMap { environment.volumeForRoot($0) }
        var result = Reconciliation.make(lens: lens ?? baseLens, ignore: ignoreResult, rules: ignoreRules, volume: volume,
                                         sample: environment.sampleLedger)
        result.visibleBytes = (lens ?? baseLens).size.first ?? 0
        return result
    }
}
