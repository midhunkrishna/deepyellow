import DYAnalysis
import DYCore
import DYWorkspace
import SwiftUI

/// The ranked list of things at a chosen level of detail.
///
/// A slider sets how finely the tree is cut. Every tick asks the workspace for a new cut, and the list keeps showing the
/// previous one until the new one lands, so dragging never stalls.
public struct ThingsLens: View {
    let workspace: Workspace
    @State private var detail: Double

    /// Creates the lens over a workspace.
    public init(workspace: Workspace) {
        self.workspace = workspace
        _detail = State(initialValue: ThingsDetail.position(forTarget: workspace.thingsItemTarget))
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.hairline)
            if let result = workspace.things {
                list(result)
            } else {
                LensPlaceholder(message: "Working out the biggest things…")
            }
        }
        .background(Theme.background)
    }

    /// The headline and the level-of-detail slider.
    private var header: some View {
        let summary = workspace.things.map { ThingsSummary(result: $0, metric: workspace.metric) }
        return HStack(alignment: .bottom, spacing: 22) {
            LensHeadline(title: Text(summary?.title ?? "Things"),
                         subtitle: summary?.subtitle ?? "The biggest files and folders, cut at a size you choose.")
                .frame(maxWidth: .infinity, alignment: .leading)
            detailSlider.frame(width: 380)
        }
        .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 12)
    }

    /// The slider with its live threshold label.
    private var detailSlider: some View {
        VStack(spacing: 2) {
            HStack {
                Text("Fewer, bigger things").foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(thresholdLabel).font(Theme.number(size: 12, weight: .semibold)).foregroundStyle(Theme.accent)
                Spacer()
                Text("More detail").foregroundStyle(Theme.textSecondary)
            }
            .font(.system(size: 12))
            Slider(value: $detail, in: 0...1)
                .tint(Theme.accent)
                .accessibilityLabel("Level of detail")
                .onChange(of: detail) { _, value in workspace.setThingsItemTarget(ThingsDetail.target(forPosition: value)) }
        }
    }

    /// "at least 400 MB", from the threshold the workspace last used.
    private var thresholdLabel: String {
        guard let threshold = workspace.thingsThreshold else { return "" }
        return "at least \(MetricFormat.text(threshold, metric: workspace.metric))"
    }

    /// The rows, drawn lazily so thousands of things stay light.
    private func list(_ result: ThingsResult) -> some View {
        let summary = ThingsSummary(result: result, metric: workspace.metric)
        let top = Double(max(result.items.first?.value ?? 1, 1))
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(Array(result.items.enumerated()), id: \.element.id) { index, thing in
                        ThingRow(workspace: workspace, thing: thing, total: result.total,
                                 barFraction: Double(thing.value) / top, cumulative: summary.cumulative[index])
                    }
                }
                .padding(.horizontal, 8).padding(.top, 8).padding(.bottom, 24)
            }
            .onChange(of: workspace.selectedNodes) { _, nodes in
                if let node = nodes.last { proxy.scrollTo(Int(node)) }
            }
        }
    }
}

/// One row of the Things list.
struct ThingRow: View {
    let workspace: Workspace
    let thing: Thing
    let total: UInt64
    let barFraction: Double
    let cumulative: Double

    var body: some View {
        let facts = Facts(workspace: workspace, thing: thing)
        HStack(spacing: 12) {
            HStack(spacing: 9) {
                KindSwatch(kind: facts.kind)
                Text(facts.name).font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.middle)
                    .foregroundStyle(Theme.textPrimary).layoutPriority(1)
                Text(facts.typeLabel).font(.system(size: 11)).foregroundStyle(facts.typeInk)
                Text(facts.location).font(.system(size: 12)).foregroundStyle(Theme.textMuted)
                    .lineLimit(1).truncationMode(.head)
                Spacer(minLength: 0)
                DecisionTag(decision: facts.decision)
                TierPill(tier: facts.tier)
            }
            Text(MetricFormat.text(thing.value, metric: workspace.metric))
                .font(Theme.number(size: 13, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                .frame(width: 92, alignment: .trailing)
            Text(Format.percent(thing.value, of: total))
                .font(Theme.number(size: 13)).foregroundStyle(Theme.textMuted).frame(width: 62, alignment: .trailing)
            Text("Σ\(Int((cumulative * 100).rounded()))%")
                .font(Theme.number(size: 11)).foregroundStyle(Theme.textMuted).frame(width: 46, alignment: .trailing)
                .accessibilityLabel("Cumulative share \(Int((cumulative * 100).rounded())) percent")
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
        .background(alignment: .leading) { RowBar(fraction: barFraction) }
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.accent, lineWidth: facts.isSelected ? 1 : 0))
        .nodeInteraction(workspace: workspace, node: facts.node) { if facts.isFolder { workspace.zoomIn(facts.node) } }
        .accessibilityElement(children: .combine)
    }

    /// Everything a row shows that comes from the tree.
    private struct Facts {
        let node: NodeID
        let name: String
        let location: String
        let kind: FileKind
        let typeLabel: String
        let typeInk: Color
        let decision: Decision
        let tier: SafetyTier
        let isSelected: Bool
        let isFolder: Bool

        /// Looks up a row's node, its parent path, type and state.
        @MainActor init(workspace: Workspace, thing: Thing) {
            let tree = workspace.tree
            switch thing.content {
            case .rest(let parent, let items):
                node = parent
                name = items == 0 ? "Everything smaller" : "\(Format.count(items)) smaller items"
                location = tree.map { "in " + $0.path(parent) } ?? ""
                kind = .other
                typeLabel = "Rest"
                typeInk = Theme.textMuted
                decision = .none
                tier = .unknown
                isSelected = false
                isFolder = true
            case .node(let id):
                node = id
                if let tree {
                    name = tree.name(id)
                    location = id > 0 ? tree.path(tree.parent(id)) : ""
                    kind = NodeFacts.displayKind(workspace, id)
                    let isFolder = tree.isDirectory(id)
                    let isPackage = tree.flags(id).contains(.package)
                    typeLabel = !isFolder ? "File" : isPackage ? "Package" : ThingsEngine.isAtom(tree: tree, node: id) ? "Group" : "Folder"
                    typeInk = isFolder ? Color(.sRGB, red: 0xD8 / 255, green: 0xC4 / 255, blue: 0x8F / 255) : Theme.textMuted
                    isSelected = workspace.selectionPaths.contains(tree.path(id))
                    self.isFolder = isFolder
                } else {
                    (name, location, kind, typeLabel, typeInk, isSelected, isFolder) = ("", "", .other, "File", Theme.textMuted, false, false)
                }
                decision = NodeFacts.decision(workspace, id)
                tier = NodeFacts.tier(workspace, id)
            }
        }
    }
}

/// The faint bar behind a row, as wide as the row's share of the largest row.
struct RowBar: View {
    let fraction: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            RoundedRectangle(cornerRadius: 7)
                .fill(LinearGradient(colors: [.white.opacity(0.075), .white.opacity(0.03)], startPoint: .leading, endPoint: .trailing))
                .frame(width: max(proxy.size.width * min(max(fraction, 0.005), 1), 2))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: fraction)
        }
        .allowsHitTesting(false)
    }
}
