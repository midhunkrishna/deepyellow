import DYCore
import DYPreview
import DYWorkspace
import SwiftUI

/// Full-window culling over the current review session.
///
/// The preview fills the stage, a side panel carries the facts and the three verdicts, and a filmstrip shows the whole set.
/// Keys are handled by the shell, which calls the same `Workspace` verdict methods these buttons call. The next few items
/// are prepared ahead, so advancing is instant.
public struct ReviewMode: View {
    let workspace: Workspace
    let controller: PreviewController
    @Environment(\.lensActions) private var actions

    /// Creates review mode over a workspace, sharing the app's preview controller.
    public init(workspace: Workspace, controller: PreviewController) {
        self.workspace = workspace
        self.controller = controller
    }

    public var body: some View {
        if let session = workspace.review {
            VStack(spacing: 0) {
                ReviewTopBar(workspace: workspace, session: session)
                if session.isFinished {
                    ReviewFinished(workspace: workspace, session: session) { actions.reviewPlan() }
                } else {
                    stage(session)
                    Filmstrip(workspace: workspace, session: session)
                }
            }
            .background(Theme.background)
            .task(id: session.index) { controller.prepare(workspace.reviewUpcoming(count: 3)) }
        }
    }

    /// The preview and the side panel.
    private func stage(_ session: ReviewSession) -> some View {
        HStack(spacing: 0) {
            PreviewPane(item: workspace.reviewPreview, controller: controller)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.4))
            if let item = session.current {
                ReviewSidePanel(workspace: workspace, session: session, item: item)
                    .frame(width: 330)
                    .overlay(alignment: .leading) { Rectangle().fill(Theme.hairline).frame(width: 1) }
            }
        }
    }
}

/// Title, progress, tally and the way out.
struct ReviewTopBar: View {
    let workspace: Workspace
    let session: ReviewSession

    /// "38 left · 214 GB decided".
    static func tallyText(_ tally: ReviewTally) -> String { "\(Format.count(tally.left)) left · \(Format.bytes(tally.decidedBytes)) decided" }

    var body: some View {
        let total = session.items.count
        let position = min(session.index + 1, total)
        HStack(spacing: 14) {
            Text(session.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textPrimary)
            Text(session.isFinished ? "\(total) of \(total)" : "\(position) of \(total)")
                .font(Theme.number(size: 13)).foregroundStyle(Theme.textSecondary)
            ProgressBar(fraction: Double(session.index) / Double(max(total, 1))).frame(maxWidth: .infinity)
            Text(Self.tallyText(session.tally)).font(Theme.number(size: 13)).foregroundStyle(Theme.textSecondary)
            Button { workspace.endReview() } label: {
                HStack(spacing: 6) { Text("Done"); KeyCap(key: "esc") }
            }
            .buttonStyle(GhostButtonStyle())
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }
}

/// The facts about the current item and the three verdict buttons.
struct ReviewSidePanel: View {
    let workspace: Workspace
    let session: ReviewSession
    let item: ReviewItem

    var body: some View {
        let node = workspace.tree?.find(path: item.path)
        let summary = node.flatMap { workspace.summary(for: $0) }
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(item.name).font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.path).font(Theme.mono(size: 11)).foregroundStyle(Theme.textMuted)
                    .lineLimit(3).truncationMode(.head)
                Text(Format.bytes(item.bytes)).font(Theme.number(size: 34, weight: .semibold)).tracking(-0.6).foregroundStyle(Theme.textPrimary)
                if let summary { Text(Self.meta(summary, now: workspace.environment.clock())).font(Theme.number(size: 13)).foregroundStyle(Theme.textSecondary) }
                if let summary, summary.tier != .unknown {
                    VStack(alignment: .leading, spacing: 6) {
                        TierPill(tier: summary.tier)
                        if let why = summary.consequence {
                            Text(why).font(.system(size: 13)).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if let given = session.verdicts[item.path], given != .none {
                    HStack(spacing: 6) { Text("Marked").foregroundStyle(Theme.textMuted); DecisionTag(decision: given) }.font(.system(size: 12))
                }
                verdicts.padding(.top, 8)
                Text("The next item appears immediately. ⌘Z steps back. Nothing moves until you apply the plan.")
                    .font(.system(size: 12)).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
        }
    }

    /// Kind, age and, for a folder, its file count.
    static func meta(_ summary: NodeSummary, now: Date) -> String {
        var parts = [summary.kind.title]
        if summary.isDirectory { parts.append("\(Format.count(summary.files)) files") }
        if let modified = summary.modified { parts.append("changed " + Format.age(Int32(clamping: Int(modified.timeIntervalSince1970)), now: Int32(clamping: Int(now.timeIntervalSince1970)))) }
        return parts.joined(separator: " · ")
    }

    /// Keep, Remove and Decide later, each with its key.
    private var verdicts: some View {
        VStack(spacing: 7) {
            VerdictButton(title: "Keep", key: "k", decision: .keep) { workspace.reviewVerdict(.keep) }
            VerdictButton(title: "Remove", key: "x", decision: .remove) { workspace.reviewVerdict(.remove) }
            VerdictButton(title: "Decide later", key: "l", decision: .later) { workspace.reviewVerdict(.later) }
        }
    }
}

/// One verdict button: glyph, word, key cap.
struct VerdictButton: View {
    let title: String
    let key: String
    let decision: Decision
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                DecisionGlyph(decision: decision, size: 14)
                Text(title).font(.system(size: 13.5, weight: .medium)).foregroundStyle(DecisionTag.ink(decision))
                Spacer()
                KeyCap(key: key)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 9).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.hairline, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), key \(key)")
    }
}

/// The set as a strip of tiles. The current one is ringed in gold, and decided ones carry their glyph.
struct Filmstrip: View {
    let workspace: Workspace
    let session: ReviewSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 5) {
                    ForEach(Array(session.items.enumerated()), id: \.element.id) { index, item in
                        FilmstripTile(item: item, verdict: session.verdicts[item.path] ?? .none, isCurrent: index == session.index) {
                            workspace.reviewGo(to: index)
                        }
                        .id(index)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
            }
            .onChange(of: session.index) { _, index in
                if reduceMotion { proxy.scrollTo(index, anchor: .center) } else { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(index, anchor: .center) } }
            }
        }
        .frame(height: 80)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }
}

/// One filmstrip tile.
struct FilmstripTile: View {
    let item: ReviewItem
    let verdict: Decision
    let isCurrent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Text(item.name).font(.system(size: 10.5)).lineLimit(1).truncationMode(.middle).foregroundStyle(Theme.textPrimary)
                    Spacer(minLength: 0)
                    DecisionGlyph(decision: verdict, size: 11)
                }
                Spacer(minLength: 0)
                Text(Format.bytes(item.bytes)).font(Theme.number(size: 10.5)).foregroundStyle(Theme.textSecondary)
            }
            .padding(6)
            .frame(width: 104, height: 62)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(Theme.kind(item.kind).opacity(0.28))
                    if verdict == .remove { HatchFill(color: Theme.remove.opacity(0.35), spacing: 6).clipShape(RoundedRectangle(cornerRadius: 6)) }
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.accent, lineWidth: isCurrent ? 2 : 0))
            .opacity(verdict != .none && !isCurrent ? 0.75 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.name), \(Format.bytes(item.bytes))\(verdict == .none ? "" : ", " + DecisionTag.title(verdict))")
    }
}

/// The state after the last item: what was decided and the way to the plan.
struct ReviewFinished: View {
    let workspace: Workspace
    let session: ReviewSession
    let openPlan: () -> Void

    var body: some View {
        let tally = session.tally
        VStack(spacing: 12) {
            Text(tally.left == 0 ? "All \(Format.count(session.items.count)) decided" : "End of the set: \(Format.count(tally.left)) left undecided").font(.system(size: 30, weight: .semibold)).tracking(-0.5)
                .foregroundStyle(Theme.textPrimary)
            Text("\(tally.kept) kept · \(tally.removed) to remove (\(Format.bytes(tally.removedBytes))) · \(tally.later) for later")
                .font(Theme.number(size: 15)).foregroundStyle(Theme.textSecondary)
            HStack(spacing: 8) {
                Button("Back to the map") { workspace.endReview() }.buttonStyle(GhostButtonStyle())
                Button("Review plan") { openPlan() }.buttonStyle(PrimaryButtonStyle())
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A thin gold bar for progress through the set.
struct ProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.surfaceRaised)
                Capsule().fill(Theme.accent).frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 4)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int(fraction * 100)) percent")
    }
}
