import DYCore
import Foundation

/// Evaluates an `IgnoreRuleSet` against a tree in one linear pass.
///
/// Semantics: a hide rule hides the matched node and everything beneath it. A `!` rule on the same node keeps it
/// visible and beats any hide rule that matches it. A `!` rule cannot reveal a node whose ancestor is hidden.
public enum IgnoreEngine {
    /// How a pattern selects nodes.
    private enum Shape {
        /// One component, matched against a node's own name at any depth.
        case name(Glob)
        /// Several components, matched against the node and its ancestors' names at any depth.
        case chain([Glob])
        /// Components from the filesystem root.
        case anchored([Glob])
    }

    private struct Compiled {
        let index: Int
        let keep: Bool
        let dirOnly: Bool
        let shape: Shape
    }

    /// Computes which nodes are hidden. Returns nil if cancelled.
    public static func evaluate(_ rules: IgnoreRuleSet, tree: FileTree, home: String, isCancelled: () -> Bool) -> IgnoreResult? {
        let compiled = rules.rules.enumerated().compactMap { index, rule in
            rule.enabled ? compile(rule.pattern, index: index, home: home) : nil
        }
        var perRule: [UUID: (bytes: UInt64, files: UInt64)] = [:]
        for item in compiled where !item.keep { perRule[rules.rules[item.index].id] = (0, 0) }
        let count = tree.count
        var hidden = [Bool](repeating: false, count: count)
        guard count > 0, !compiled.isEmpty else { return IgnoreResult(hidden: hidden, perRule: perRule) }

        let anchored = resolveAnchored(compiled, tree: tree)
        let (buckets, generic) = bucketNameRules(compiled)
        let columns = tree.columns
        let hasAnchored = !anchored.hide.isEmpty

        let cancelled: Bool = NameReader.with(tree) { names in
            for index in 1..<max(count, 1) {
                if index & 0xFFFF == 0, isCancelled() { return true }
                if hidden[Int(columns.parent[index])] {
                    hidden[index] = true
                    continue
                }
                var hideRule = Int.max
                var keep = false
                if hasAnchored {
                    let rule = anchored.hide[index]
                    if rule >= 0 { hideRule = Int(rule) }
                    keep = anchored.keep[index]
                }
                let name = names.name(index)
                if let first = name.first {
                    let isDirectory = columns.flags[index] & NodeFlags.directory.rawValue != 0
                    let bucket = buckets[Int(Glob.lower(first))]
                    for pass in 0..<2 {
                        for ruleIndex in (pass == 0 ? bucket : generic) {
                            let rule = compiled[ruleIndex]
                            if rule.dirOnly && !isDirectory { continue }
                            if !rule.keep && rule.index >= hideRule { continue }
                            if rule.keep && keep { continue }
                            guard nameMatches(rule.shape, node: index, name: name, tree: tree) else { continue }
                            if rule.keep { keep = true } else { hideRule = rule.index }
                        }
                    }
                }
                if hideRule != Int.max && !keep {
                    hidden[index] = true
                    let id = rules.rules[hideRule].id
                    let current = perRule[id] ?? (0, 0)
                    perRule[id] = (current.bytes &+ columns.allocated[index], current.files &+ UInt64(columns.fileCount[index]))
                }
            }
            return false
        }
        if cancelled { return nil }
        return IgnoreResult(hidden: hidden, perRule: perRule)
    }

    /// Parses one pattern, or returns nil for blank and comment lines.
    private static func compile(_ pattern: String, index: Int, home: String) -> Compiled? {
        var text = pattern.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !text.hasPrefix("#") else { return nil }
        let keep = text.hasPrefix("!")
        if keep { text.removeFirst() }
        if text == "~" || text.hasPrefix("~/") { text = home + text.dropFirst() }
        let dirOnly = text.hasSuffix("/") && text.count > 1
        while text.count > 1, text.hasSuffix("/") { text.removeLast() }
        guard !text.isEmpty else { return nil }
        let isAnchored = text.hasPrefix("/")
        let parts = text.split(separator: "/", omittingEmptySubsequences: true).map { Glob(String($0)) }
        guard !parts.isEmpty else { return nil }
        let shape: Shape = isAnchored ? .anchored(parts) : (parts.count == 1 ? .name(parts[0]) : .chain(parts))
        return Compiled(index: index, keep: keep, dirOnly: dirOnly, shape: shape)
    }

    /// Splits name and chain rules into 256 buckets by first literal byte, plus one list for wildcard-first rules.
    private static func bucketNameRules(_ compiled: [Compiled]) -> ([[Int]], [Int]) {
        var buckets = [[Int]](repeating: [], count: 256)
        var generic: [Int] = []
        for (position, rule) in compiled.enumerated() {
            let last: Glob
            switch rule.shape {
            case .name(let glob): last = glob
            case .chain(let globs): last = globs[globs.count - 1]
            case .anchored: continue
            }
            if let first = last.literalFirstByte { buckets[Int(first)].append(position) } else { generic.append(position) }
        }
        return (buckets, generic)
    }

    /// Whether a name or chain rule matches the node, comparing bytes in place.
    private static func nameMatches(_ shape: Shape, node: Int, name: UnsafeBufferPointer<UInt8>, tree: FileTree) -> Bool {
        switch shape {
        case .name(let glob):
            return glob.matches(name)
        case .chain(let globs):
            guard globs[globs.count - 1].matches(name) else { return false }
            var current = tree.parent(NodeID(node))
            for glob in globs.dropLast().reversed() {
                guard current >= 0 else { return false }
                if !tree.withName(current, { glob.matches($0) }) { return false }
                current = tree.parent(current)
            }
            return true
        case .anchored:
            return false
        }
    }

    /// Resolves path-anchored rules to node marks by walking only the matching branches.
    private static func resolveAnchored(_ compiled: [Compiled], tree: FileTree) -> (hide: [Int32], keep: [Bool]) {
        let anchoredRules = compiled.filter { if case .anchored = $0.shape { true } else { false } }
        guard !anchoredRules.isEmpty else { return ([], []) }
        var hide = [Int32](repeating: -1, count: tree.count)
        var keep = [Bool](repeating: false, count: tree.count)
        for rule in anchoredRules {
            guard case .anchored(let globs) = rule.shape else { continue }
            for node in resolve(globs, tree: tree) {
                if rule.dirOnly && !tree.isDirectory(node) { continue }
                if rule.keep { keep[Int(node)] = true } else if hide[Int(node)] < 0 || Int32(rule.index) < hide[Int(node)] { hide[Int(node)] = Int32(rule.index) }
            }
        }
        return (hide, keep)
    }

    /// Finds the nodes an absolute pattern selects. The tree root's own path components must match the pattern's prefix.
    private static func resolve(_ globs: [Glob], tree: FileTree) -> [NodeID] {
        let rootParts = tree.name(0).split(separator: "/", omittingEmptySubsequences: true)
        guard globs.count > rootParts.count else { return [] }
        for (glob, part) in zip(globs, rootParts) {
            var part = String(part)
            let matched = part.withUTF8 { glob.matches($0) }
            if !matched { return [] }
        }
        var frontier: [NodeID] = [0]
        for glob in globs.dropFirst(rootParts.count) {
            var next: [NodeID] = []
            for node in frontier {
                for child in tree.children(node) where tree.withName(child, { glob.matches($0) }) { next.append(child) }
            }
            frontier = next
            if frontier.isEmpty { break }
        }
        return frontier
    }
}
