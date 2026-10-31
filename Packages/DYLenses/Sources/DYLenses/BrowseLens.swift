import DYCore
import DYWorkspace
import SwiftUI

/// Miller columns with inline size bars, for people who think in Finder.
///
/// The last-clicked node drives the columns: a folder opens to its right, a file shows its folder. Arrow keys move
/// through the columns, and each column scrolls to keep the selection in view.
public struct BrowseLens: View {
    let workspace: Workspace
    @FocusState private var hasFocus: Bool

    /// Creates the lens over a workspace.
    public init(workspace: Workspace) { self.workspace = workspace }

    public var body: some View {
        if let lens = workspace.lens {
            columns(lens)
        } else {
            LensPlaceholder(message: "Waiting for the scan…").background(Theme.background)
        }
    }

    /// The node the columns follow.
    private var selectedNode: NodeID? {
        guard let tree = workspace.tree, let path = workspace.primarySelectionPath else { return nil }
        return tree.find(path: path)
    }

    /// The row of columns, scrolled so the deepest one is visible.
    private func columns(_ lens: TreeLens) -> some View {
        let selected = selectedNode
        let parents = BrowseModel.columnParents(tree: lens.tree, focus: workspace.focus, selected: selected)
        return ScrollViewReader { horizontal in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Array(parents.enumerated()), id: \.element) { index, parent in
                        let next = index + 1 < parents.count ? parents[index + 1] : selected
                        BrowseColumn(workspace: workspace, lens: lens, parent: parent, highlighted: next, selected: selected)
                            .id(parent)
                    }
                    Spacer(minLength: 0)
                }
            }
            .onChange(of: parents) { _, now in
                if let last = now.last { withAnimation(.easeOut(duration: 0.2)) { horizontal.scrollTo(last, anchor: .trailing) } }
            }
        }
        .background(Theme.background)
        .focusable()
        .focused($hasFocus)
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { step(.up, lens) }
        .onKeyPress(.downArrow) { step(.down, lens) }
        .onKeyPress(.leftArrow) { step(.left, lens) }
        .onKeyPress(.rightArrow) { step(.right, lens) }
        .onAppear { hasFocus = true }
    }

    /// Moves the selection with an arrow key.
    private func step(_ arrow: BrowseModel.Arrow, _ lens: TreeLens) -> KeyPress.Result {
        guard let target = BrowseModel.move(arrow, from: selectedNode, lens: lens, focus: workspace.focus) else { return .handled }
        workspace.select([target])
        return .handled
    }
}

/// One column: the children of a folder, largest first, each with a size bar.
struct BrowseColumn: View {
    let workspace: Workspace
    let lens: TreeLens
    let parent: NodeID
    let highlighted: NodeID?
    /// The node the user last clicked. Folders on the way to it get a softer highlight.
    let selected: NodeID?

    var body: some View {
        let children = lens.visibleChildren(of: parent)
        let top = Double(max(children.first.map { lens.size[Int($0)] } ?? 1, 1))
        ScrollViewReader { vertical in
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(children, id: \.self) { child in
                        BrowseRow(workspace: workspace, lens: lens, node: child, fraction: Double(lens.size[Int(child)]) / top,
                                  isHighlighted: child == highlighted, isSelection: child == selected)
                            .id(child)
                    }
                }
                .padding(.horizontal, 6).padding(.vertical, 8)
            }
            .onChange(of: highlighted) { _, node in if let node { vertical.scrollTo(node, anchor: .center) } }
            .onAppear { if let highlighted { vertical.scrollTo(highlighted, anchor: .center) } }
        }
        .frame(width: 280)
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.hairline).frame(width: 1) }
    }
}

/// One row in a Miller column.
struct BrowseRow: View {
    let workspace: Workspace
    let lens: TreeLens
    let node: NodeID
    let fraction: Double
    let isHighlighted: Bool
    let isSelection: Bool

    var body: some View {
        let tree = lens.tree
        let decision = NodeFacts.decision(workspace, node)
        let isFolder = tree.isDirectory(node)
        HStack(spacing: 8) {
            KindSwatch(kind: NodeFacts.displayKind(workspace, node))
            Text(tree.name(node)).font(.system(size: 13)).lineLimit(1).truncationMode(.middle)
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 0)
            DecisionTag(decision: decision)
            Text(Format.bytes(lens.size[Int(node)])).font(Theme.number(size: 12)).foregroundStyle(Theme.textSecondary)
            Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.textMuted).opacity(isFolder ? 1 : 0)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(alignment: .leading) { RowBar(fraction: fraction) }
        .background(RoundedRectangle(cornerRadius: 6).fill(isHighlighted ? Theme.surfaceRaised : .clear))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.accent, lineWidth: isSelection ? 1 : 0))
        .nodeInteraction(workspace: workspace, node: node) { if isFolder { workspace.zoomIn(node) } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isHighlighted ? .isSelected : [])
    }
}
