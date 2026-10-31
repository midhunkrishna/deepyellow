import DYAdvisor
import DYCore
import DYWorkspace
import SwiftUI

/// Where to start, then every safety group.
///
/// Worklists come first because they answer "where do I start?" with a measured fact. The safety groups follow, each family
/// with its plain consequence and the official cleanup command, which is shown as text and never run. Nothing is pre-marked.
public struct ReclaimLens: View {
    let workspace: Workspace

    /// Creates the lens over a workspace.
    public init(workspace: Workspace) { self.workspace = workspace }

    public var body: some View {
        if let report = workspace.reclaimReport {
            content(ReclaimModel.groups(report))
        } else {
            LensPlaceholder(message: "Reading the advice for this disk…").background(Theme.background)
        }
    }

    /// The headline, worklists, safety groups and the part with no advice.
    private func content(_ groups: [ReclaimModel.TierGroup]) -> some View {
        let figures = ReclaimModel.headline(groups)
        return ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                LensHeadline(
                    title: Text(Format.bytes(figures.reclaimable)).foregroundColor(Theme.accent)
                        + Text(" you could get back, in \(figures.decisions) decisions"),
                    subtitle: headlineNote(figures.lookFirst))
                WorklistSection(workspace: workspace)
                ForEach(groups) { group in
                    TierSection(workspace: workspace, group: group)
                }
                NoAdviceCard(bytes: ReclaimModel.noAdviceBytes(total: workspace.baseLens?.size.first ?? 0, groups: groups))
            }
            .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
    }

    /// The reassurance under the headline, plus what sits in Look first.
    private func headlineNote(_ lookFirst: UInt64) -> String {
        let base = "Nothing is marked for you. Staging a group removes nothing until you apply the plan, and applying only moves things to the Trash."
        return lookFirst > 0 ? base + " Another \(Format.bytes(lookFirst)) sits in Look first, which only you can judge." : base
    }
}

/// The worklists: short lists chosen by a measured fact.
struct WorklistSection: View {
    let workspace: Workspace

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WHERE TO START").font(.system(size: 11, weight: .semibold)).tracking(0.6).foregroundStyle(Theme.textSecondary)
            ViewThatFits(in: .horizontal) {
                grid(columns: 2).frame(minWidth: 920)
                grid(columns: 1)
            }
        }
    }

    /// The cards in `columns` equal columns, so the row always fills the width.
    private func grid(columns: Int) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: columns), alignment: .leading, spacing: 10) {
            ForEach(shown, id: \.id) { entry in entry.card }
        }
    }

    /// One card per question, in a fixed order: forgotten, duplicates, leftovers, largest undecided.
    private var shown: [(id: String, card: AnyView)] {
        var result: [(id: String, card: AnyView)] = []
        for kind in WorklistKind.allCases {
            if let list = workspace.worklists.first(where: { $0.kind == kind }) {
                result.append((list.id, AnyView(WorklistCard(workspace: workspace, worklist: list))))
            } else if kind == .duplicates {
                result.append(("duplicates", AnyView(DuplicatesCard(workspace: workspace))))
            }
        }
        return result
    }
}

/// One worklist: its question, the fact behind it, its size and a way in.
struct WorklistCard: View {
    let workspace: Workspace
    let worklist: Worklist

    var body: some View {
        let certainty = worklist.kind == .leftovers
            ? ReclaimModel.leftoverCertainty(worklist, ownership: workspace.ownershipReport, tree: workspace.tree) : (guesses: 0, identified: 0)
        CardFrame {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Text(worklist.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                    Text(ReclaimModel.listFigures(worklist)).font(Theme.number(size: 12)).foregroundStyle(Theme.textMuted)
                }
                Text(worklist.why).font(.system(size: 13)).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                if let note = ReclaimModel.guessNote(guesses: certainty.guesses, identified: certainty.identified) {
                    Text(note).font(.system(size: 12)).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button("Look through") { workspace.startReview(worklist: worklist) }.buttonStyle(GhostButtonStyle()).padding(.top, 4)
            }
        } trailing: {
            Text(Format.bytes(worklist.bytes)).font(Theme.number(size: 19, weight: .semibold)).foregroundStyle(Theme.textPrimary)
        }
    }
}

/// The duplicates question before and during the search, which reads file contents and so waits for the user.
struct DuplicatesCard: View {
    let workspace: Workspace

    var body: some View {
        let state = workspace.analysis[.duplicates] ?? .idle
        CardFrame {
            VStack(alignment: .leading, spacing: 5) {
                Text("Duplicates").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                Text(explanation(state)).font(.system(size: 13)).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                control(state).padding(.top, 4)
            }
        } trailing: { EmptyView() }
    }

    /// What this card says in each state.
    private func explanation(_ state: StageState) -> String {
        switch state {
        case .running: "Comparing files of the same size by their contents. You can stop at any time."
        case .done: "No two files with identical contents were found at the size this search checks."
        default: "Finds files with identical contents. This reads file contents, so it only runs when you ask."
        }
    }

    /// The button or progress for the state.
    @ViewBuilder private func control(_ state: StageState) -> some View {
        switch state {
        case .running(let fraction):
            HStack(spacing: 10) {
                if let fraction { ProgressView(value: fraction).tint(Theme.accent).frame(maxWidth: 220) } else { ProgressView().controlSize(.small) }
                Text(fraction.map { "\(Int($0 * 100))%" } ?? "Reading…").font(Theme.number(size: 12)).foregroundStyle(Theme.textSecondary)
                Button("Stop") { workspace.cancelAnalyses() }.buttonStyle(GhostButtonStyle())
            }
        case .done:
            Button("Search again") { workspace.findDuplicates() }.buttonStyle(GhostButtonStyle())
        default:
            Button("Find duplicates") { workspace.findDuplicates() }.buttonStyle(GhostButtonStyle(ink: Theme.textPrimary))
        }
    }
}

/// One safety group: a tier pill, what the tier means, and its families.
struct TierSection: View {
    let workspace: Workspace
    let group: ReclaimModel.TierGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                TierPill(tier: group.tier)
                Text(group.blurb).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                Text(Format.bytes(group.bytes)).font(Theme.number(size: 12)).foregroundStyle(Theme.textMuted)
            }
            VStack(spacing: 8) {
                ForEach(group.families) { family in FamilyCard(workspace: workspace, family: family) }
            }
        }
    }
}

/// One rule family: title, meta, plain consequence, the cleanup command as text, size and actions.
struct FamilyCard: View {
    let workspace: Workspace
    let family: ReclaimFamily

    var body: some View {
        let rule = family.rule
        let offered = rule.tier != .never
        let staged = ReclaimModel.isStaged(family.nodes, effective: workspace.resolved?.effective)
        CardFrame {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Text(rule.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                    Text(ReclaimModel.meta(family, now: Int32(clamping: Int(workspace.environment.clock().timeIntervalSince1970))))
                        .font(Theme.number(size: 12)).foregroundStyle(Theme.textMuted)
                }
                Text(rule.consequence).font(.system(size: 13)).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                if let condition = rule.sideCondition {
                    Text(condition).font(.system(size: 12)).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                }
                if let command = rule.cleanupCommand {
                    HStack(spacing: 6) {
                        Text("Cleaner with the official tool:").font(.system(size: 12)).foregroundStyle(Theme.textMuted)
                        Text(command).font(Theme.mono(size: 12)).foregroundStyle(Theme.textPrimary).textSelection(.enabled)
                    }
                    .padding(.top, 4)
                }
            }
        } trailing: {
            VStack(alignment: .trailing, spacing: 6) {
                Text(Format.bytes(family.bytes)).font(Theme.number(size: 19, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                if offered, family.reclaimable < family.bytes {
                    Text("frees \(Format.bytes(family.reclaimable)) right away").font(.system(size: 11)).foregroundStyle(Theme.textMuted)
                }
                if offered {
                    HStack(spacing: 6) {
                        Button("Look through") { workspace.startReview(family: family) }.buttonStyle(GhostButtonStyle())
                        Button(staged ? "Unstage" : "Stage for removal") {
                            workspace.mark(staged ? .none : .remove, nodes: family.nodes)
                        }
                        .buttonStyle(GhostButtonStyle(ink: staged ? Theme.remove : Theme.textPrimary))
                    }
                }
            }
        }
        .overlay(alignment: .leading) {
            if staged { HatchFill(spacing: 4).frame(width: 5).clipShape(RoundedRectangle(cornerRadius: 2)).padding(.vertical, 8) }
        }
    }
}

/// The part of the disk no rule speaks about, shown honestly with its size.
struct NoAdviceCard: View {
    let bytes: UInt64

    var body: some View {
        if bytes > 0 {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Text("No advice").font(.system(size: 11, weight: .semibold)).padding(.horizontal, 7).padding(.vertical, 1)
                        .foregroundStyle(Theme.textSecondary).background(Capsule().fill(Theme.surfaceRaised))
                    Text("Only you can judge this part.").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                }
                CardFrame {
                    Text("DeepYellow has no rule for this part of the disk. It is mostly your own files, so nothing here is suggested. Use Things or Browse to look through it.")
                        .font(.system(size: 13)).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                } trailing: {
                    Text(Format.bytes(bytes)).font(Theme.number(size: 19, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                }
            }
        }
    }
}

/// The rounded card used by worklists and families: content on the left, figures and actions on the right.
struct CardFrame<Content: View, Trailing: View>: View {
    @ViewBuilder let content: Content
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            content.frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 0, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 11).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Theme.hairline, lineWidth: 1))
    }
}
