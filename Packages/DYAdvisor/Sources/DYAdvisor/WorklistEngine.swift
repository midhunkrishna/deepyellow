import DYAnalysis
import DYCore
import Foundation

/// Which question a worklist answers.
public enum WorklistKind: Sendable, CaseIterable {
    case forgotten, duplicates, leftovers, largestUndecided
}

/// A short list of places worth a look, chosen by a measured fact rather than a guess about value.
public struct Worklist: Identifiable, Sendable {
    public var id: String { String(describing: kind) }
    public let kind: WorklistKind
    public let title: String
    /// One concrete sentence on why these items are listed.
    public let why: String
    public let nodes: [NodeID]
    public let bytes: UInt64
    public let files: UInt64

    /// Creates a worklist.
    public init(kind: WorklistKind, title: String, why: String, nodes: [NodeID], bytes: UInt64, files: UInt64) {
        self.kind = kind
        self.title = title
        self.why = why
        self.nodes = nodes
        self.bytes = bytes
        self.files = files
    }
}

/// Builds the worklists. Lists are advice only: nothing here marks, moves or deletes anything.
public enum WorklistEngine {
    /// Smallest item the forgotten list considers.
    static let forgottenThreshold: UInt64 = 100_000_000
    /// Age beyond which an untouched item counts as forgotten.
    static let forgottenAge: Int32 = 365 * 86_400
    /// Most items on the largest-undecided list.
    static let largestCount = 25

    /// Computes every list that has at least one item.
    ///
    /// Items with a `never` tier (or inside one), protected items, and items the user has decided, or that hold a decided
    /// item, are excluded from every list. `decisions` holds effective `Decision` raw values per node.
    public static func compute(lens: TreeLens, report: ReclaimReport, ownership: OwnershipReport, duplicates: DuplicateReport?,
                               decisions: [UInt8], now: Int32) -> [Worklist] {
        let filter = Exclusions(lens: lens, tiers: report.nodeTier, decisions: decisions)
        let lists = [forgotten(lens, filter, now), self.duplicates(lens, filter, duplicates), leftovers(lens, filter, ownership),
                     largestUndecided(lens, filter)]
        return lists.compactMap { $0 }
    }

    /// Which nodes may appear on a list.
    private struct Exclusions {
        let blocked: [Bool]
        let holdsDecision: [Bool]

        /// Marks nodes that are `never`, protected or decided, and the ancestors of decided nodes.
        init(lens: TreeLens, tiers: [UInt8], decisions: [UInt8]) {
            let tree = lens.tree
            var blocked = [Bool](repeating: false, count: tree.count)
            var holds = [Bool](repeating: false, count: tree.count)
            for index in 0..<tree.count {
                let decided = index < decisions.count && decisions[index] != Decision.none.rawValue
                let never = index < tiers.count && tiers[index] == SafetyTier.never.rawValue
                blocked[index] = decided || never || tree.flags(NodeID(index)).contains(.restricted)
            }
            for index in stride(from: tree.count - 1, to: 0, by: -1) where blocked[index] || holds[index] {
                if index < decisions.count && decisions[index] != Decision.none.rawValue || holds[index] {
                    holds[Int(tree.columns.parent[index])] = true
                }
            }
            self.blocked = blocked
            self.holdsDecision = holds
        }

        /// Whether `node` may be listed.
        func allows(_ node: NodeID) -> Bool { !blocked[Int(node)] && !holdsDecision[Int(node)] }
    }

    /// Big things whose newest modification anywhere inside is over a year old.
    private static func forgotten(_ lens: TreeLens, _ filter: Exclusions, _ now: Int32) -> Worklist? {
        let tree = lens.tree
        let newest = newestModified(lens)
        let cut = ThingsEngine.cut(lens: lens, under: tree.root, threshold: forgottenThreshold, metric: .bytes)
        let nodes = cut.items.compactMap { thing -> NodeID? in
            guard case .node(let node) = thing.content, node != tree.root, filter.allows(node),
                  now &- newest[Int(node)] > forgottenAge else { return nil }
            return node
        }
        guard !nodes.isEmpty else { return nil }
        let bytes = total(nodes, lens), files = totalFiles(nodes, lens)
        let why = "\(nodes.count) items of at least \(Format.bytes(forgottenThreshold)) each, nothing inside changed in over a year, "
            + "\(Format.bytes(bytes)) in all."
        return Worklist(kind: .forgotten, title: "Not touched in over a year", why: why, nodes: nodes, bytes: bytes, files: files)
    }

    /// The copies beyond the oldest one in each duplicate set.
    private static func duplicates(_ lens: TreeLens, _ filter: Exclusions, _ report: DuplicateReport?) -> Worklist? {
        guard let report else { return nil }
        let tree = lens.tree
        var nodes: [NodeID] = []
        for set in report.sets {
            let members = set.nodes.filter { Int($0) < tree.count && lens.included[Int($0)] }
            guard members.count > 1, let keeper = members.min(by: { (tree.modified($0), $0) < (tree.modified($1), $1) }) else { continue }
            nodes += members.filter { $0 != keeper && filter.allows($0) }
        }
        guard !nodes.isEmpty else { return nil }
        nodes.sort { lens.size[Int($0)] != lens.size[Int($1)] ? lens.size[Int($0)] > lens.size[Int($1)] : $0 < $1 }
        let bytes = total(nodes, lens)
        let why = "\(nodes.count) files are byte-for-byte copies of an older file, \(Format.bytes(bytes)) in all. The oldest copy of each is not listed."
        return Worklist(kind: .duplicates, title: "Duplicate files", why: why, nodes: nodes, bytes: bytes, files: UInt64(nodes.count))
    }

    /// Library folders whose app is not installed, or probably not.
    private static func leftovers(_ lens: TreeLens, _ filter: Exclusions, _ ownership: OwnershipReport) -> Worklist? {
        var sure = 0, guesses = 0
        let found = ownership.folders.compactMap { folder -> NodeID? in
            guard filter.allows(folder.node), lens.size[Int(folder.node)] > 0 else { return nil }
            switch folder.ownership {
            case .notInstalled: sure += 1
            case .possiblyNotInstalled: guesses += 1
            case .installed: return nil
            }
            return folder.node
        }
        guard !found.isEmpty else { return nil }
        let nodes = found.sorted { lens.size[Int($0)] != lens.size[Int($1)] ? lens.size[Int($0)] > lens.size[Int($1)] : $0 < $1 }
        let bytes = total(nodes, lens)
        let why = leftoversWhy(sure: sure, guesses: guesses, bytes: bytes)
        return Worklist(kind: .leftovers, title: "Left behind by apps", why: why, nodes: nodes, bytes: bytes, files: totalFiles(nodes, lens))
    }

    /// The sentence behind the leftovers list, with singular and plural wording and guesses named as guesses.
    static func leftoversWhy(sure: Int, guesses: Int, bytes: UInt64) -> String {
        func folders(_ count: Int) -> String { count == 1 ? "1 folder" : "\(count) folders" }
        var why: String
        if sure > 0 {
            why = "\(folders(sure)) in your Library \(sure == 1 ? "is" : "are") named for an app that isn't installed"
            if guesses > 0 { why += ", and \(guesses) more look\(guesses == 1 ? "s" : "") like \(guesses == 1 ? "it" : "that") but that is a guess" }
        } else {
            why = "\(folders(guesses)) in your Library look\(guesses == 1 ? "s" : "") like \(guesses == 1 ? "it belongs" : "they belong") to an app that isn't installed, but that is a guess"
        }
        return why + ". \(Format.bytes(bytes)) in all."
    }

    /// The biggest things with no verdict yet.
    private static func largestUndecided(_ lens: TreeLens, _ filter: Exclusions) -> Worklist? {
        let tree = lens.tree
        let threshold = max(lens.size[Int(tree.root)] / 100, 1)
        let cut = ThingsEngine.cut(lens: lens, under: tree.root, threshold: threshold, metric: .bytes)
        let nodes = cut.items.compactMap { thing -> NodeID? in
            guard case .node(let node) = thing.content, node != tree.root, filter.allows(node) else { return nil }
            return node
        }.prefix(largestCount)
        guard !nodes.isEmpty else { return nil }
        let list = Array(nodes)
        let bytes = total(list, lens)
        let why = "The \(list.count) biggest things you haven't decided on, \(Format.bytes(bytes)) in all."
        return Worklist(kind: .largestUndecided, title: "Largest, undecided", why: why, nodes: list, bytes: bytes, files: totalFiles(list, lens))
    }

    /// Sum of visible bytes.
    private static func total(_ nodes: [NodeID], _ lens: TreeLens) -> UInt64 { nodes.reduce(0) { $0 &+ lens.size[Int($1)] } }

    /// Sum of visible file counts.
    private static func totalFiles(_ nodes: [NodeID], _ lens: TreeLens) -> UInt64 { nodes.reduce(0) { $0 &+ UInt64(lens.files[Int($1)]) } }

    /// The newest modification time in every visible subtree.
    private static func newestModified(_ lens: TreeLens) -> [Int32] {
        let tree = lens.tree
        var newest = tree.columns.modified
        for index in stride(from: tree.count - 1, to: 0, by: -1) where lens.included[index] {
            let parent = Int(tree.columns.parent[index])
            newest[parent] = max(newest[parent], newest[index])
        }
        return newest
    }
}
