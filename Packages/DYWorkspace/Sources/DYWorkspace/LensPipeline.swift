import DYAnalysis
import DYCore
import DYDecide
import Foundation

/// A previous ignore evaluation, reused while the tree and the rules are unchanged.
struct CachedIgnore: @unchecked Sendable {
    var tree: FileTree
    var rulesRevision: Int
    var result: IgnoreResult
}

/// Everything a lens recomputation reads, captured on the main actor so the work can run anywhere.
struct LensInput: @unchecked Sendable {
    var tree: FileTree
    var rules: IgnoreRuleSet
    var rulesRevision: Int
    var home: String
    var query: Query
    var store: DecisionStore
    /// `SafetyTier` per node, or nil before the reclaim report exists.
    var nodeTier: [UInt8]?
    var trashed: Set<String>
    var now: Int32
    var wantsDominantKinds: Bool
    var cachedIgnore: CachedIgnore?
}

/// The outputs of one recomputation, published together or not at all.
struct LensBundle: @unchecked Sendable {
    var tree: FileTree
    var ignore: IgnoreResult
    var rulesRevision: Int
    var resolved: ResolvedDecisions
    /// Rules and Trash applied, no query.
    var baseLens: TreeLens
    /// Rules, Trash and query applied.
    var lens: TreeLens
    var dominantKinds: [UInt8]
    var plan: RemovalPlan
}

/// Computes a lens bundle: ignore rules, decisions, query, Trash state and the removal plan.
enum LensPipeline {
    /// Builds a bundle, or returns nil if `isCancelled` becomes true. Linear in the size of the tree.
    static func build(_ input: LensInput, isCancelled: () -> Bool) -> LensBundle? {
        let tree = input.tree
        let ignore: IgnoreResult
        if let cached = input.cachedIgnore, cached.tree === tree, cached.rulesRevision == input.rulesRevision {
            ignore = cached.result
        } else {
            guard let evaluated = IgnoreEngine.evaluate(input.rules, tree: tree, home: input.home, isCancelled: isCancelled) else { return nil }
            ignore = evaluated
        }
        let resolved = input.store.resolve(tree: tree)
        if isCancelled() { return nil }
        let removed = removedMask(input.trashed, tree: tree)
        let baseLens = TreeLens(tree: tree, hidden: ignore.hidden, matches: nil, removed: removed)
        var lens = baseLens
        if !input.query.isEmpty {
            let context = QueryContext(decisions: resolved.effective, safety: padded(input.nodeTier, count: tree.count), now: input.now)
            guard let matches = QueryEngine.matches(input.query, tree: tree, context: context, isCancelled: isCancelled) else { return nil }
            lens = TreeLens(tree: tree, hidden: ignore.hidden, matches: matches, removed: removed)
        }
        if isCancelled() { return nil }
        let dominant = input.wantsDominantKinds ? lens.dominantKinds() : []
        let plan = livePlan(tree: tree, resolved: resolved, nodeTier: padded(input.nodeTier, count: tree.count), home: input.home, lens: baseLens)
        return LensBundle(tree: tree, ignore: ignore, rulesRevision: input.rulesRevision, resolved: resolved, baseLens: baseLens,
                          lens: lens, dominantKinds: dominant, plan: plan)
    }

    /// A per-node mask of the paths already moved to the Trash, or nil when there are none.
    static func removedMask(_ trashed: Set<String>, tree: FileTree) -> [Bool]? {
        guard !trashed.isEmpty else { return nil }
        var mask = [Bool](repeating: false, count: tree.count)
        for path in trashed { if let node = tree.find(path: path) { mask[Int(node)] = true } }
        return mask
    }

    /// `tiers` with exactly `count` elements, padding with "no advice".
    static func padded(_ tiers: [UInt8]?, count: Int) -> [UInt8] {
        guard let tiers, tiers.count == count else { return [UInt8](repeating: 0, count: count) }
        return tiers
    }

    /// The removal plan, minus anything already in the Trash or hidden from the views.
    static func livePlan(tree: FileTree, resolved: ResolvedDecisions, nodeTier: [UInt8], home: String, lens: TreeLens) -> RemovalPlan {
        let plan = RemovalPlanner.plan(tree: tree, resolved: resolved, nodeTier: nodeTier, home: home)
        let kept = plan.items.filter { lens.included[Int($0.node)] }
        guard kept.count != plan.items.count else { return plan }
        return RemovalPlan(items: kept, protected: plan.protected, blocked: plan.blocked)
    }
}
