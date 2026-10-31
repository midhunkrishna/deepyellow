import DYCore
import Foundation

/// Matches reclaim rules against a scan and resolves what applies to every node. Advice only: nothing is marked,
/// moved or deleted, and cleanup commands are data for display.
public enum ReclaimEngine {
    /// The built-in rules, transcribed from the research notes.
    public static let builtinRules: [ReclaimRule] = BuiltinRules.all

    /// Resolves the governing rule for every node and totals each rule's families.
    ///
    /// A rule applies to the node it matches and everything beneath it. The deepest (most specific) match wins, except
    /// that a `never` ancestor always wins over anything nested in it. SIP-protected nodes are `never`. Returns nil if
    /// `isCancelled` becomes true.
    public static func analyze(lens: TreeLens, home: String, rules: [ReclaimRule], isCancelled: () -> Bool) -> ReclaimReport? {
        let tree = lens.tree
        guard let own = ownMatches(lens: lens, home: home, rules: rules, isCancelled: isCancelled) else { return nil }
        guard let resolved = resolve(tree: tree, rules: rules, own: own, isCancelled: isCancelled) else { return nil }
        let families = buildFamilies(lens: lens, rules: rules, resolved: resolved)
        return ReclaimReport(families: families, nodeTier: resolved.tier, nodeRule: resolved.rule, rules: rules)
    }

    /// Compiles every rule's patterns. A rule may list several full paths separated by ` || `.
    private static func compilePatterns(rules: [ReclaimRule], home: String) -> [(Int, CompiledPattern)] {
        rules.enumerated().flatMap { index, rule in
            rule.pattern.components(separatedBy: " || ").compactMap { part in
                CompiledPattern(pattern: part, home: home).map { (index, $0) }
            }
        }
    }

    /// For each node, the index of the most specific rule matching that node itself, or -1.
    private static func ownMatches(lens: TreeLens, home: String, rules: [ReclaimRule], isCancelled: () -> Bool) -> [Int32]? {
        let tree = lens.tree
        var best = [Int32](repeating: -1, count: tree.count)
        var bestScore = [Int](repeating: -1, count: tree.count)
        let compiled = compilePatterns(rules: rules, home: home)

        func offer(_ ruleIndex: Int, to node: NodeID, _ pattern: CompiledPattern) {
            let slot = Int(node)
            let score = pattern.specificity
            let current = Int(best[slot])
            let wins = score > bestScore[slot]
                || (score == bestScore[slot] && current >= 0 && rules[ruleIndex].tier.rawValue > rules[current].tier.rawValue)
            if wins { best[slot] = Int32(ruleIndex); bestScore[slot] = score }
        }

        for (index, pattern) in compiled where !pattern.floating {
            if isCancelled() { return nil }
            for node in PatternMatcher.anchoredMatches(pattern, lens: lens) { offer(index, to: node, pattern) }
        }
        let floating = compiled.filter { $0.1.floating }
        guard !floating.isEmpty else { return best }
        for node in 1..<max(tree.count, 1) {
            if node & 4095 == 0, isCancelled() { return nil }
            guard lens.included[node] else { continue }
            let id = NodeID(node)
            for (index, pattern) in floating where PatternMatcher.floatingMatches(pattern, node: id, tree: tree) {
                offer(index, to: id, pattern)
            }
        }
        return best
    }

    /// Per-node effective tier and rule after inheritance, `never` ancestors and protected nodes are applied.
    private struct Resolved {
        var tier: [UInt8]
        var rule: [Int32]
        /// Whether the node itself started a rule (as opposed to inheriting one).
        var isRoot: [Bool]
    }

    /// Walks parents before children, applying the precedence rules.
    private static func resolve(tree: FileTree, rules: [ReclaimRule], own: [Int32], isCancelled: () -> Bool) -> Resolved? {
        var result = Resolved(tier: [UInt8](repeating: 0, count: tree.count),
                              rule: [Int32](repeating: -1, count: tree.count),
                              isRoot: [Bool](repeating: false, count: tree.count))
        var leaves = [String](repeating: "", count: rules.count)
        for (index, pattern) in compilePatterns(rules: rules, home: "/") where pattern.floating { leaves[index] = pattern.leaf }
        for index in 0..<tree.count {
            if index & 4095 == 0, isCancelled() { return nil }
            let parent = index == 0 ? -1 : Int(tree.parent(NodeID(index)))
            let inheritedTier = parent >= 0 ? result.tier[parent] : 0
            let inheritedRule = parent >= 0 ? result.rule[parent] : -1
            result.tier[index] = inheritedTier
            result.rule[index] = inheritedRule
            if inheritedTier == SafetyTier.never.rawValue { continue }
            if tree.flags(NodeID(index)).contains(.restricted) {
                result.tier[index] = SafetyTier.never.rawValue
                result.rule[index] = -1
                continue
            }
            let mine = Int(own[index])
            guard mine >= 0 else { continue }
            if inheritedRule >= 0, !leaves[mine].isEmpty, leaves[mine] == leaves[Int(inheritedRule)] { continue }
            result.tier[index] = rules[mine].tier.rawValue
            result.rule[index] = Int32(mine)
            result.isRoot[index] = true
        }
        return result
    }

    /// Groups rule roots into families, carving nested roots out of their enclosing root's totals.
    private static func buildFamilies(lens: TreeLens, rules: [ReclaimRule], resolved: Resolved) -> [ReclaimFamily] {
        let tree = lens.tree
        let count = tree.count
        var rootOf = [Int32](repeating: -1, count: count)
        var carvedBytes = [UInt64](repeating: 0, count: count)
        var carvedFiles = [UInt64](repeating: 0, count: count)
        var carvedPrivate = [UInt64](repeating: 0, count: count)
        var newest = [Int32](repeating: 0, count: count)

        for index in 0..<count {
            let parent = index == 0 ? -1 : Int(tree.parent(NodeID(index)))
            let enclosing = parent >= 0 ? rootOf[parent] : -1
            if resolved.isRoot[index] {
                rootOf[index] = Int32(index)
                if enclosing >= 0 {
                    carvedBytes[Int(enclosing)] &+= lens.size[index]
                    carvedFiles[Int(enclosing)] &+= UInt64(lens.files[index])
                    carvedPrivate[Int(enclosing)] &+= tree.privateBytes(NodeID(index))
                }
            } else {
                rootOf[index] = enclosing
            }
        }
        for index in stride(from: count - 1, through: 0, by: -1) {
            newest[index] = max(newest[index], tree.modified(NodeID(index)))
            if index > 0 {
                let parent = Int(tree.parent(NodeID(index)))
                newest[parent] = max(newest[parent], newest[index])
            }
        }

        var grouped: [Int32: [NodeID]] = [:]
        for index in 0..<count where resolved.isRoot[index] && lens.included[index] {
            grouped[resolved.rule[index], default: []].append(NodeID(index))
        }
        var families: [ReclaimFamily] = []
        for (ruleIndex, nodes) in grouped {
            let rule = rules[Int(ruleIndex)]
            var bytes: UInt64 = 0, files: UInt64 = 0, reclaimable: UInt64 = 0, latest: Int32 = 0
            for node in nodes {
                let slot = Int(node)
                let netBytes = lens.size[slot] &- min(lens.size[slot], carvedBytes[slot])
                bytes &+= netBytes
                files &+= UInt64(lens.files[slot]) &- min(UInt64(lens.files[slot]), carvedFiles[slot])
                let netPrivate = tree.privateBytes(node) &- min(tree.privateBytes(node), carvedPrivate[slot])
                reclaimable &+= min(netPrivate, netBytes)
                latest = max(latest, newest[slot])
            }
            if rule.tier == .never { reclaimable = 0 }
            families.append(ReclaimFamily(rule: rule, nodes: nodes.sorted { lens.size[Int($0)] > lens.size[Int($1)] },
                                          bytes: bytes, reclaimable: reclaimable, files: files, newestModified: latest))
        }
        families.sort { a, b in
            if a.rule.tier != b.rule.tier { return a.rule.tier.rawValue < b.rule.tier.rawValue }
            return a.bytes != b.bytes ? a.bytes > b.bytes : a.rule.id < b.rule.id
        }
        return families
    }
}
