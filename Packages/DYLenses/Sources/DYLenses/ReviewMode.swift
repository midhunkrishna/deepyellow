import AppKit
import DYCore
import DYPreview
import DYWorkspace
import SwiftUI

/// Puts a file path on the clipboard.
public enum PathClipboard {
    /// Replaces what `pasteboard` holds with `path`.
    public static func copy(_ path: String, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.setString(path, forType: .string)
    }
}

/// Full-window culling over the current review session.
///
/// The preview fills the stage, a side panel carries the facts and the three verdicts, and a filmstrip shows the current level.
/// Keys are handled by the shell, which calls the same `Workspace` verdict methods these buttons call. The next few items
/// are prepared ahead, so moving along is instant.
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
                ReviewTopBar(workspace: workspace, session: session) { actions.reviewPlan() }
                stage(session)
                Filmstrip(workspace: workspace, session: session)
            }
            .background(Theme.background)
            .task(id: session.current?.path) { controller.prepare(workspace.reviewUpcoming(count: 3)) }
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

/// Where you are, progress, tally, and the ways out.
struct ReviewTopBar: View {
    let workspace: Workspace
    let session: ReviewSession
    let openPlan: () -> Void

    /// "38 left · 214 GB decided".
    static func tallyText(_ tally: ReviewTally) -> String { "\(Format.count(tally.left)) left · \(Format.bytes(tally.decidedBytes)) decided" }

    var body: some View {
        let total = session.items.count
        let position = session.index + 1
        HStack(spacing: 14) {
            Text(session.trail.joined(separator: " › ")).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                .lineLimit(1).truncationMode(.head)
            Text("\(position) of \(total)")
                .font(Theme.number(size: 13)).foregroundStyle(Theme.textSecondary)
            ProgressBar(fraction: Double(position) / Double(max(total, 1))).frame(maxWidth: .infinity)
            Text(Self.tallyText(workspace.reviewTally)).font(Theme.number(size: 13)).foregroundStyle(Theme.textSecondary)
            Button(action: openPlan) {
                HStack(spacing: 6) { Text("Plan"); KeyCap(key: "⌘⏎") }
            }
            .buttonStyle(GhostButtonStyle())
            if session.depth > 0 {
                Button { workspace.reviewUp() } label: {
                    HStack(spacing: 6) { Text("Up"); KeyCap(key: "esc") }
                }
                .buttonStyle(GhostButtonStyle())
                Button("Done") { workspace.endReview() }.buttonStyle(GhostButtonStyle())
            } else {
                Button { workspace.endReview() } label: {
                    HStack(spacing: 6) { Text("Done"); KeyCap(key: "esc") }
                }
                .buttonStyle(GhostButtonStyle())
            }
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
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                Button {
                    PathClipboard.copy(item.path)
                    workspace.announce("Copied the path.")
                } label: {
                    HStack(spacing: 6) { Text("Copy path"); KeyCap(key: "⌘C") }
                }
                .buttonStyle(GhostButtonStyle())
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
                if let text = markedFilesText { Text(text).font(Theme.number(size: 13)).foregroundStyle(Theme.textSecondary) }
                let given = workspace.reviewDecision(of: item)
                if given != .none {
                    HStack(spacing: 6) {
                        Text("Marked").foregroundStyle(Theme.textMuted)
                        DecisionTag(decision: given)
                        if workspace.reviewMarkIsInherited(item) { Text("through its folder").foregroundStyle(Theme.textMuted) }
                    }
                    .font(.system(size: 12))
                }
                verdicts.padding(.top, 8)
                if item.canGoIn {
                    Button { workspace.reviewEnter() } label: {
                        HStack(spacing: 6) { Text("Go in"); KeyCap(key: "⏎") }
                    }
                    .buttonStyle(GhostButtonStyle())
                }
                Text("← → move. u clears a mark, ⌘Z undoes the last one. Nothing moves until you apply the plan.")
                    .font(.system(size: 12)).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
        }
    }

    /// "12 of 40 marked" for a folder with marks inside it.
    private var markedFilesText: String? {
        guard let counts = workspace.reviewMarkedFiles(of: item), counts.marked > 0 else { return nil }
        return "\(Format.count(counts.marked)) of \(Format.count(counts.files)) marked"
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

/// The current level as a strip of tiles. The current one is ringed in gold, and decided ones carry their glyph.
struct Filmstrip: View {
    let workspace: Workspace
    let session: ReviewSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 5) {
                    ForEach(Array(session.items.enumerated()), id: \.element.id) { index, item in
                        FilmstripTile(item: item, verdict: workspace.reviewDecision(of: item), marked: workspace.reviewMarkedFiles(of: item), isCurrent: index == session.index) {
                            workspace.reviewGo(to: index)
                        }
                        .id(index)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
            }
            .onAppear { proxy.scrollTo(session.index, anchor: .center) }
            .onChange(of: session.index) { _, index in
                if reduceMotion { proxy.scrollTo(index, anchor: .center) } else { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(index, anchor: .center) } }
            }
        }
        .id(session.trail)
        .frame(height: 80)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }
}

/// One filmstrip tile.
struct FilmstripTile: View {
    let item: ReviewItem
    let verdict: Decision
    /// For a folder, how many of its files have a mark and how many it holds.
    let marked: (marked: Int, files: Int)?
    let isCurrent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    if item.canGoIn { Image(systemName: "folder.fill").font(.system(size: 9)).foregroundStyle(Theme.textSecondary) }
                    Text(item.name).font(.system(size: 10.5)).lineLimit(1).truncationMode(.middle).foregroundStyle(Theme.textPrimary)
                    Spacer(minLength: 0)
                    DecisionGlyph(decision: verdict, size: 11)
                }
                Spacer(minLength: 0)
                Text(detail).font(Theme.number(size: 10.5)).foregroundStyle(Theme.textSecondary).lineLimit(1)
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
        .accessibilityLabel("\(item.canGoIn ? "Folder " : "")\(item.name), \(detail)\(verdict == .none ? "" : ", " + DecisionTag.title(verdict))")
    }

    /// The size, and for a folder with marks inside it, how many.
    private var detail: String {
        guard let marked, marked.marked > 0, verdict == .none || marked.marked < marked.files else { return Format.bytes(item.bytes) }
        return "\(Format.bytes(item.bytes)) · \(Format.count(marked.marked))/\(Format.count(marked.files))"
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
