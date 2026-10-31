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

    /// The groups in the order they are shown. Empty groups are dropped.
    static func groups(_ report: ReclaimReport) -> [TierGroup] {
        let defs: [(SafetyTier, String, String)] = [
            (.safe, "Safe to remove", "Regenerates by itself. You will not notice it is gone."),
            (.rebuild, "Recoverable at a cost", "Comes back, but costs time, network or a re-login."),
            (.review, "Look first", "May hold something unique. Only you can decide."),
            (.never, "Not offered", "Shown so the numbers add up. DeepYellow will not plan these."),
        ]
        return defs.compactMap { tier, title, blurb in
            let families = report.families.filter { $0.rule.tier == tier && $0.bytes > 0 }.sorted { $0.bytes > $1.bytes }
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
