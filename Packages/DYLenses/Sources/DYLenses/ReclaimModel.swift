import DYAdvisor
import DYCore
import Foundation

/// Pure grouping and wording for the Reclaim lens.
enum ReclaimModel {
    /// One safety group with the families that fall in it.
    struct TierGroup: Identifiable {
        var id: SafetyTier { tier }
        let tier: SafetyTier
        let title: String
        let blurb: String
        let families: [ReclaimFamily]
        /// Bytes under the families.
        var bytes: UInt64 { families.reduce(0) { $0 + $1.bytes } }
        /// Bytes that removal would free right away.
        var reclaimable: UInt64 { families.reduce(0) { $0 + $1.reclaimable } }
    }

    /// What the lens shows: families and worklists, narrowed to the current filter when one is active.
    struct Scope {
        var groups: [TierGroup]
        var worklists: [Worklist]
        /// Bytes each family and worklist holds without any filter, by id. Empty when nothing is narrowed.
        var fullBytes: [String: UInt64]
        /// Bytes the whole view holds, for the "no advice" remainder.
        var totalBytes: UInt64
        var isNarrowed: Bool
        /// True when the unfiltered duplicates list exists, so the lens must not offer the search again.
        var hasDuplicateList: Bool
        /// True when nothing offers advice in the current result.
        var isEmpty: Bool { groups.isEmpty && worklists.isEmpty }
    }

    /// Builds the scope. With no filter (`lens === baseLens`) it is the unfiltered report, unchanged.
    static func scope(report: ReclaimReport, worklists: [Worklist], lens: TreeLens?, baseLens: TreeLens?) -> Scope {
        let hasDuplicates = worklists.contains { $0.kind == .duplicates }
        guard let lens, let baseLens, lens !== baseLens else {
            return Scope(groups: groups(report), worklists: worklists, fullBytes: [:], totalBytes: baseLens?.size.first ?? 0,
                         isNarrowed: false, hasDuplicateList: hasDuplicates)
        }
        var full: [String: UInt64] = [:]
        let families = report.families.compactMap { family -> ReclaimFamily? in
            full[family.id] = family.bytes
            return narrow(family, lens: lens)
        }
        let lists = worklists.compactMap { list -> Worklist? in
            full[list.id] = list.bytes
            return narrow(list, lens: lens)
        }
        return Scope(groups: groups(families), worklists: lists, fullBytes: full, totalBytes: lens.size.first ?? 0,
                     isNarrowed: true, hasDuplicateList: hasDuplicates)
    }

    /// The nodes that pass the lens and still hold bytes.
    static func visible(_ nodes: [NodeID], lens: TreeLens) -> [NodeID] {
        nodes.filter { lens.included[Int($0)] && lens.size[Int($0)] > 0 }
    }

    /// A family cut to the nodes in the result, with bytes and files re-summed from the lens. Nil when nothing is left.
    static func narrow(_ family: ReclaimFamily, lens: TreeLens) -> ReclaimFamily? {
        let nodes = visible(family.nodes, lens: lens)
        guard !nodes.isEmpty else { return nil }
        let bytes = nodes.reduce(UInt64(0)) { $0 + lens.size[Int($1)] }
        let files = nodes.reduce(UInt64(0)) { $0 + UInt64(lens.files[Int($1)]) }
        return ReclaimFamily(rule: family.rule, nodes: nodes, bytes: bytes, reclaimable: min(family.reclaimable, bytes), files: files,
                             newestModified: family.newestModified)
    }

    /// A worklist cut to the nodes in the result. Nil when nothing is left.
    static func narrow(_ list: Worklist, lens: TreeLens) -> Worklist? {
        let nodes = visible(list.nodes, lens: lens)
        guard !nodes.isEmpty else { return nil }
        let bytes = nodes.reduce(UInt64(0)) { $0 + lens.size[Int($1)] }
        let files = list.kind == .duplicates ? UInt64(nodes.count) : nodes.reduce(UInt64(0)) { $0 + UInt64(lens.files[Int($1)]) }
        return Worklist(kind: list.kind, title: list.title, why: list.why, nodes: nodes, bytes: bytes, files: files)
    }

    /// "12.6 GB in this result, of 18.0 GB" when a card holds less than it would without the filter.
    static func partialNote(bytes: UInt64, full: UInt64?) -> String? {
        guard let full, bytes < full else { return nil }
        return "\(Format.bytes(bytes)) in this result, of \(Format.bytes(full))"
    }

    /// The line under the headline while a filter is active.
    static let narrowedNote = "Narrowed to the current filter. Staging acts on whole folders, and the Plan lists exactly what is staged."

    /// The groups in the order they are shown. Empty groups are dropped.
    static func groups(_ report: ReclaimReport) -> [TierGroup] { groups(report.families) }

    /// The groups for a list of families, which may already be narrowed.
    static func groups(_ families: [ReclaimFamily]) -> [TierGroup] {
        let defs: [(SafetyTier, String, String)] = [
            (.safe, "Safe to remove", "Regenerates by itself. You will not notice it is gone."),
            (.rebuild, "Recoverable at a cost", "Comes back, but costs time, network or a re-login."),
            (.review, "Look first", "May hold something unique. Only you can decide."),
            (.never, "Not offered", "Shown so the numbers add up. DeepYellow will not plan these."),
        ]
        return defs.compactMap { tier, title, blurb in
            let families = families.filter { $0.rule.tier == tier && $0.bytes > 0 }.sorted { $0.bytes > $1.bytes }
            return families.isEmpty ? nil : TierGroup(tier: tier, title: title, blurb: blurb, families: families)
        }
    }

    /// The headline figures: bytes that safe and recoverable groups free, how many groups that is, and the Look first bytes.
    static func headline(_ groups: [TierGroup]) -> (reclaimable: UInt64, decisions: Int, lookFirst: UInt64) {
        let offered = groups.filter { $0.tier == .safe || $0.tier == .rebuild }
        return (offered.reduce(0) { $0 + $1.reclaimable }, offered.reduce(0) { $0 + $1.families.count },
                groups.first { $0.tier == .review }?.bytes ?? 0)
    }

    /// Bytes no rule speaks about: the part only the owner can judge.
    static func noAdviceBytes(total: UInt64, groups: [TierGroup]) -> UInt64 {
        total &- min(total, groups.reduce(0) { $0 + $1.bytes })
    }

    /// "3 items · 12,431 files · newest 4 months ago".
    static func meta(_ family: ReclaimFamily, now: Int32) -> String {
        let items = "\(Format.count(family.nodes.count)) \(family.nodes.count == 1 ? "item" : "items")"
        return "\(items) · \(Format.count(family.files)) files · newest \(Format.age(family.newestModified, now: now))"
    }

    /// Whether every node is already staged for removal.
    static func isStaged(_ nodes: [NodeID], effective: [UInt8]?) -> Bool {
        guard let effective, !nodes.isEmpty else { return false }
        return nodes.allSatisfy { effective.indices.contains(Int($0)) && effective[Int($0)] == Decision.remove.rawValue }
    }

    /// How many leftover folders are only a guess, and how many are named by an app identifier nothing installed matches.
    static func leftoverCertainty(_ worklist: Worklist, ownership: OwnershipReport?, tree: FileTree?) -> (guesses: Int, identified: Int) {
        guard let ownership, let tree else { return (0, 0) }
        var guesses = 0, identified = 0
        for node in worklist.nodes {
            switch ownership.owner(of: node, tree: tree)?.ownership {
            case .possiblyNotInstalled: guesses += 1
            case .notInstalled: identified += 1
            default: break
            }
        }
        return (guesses, identified)
    }

    /// The sentence that labels guesses as guesses.
    static func guessNote(guesses: Int, identified: Int) -> String? {
        guard guesses > 0 else { return nil }
        let guessPart = "\(Format.count(guesses)) \(guesses == 1 ? "is" : "are") a guess: the folder is named like an app, but nothing proves the app is gone."
        guard identified > 0 else { return guessPart }
        let rest = identified == 1 ? "The other one carries" : "The other \(Format.count(identified)) carry"
        return "\(guessPart) \(rest) the identifier of an app that is not installed."
    }

    /// "12 items · 3.4 GB".
    static func listFigures(_ worklist: Worklist) -> String {
        "\(Format.count(worklist.nodes.count)) \(worklist.nodes.count == 1 ? "item" : "items") · \(Format.bytes(worklist.bytes))"
    }
}
