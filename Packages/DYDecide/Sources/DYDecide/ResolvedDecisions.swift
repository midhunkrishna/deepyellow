import Foundation
import DYCore

/// The decisions that apply to one tree, with inheritance resolved and totals computed.
public struct ResolvedDecisions: Sendable {
    /// `Decision` raw value per node, after inheritance. Empty or `tree.count` elements.
    public var effective: [UInt8]
    /// True for a remove-marked directory that holds a keep or later descendant. Such a directory is split, never trashed.
    public var partial: [Bool]
    /// Paths whose recorded fingerprint no longer matches the tree. A stale remove is not applied.
    public var stalePaths: [String]
    /// Bytes that sit under remove, minus whatever a deeper keep or later protects.
    public var removeBytes: UInt64
    /// Bytes that sit under keep, minus whatever a deeper remove or later takes back.
    public var keepBytes: UInt64
    /// Number of separate things a plan would move, before safety guards.
    public var removeRoots: Int
    /// Number of files with no decision either way.
    public var undecided: Int

    /// Creates a resolution. Used by `DecisionStore` and by tests that need an arbitrary input.
    public init(effective: [UInt8] = [], partial: [Bool] = [], stalePaths: [String] = [], removeBytes: UInt64 = 0,
                keepBytes: UInt64 = 0, removeRoots: Int = 0, undecided: Int = 0) {
        self.effective = effective
        self.partial = partial
        self.stalePaths = stalePaths
        self.removeBytes = removeBytes
        self.keepBytes = keepBytes
        self.removeRoots = removeRoots
        self.undecided = undecided
    }
}

/// One stored verdict: what the user chose, and what the node looked like at that moment.
struct DecisionEntry: Codable, Equatable {
    var decision: Decision
    var fingerprint: Fingerprint
}

/// Turns stored verdicts into per-node effective decisions for a particular tree.
enum DecisionResolver {
    /// Resolves `entries` against `tree`. Entries whose path isn't in the tree are ignored, not stale.
    ///
    /// A stale remove is dropped, so it can't take anything out. A stale keep or later is still honoured, because
    /// ignoring a protective verdict could let a file be removed that the user wanted kept.
    static func resolve(entries: [String: DecisionEntry], tree: FileTree) -> ResolvedDecisions {
        let count = tree.count
        var explicit = [UInt8](repeating: 0, count: count)
        var stale: [String] = []
        for (path, entry) in entries {
            guard let node = tree.find(path: path) else { continue }
            if Fingerprint(tree: tree, node: node) != entry.fingerprint {
                stale.append(path)
                if entry.decision == .remove { continue }
            }
            explicit[Int(node)] = entry.decision.rawValue
        }
        let effective = inherit(explicit, tree: tree)
        let partial = markPartial(effective, tree: tree)
        var resolved = ResolvedDecisions(effective: effective, partial: partial, stalePaths: stale.sorted())
        resolved.removeBytes = bytes(under: .remove, effective: effective, tree: tree)
        resolved.keepBytes = bytes(under: .keep, effective: effective, tree: tree)
        resolved.removeRoots = countRoots(effective: effective, partial: partial, tree: tree)
        resolved.undecided = countUndecided(effective: effective, tree: tree)
        return resolved
    }

    /// Pushes each explicit verdict down to descendants that have none. The deepest explicit verdict wins.
    static func inherit(_ explicit: [UInt8], tree: FileTree) -> [UInt8] {
        var effective = explicit
        for index in 1..<max(1, tree.count) where effective[index] == 0 {
            effective[index] = effective[Int(tree.columns.parent[index])]
        }
        return effective
    }

    /// Flags remove-effective directories that contain anything not removed.
    static func markPartial(_ effective: [UInt8], tree: FileTree) -> [Bool] {
        var partial = [Bool](repeating: false, count: tree.count)
        let remove = Decision.remove.rawValue
        for index in stride(from: tree.count - 1, to: 0, by: -1) {
            let parent = Int(tree.columns.parent[index])
            guard effective[parent] == remove else { continue }
            if effective[index] != remove || partial[index] { partial[parent] = true }
        }
        return partial
    }

    /// Bytes whose effective decision is `decision`. A directory's own bytes are what's left after its children.
    static func bytes(under decision: Decision, effective: [UInt8], tree: FileTree) -> UInt64 {
        var childTotal = [UInt64](repeating: 0, count: tree.count)
        for index in 1..<max(1, tree.count) {
            childTotal[Int(tree.columns.parent[index])] &+= tree.allocated(NodeID(index))
        }
        var accumulated = [UInt64](repeating: 0, count: tree.count)
        for index in stride(from: tree.count - 1, through: 0, by: -1) {
            if effective[index] == decision.rawValue {
                let total = tree.allocated(NodeID(index))
                accumulated[index] &+= total > childTotal[index] ? total - childTotal[index] : 0
            }
            if index > 0 { accumulated[Int(tree.columns.parent[index])] &+= accumulated[index] }
        }
        return tree.count == 0 ? 0 : accumulated[0]
    }

    /// Counts the separate things a plan would move: remove-effective, unsplit nodes not covered by a bigger one.
    static func countRoots(effective: [UInt8], partial: [Bool], tree: FileTree) -> Int {
        let remove = Decision.remove.rawValue
        var roots = 0
        for index in 0..<tree.count where effective[index] == remove && !partial[index] {
            if index == 0 { roots += 1; continue }
            let parent = Int(tree.columns.parent[index])
            if effective[parent] != remove || partial[parent] { roots += 1 }
        }
        return roots
    }

    /// Counts files that have no decision.
    static func countUndecided(effective: [UInt8], tree: FileTree) -> Int {
        var count = 0
        for index in 0..<tree.count where effective[index] == 0 && !tree.isDirectory(NodeID(index)) { count += 1 }
        return count
    }
}
