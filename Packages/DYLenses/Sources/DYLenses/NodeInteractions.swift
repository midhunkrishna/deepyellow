import AppKit
import DYCore
import DYWorkspace
import SwiftUI

/// Hooks the window shell can supply so lenses can reach things they don't own.
public struct LensActions {
    /// Opens the preview pane for a node.
    public var previewNode: (NodeID) -> Void
    /// Opens the removal plan, from the end of a review.
    public var reviewPlan: () -> Void

    /// Creates the hooks. Both default to doing nothing.
    public init(previewNode: @escaping (NodeID) -> Void = { _ in }, reviewPlan: @escaping () -> Void = {}) {
        self.previewNode = previewNode
        self.reviewPlan = reviewPlan
    }
}

private struct LensActionsKey: EnvironmentKey {
    static let defaultValue = LensActions()
}

extension EnvironmentValues {
    /// The shell's hooks for lenses.
    public var lensActions: LensActions {
        get { self[LensActionsKey.self] }
        set { self[LensActionsKey.self] = newValue }
    }
}

extension View {
    /// Supplies the shell's hooks to every lens beneath this view.
    public func lensActions(_ actions: LensActions) -> some View { environment(\.lensActions, actions) }
}

/// Reads per-node facts from the workspace for rows.
@MainActor
enum NodeFacts {
    /// The effective decision on a node.
    static func decision(_ workspace: Workspace, _ node: NodeID) -> Decision {
        guard let effective = workspace.resolved?.effective, effective.indices.contains(Int(node)) else { return .none }
        return Decision(rawValue: effective[Int(node)]) ?? .none
    }

    /// The safety tier on a node.
    static func tier(_ workspace: Workspace, _ node: NodeID) -> SafetyTier {
        guard let tiers = workspace.reclaimReport?.nodeTier, tiers.indices.contains(Int(node)) else { return .unknown }
        return SafetyTier(rawValue: tiers[Int(node)]) ?? .unknown
    }

    /// The kind to colour a node with: a file's own kind, or the kind holding the most bytes in a folder.
    static func displayKind(_ workspace: Workspace, _ node: NodeID) -> FileKind {
        guard let tree = workspace.tree, node >= 0, Int(node) < tree.count else { return .other }
        if tree.isDirectory(node), workspace.dominantKinds.indices.contains(Int(node)) {
            return FileKind(rawValue: workspace.dominantKinds[Int(node)]) ?? .other
        }
        return tree.kind(node)
    }

    /// Whether a modifier key asks for an additive click.
    static var isAdditiveClick: Bool {
        NSEvent.modifierFlags.contains(.command) || NSEvent.modifierFlags.contains(.shift)
    }
}

/// Hover, click and right-click behaviour shared by every row that stands for a node.
struct NodeInteraction: ViewModifier {
    let workspace: Workspace
    let node: NodeID
    var onOpen: (() -> Void)?
    @Environment(\.lensActions) private var actions

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { workspace.hover = node } else if workspace.hover == node { workspace.hover = nil }
            }
            .onTapGesture(count: 2) { onOpen?() }
            .onTapGesture { workspace.click(node, additive: NodeFacts.isAdditiveClick) }
            .contextMenu { menu }
    }

    /// The right-click menu: preview, verdicts and hide rules.
    @ViewBuilder private var menu: some View {
        let name = workspace.tree?.name(node) ?? ""
        let ext = (name as NSString).pathExtension
        Button("Preview") {
            workspace.select([node])
            actions.previewNode(node)
        }
        Divider()
        Button("Keep") { workspace.mark(.keep, nodes: [node]) }
        Button("Remove") { workspace.mark(.remove, nodes: [node]) }
        Button("Later") { workspace.mark(.later, nodes: [node]) }
        Divider()
        Button("Hide this") { workspace.hide(.path, nodes: [node]) }
        Button("Hide all named \(name)") { workspace.hide(.name, nodes: [node]) }
        if !ext.isEmpty { Button("Hide all .\(ext)") { workspace.hide(.ext, nodes: [node]) } }
    }
}

extension View {
    /// Makes a row behave like a node: hover feeds the HUD, click selects, double-click opens, right-click offers actions.
    func nodeInteraction(workspace: Workspace, node: NodeID, onOpen: (() -> Void)? = nil) -> some View {
        modifier(NodeInteraction(workspace: workspace, node: node, onOpen: onOpen))
    }
}
