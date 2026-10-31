import Foundation
import DYCore

/// Turns resolved decisions into the exact list of roots to move to the Trash.
///
/// This is the last line of defence. It trusts nothing about its input: whatever `resolved` says, a guarded node is
/// never planned, a plan never holds a parent together with its child, and a directory that holds anything kept,
/// guarded or stale is split instead of moved.
public enum RemovalPlanner {
    /// Builds the plan for `tree`.
    ///
    /// - Parameters:
    ///   - resolved: Effective decisions for `tree`. If its size doesn't match the tree, nothing is planned.
    ///   - nodeTier: `SafetyTier` raw value per node, or empty when there is no advice.
    ///   - home: The user's home directory path.
    public static func plan(tree: FileTree, resolved: ResolvedDecisions, nodeTier: [UInt8], home: String) -> RemovalPlan {
        guard resolved.effective.count == tree.count, nodeTier.isEmpty || nodeTier.count == tree.count else {
            return RemovalPlan(blocked: [BlockedItem(path: tree.name(0), reason: "The decisions don't match this scan")])
        }
        var walk = PlanWalk(tree: tree, effective: resolved.effective,
                            guards: PlannerGuards(tree: tree, tier: nodeTier, stalePaths: resolved.stalePaths, home: home))
        walk.run()
        walk.reportStale(resolved.stalePaths)
        return walk.finish()
    }
}

/// One pass over a tree that collects plan items, protected paths and blocked paths.
private struct PlanWalk {
    let tree: FileTree
    let effective: [UInt8]
    let guards: PlannerGuards
    /// The subtree holds a remove-effective node.
    private var hasRemove: [Bool]
    /// Something strictly below the node is not removable: kept, guarded or stale.
    private var holdsObstacle: [Bool]
    private var items: [PlanItem] = []
    private var protected: [String] = []
    private var blocked: [BlockedItem] = []
    private var blockedPaths: Set<String> = []

    /// Precomputes the two subtree flags.
    init(tree: FileTree, effective: [UInt8], guards: PlannerGuards) {
        self.tree = tree
        self.effective = effective
        self.guards = guards
        hasRemove = effective.map { $0 == Decision.remove.rawValue }
        holdsObstacle = [Bool](repeating: false, count: tree.count)
        for index in stride(from: tree.count - 1, to: 0, by: -1) {
            let parent = Int(tree.columns.parent[index])
            let obstacle = effective[index] != Decision.remove.rawValue || guards.hazard(NodeID(index)) != nil
            if hasRemove[index] { hasRemove[parent] = true }
            if obstacle || holdsObstacle[index] { holdsObstacle[parent] = true }
        }
    }

    /// Walks from the root, emitting each removable root once and splitting directories that hold obstacles.
    mutating func run() {
        var stack: [(node: NodeID, inPhotos: Bool, inRemoved: Bool)] = [(0, false, false)]
        while let (node, outerPhotos, inRemoved) = stack.popLast() {
            let inPhotos = outerPhotos || PlannerGuards.isPhotosLibrary(tree, node)
            guard effective[Int(node)] == Decision.remove.rawValue else {
                visitNotRemoved(node, inRemoved: inRemoved, inPhotos: inPhotos, stack: &stack)
                continue
            }
            let path = tree.path(node)
            if let reason = PlannerGuards.pathProblem(path) ?? (inPhotos ? "Inside a Photos library; manage it in Photos" : nil)
                ?? guards.hazard(node) {
                block(path, reason)
            } else if holdsObstacle[Int(node)] {
                for child in tree.children(node) { stack.append((child, inPhotos, true)) }
            } else {
                emit(node, path: path)
            }
        }
    }

    /// Handles a node that stays: records it when it sits inside a split directory, and looks below for deeper removals.
    private mutating func visitNotRemoved(_ node: NodeID, inRemoved: Bool, inPhotos: Bool,
                                          stack: inout [(node: NodeID, inPhotos: Bool, inRemoved: Bool)]) {
        if inRemoved { protected.append(tree.path(node)) }
        guard hasRemove[Int(node)] else { return }
        for child in tree.children(node) where hasRemove[Int(child)] { stack.append((child, inPhotos, false)) }
    }

    /// Reports stale verdicts that the walk didn't already refuse, unless a keep or later covers them.
    mutating func reportStale(_ stalePaths: [String]) {
        for path in stalePaths where !blockedPaths.contains(path) {
            guard let node = tree.find(path: path) else { continue }
            let decision = effective[Int(node)]
            if decision == Decision.keep.rawValue || decision == Decision.later.rawValue { continue }
            block(path, "Changed since you marked it")
        }
    }

    /// The finished plan, with a stable order.
    func finish() -> RemovalPlan {
        RemovalPlan(items: items.sorted { ($0.bytes, $1.id) > ($1.bytes, $0.id) },
                    protected: protected.sorted(), blocked: blocked.sorted { $0.path < $1.path })
    }

    /// Records a refusal once per path.
    private mutating func block(_ path: String, _ reason: String) {
        guard blockedPaths.insert(path).inserted else { return }
        blocked.append(BlockedItem(path: path, reason: reason))
    }

    /// Records `node` as a plan item.
    private mutating func emit(_ node: NodeID, path: String) {
        let allocated = tree.allocated(node)
        let reclaimable = min(tree.privateBytes(node), allocated)
        let flags = tree.flags(node)
        let lowerBound = reclaimable < allocated || flags.contains(.mayShareBlocks) || flags.contains(.privateUnknown)
        items.append(PlanItem(id: path, node: node, bytes: allocated, reclaimable: reclaimable,
                              fingerprint: Fingerprint(tree: tree, node: node), reclaimIsLowerBound: lowerBound))
    }
}
