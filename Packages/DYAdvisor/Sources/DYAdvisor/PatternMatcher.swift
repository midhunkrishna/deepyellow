import DYCore
import Foundation

/// One segment of a compiled pattern.
enum PatternSegment {
    case name(String)
    case anyDepth
}

/// A rule pattern parsed into segments, ready to match against a tree.
struct CompiledPattern {
    let segments: [PatternSegment]
    /// The segments as written, for looking up literal paths with their exact case.
    let rawSegments: [String]
    /// True for `**/...` patterns, which match anywhere rather than from a fixed start.
    let floating: Bool
    /// Absolute path of the fixed start for anchored patterns.
    let anchorPath: String
    let siblings: [String]
    /// More literal characters means more specific.
    let specificity: Int
    /// The last segment, used to stop a floating rule restarting inside its own match.
    let leaf: String

    /// Parses `pattern`, expanding `~` with `home`. Returns nil for a pattern that can't be anchored.
    init?(pattern: String, home: String) {
        var path = pattern
        var siblings: [String] = []
        if let range = pattern.range(of: " if-sibling:") {
            path = String(pattern[..<range.lowerBound])
            siblings = pattern[range.upperBound...].split(separator: "|").map { $0.lowercased() }
        }
        var parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        var anchor = ""
        var floating = false
        if path.hasPrefix("**/") {
            floating = true
            parts.removeFirst()
        } else if path.hasPrefix("~") {
            anchor = home
            parts.removeFirst()
        } else if !path.hasPrefix("/") {
            return nil
        }
        guard !parts.isEmpty, parts.last != "**" else { return nil }
        self.rawSegments = parts
        self.segments = parts.map { $0 == "**" ? .anyDepth : .name($0.lowercased()) }
        self.floating = floating
        self.anchorPath = anchor
        self.siblings = siblings
        self.leaf = parts.last!.lowercased()
        let literals = parts.reduce(0) { $0 + ($1 == "**" ? 0 : $1.filter { $0 != "*" }.count) }
        self.specificity = literals * 4 + (siblings.isEmpty ? 0 : 1)
    }

    /// The literal leading path that can be looked up directly, and the remaining segments to expand.
    var literalPrefix: (path: String, rest: ArraySlice<PatternSegment>) {
        var path = anchorPath
        var index = 0
        while index < segments.count, case .name(let spec) = segments[index], PatternMatcher.isLiteral(spec) {
            path += "/" + rawSegments[index]
            index += 1
        }
        return (path.isEmpty ? "/" : path, segments[index...])
    }
}

/// Wildcard matching of names and sibling checks, shared by the rule engine.
enum PatternMatcher {
    /// Whether a segment spec contains no wildcard, alternative or exclusion syntax.
    static func isLiteral(_ spec: String) -> Bool {
        !spec.contains("*") && !spec.contains("|") && !spec.contains("&!")
    }

    /// Whether `name` satisfies a segment spec such as `*.dmg|*.pkg` or `*.sqlite&!*cache*`. Case-insensitive.
    static func matches(spec: String, name: String) -> Bool {
        let lowered = Array(name.lowercased().utf8)
        for alternative in spec.split(separator: "|") {
            let parts = alternative.components(separatedBy: "&!")
            guard glob(Array(parts[0].utf8), lowered) else { continue }
            if !parts.dropFirst().contains(where: { glob(Array($0.utf8), lowered) }) { return true }
        }
        return false
    }

    /// Glob match where `*` matches any run of bytes.
    static func glob(_ pattern: [UInt8], _ text: [UInt8]) -> Bool {
        var p = 0, t = 0, star = -1, mark = 0
        while t < text.count {
            if p < pattern.count, pattern[p] == UInt8(ascii: "*") {
                star = p; mark = t; p += 1
            } else if p < pattern.count, pattern[p] == text[t] {
                p += 1; t += 1
            } else if star >= 0 {
                p = star + 1; mark += 1; t = mark
            } else {
                return false
            }
        }
        while p < pattern.count, pattern[p] == UInt8(ascii: "*") { p += 1 }
        return p == pattern.count
    }

    /// Finds every node in `lens` that an anchored pattern selects.
    static func anchoredMatches(_ pattern: CompiledPattern, lens: TreeLens) -> [NodeID] {
        let tree = lens.tree
        let (prefix, rest) = pattern.literalPrefix
        guard let start = tree.find(path: prefix), lens.included[Int(start)] else { return [] }
        var found: [NodeID] = []
        expand(node: start, segments: Array(rest), index: 0, lens: lens, into: &found)
        return found.filter { siblingsSatisfied(pattern.siblings, node: $0, tree: tree) }
    }

    /// Whether the floating pattern ends at `node`: the name and any preceding folders match.
    static func floatingMatches(_ pattern: CompiledPattern, node: NodeID, tree: FileTree) -> Bool {
        var current = node
        for segment in pattern.segments.reversed() {
            guard current > 0, case .name(let spec) = segment, matches(spec: spec, name: tree.name(current)) else { return false }
            current = tree.parent(current)
        }
        return siblingsSatisfied(pattern.siblings, node: node, tree: tree)
    }

    /// Whether the node has a sibling with one of the required names (or none are required).
    static func siblingsSatisfied(_ names: [String], node: NodeID, tree: FileTree) -> Bool {
        guard !names.isEmpty else { return true }
        guard node > 0 else { return false }
        return tree.children(tree.parent(node)).contains { sibling in
            sibling != node && names.contains(tree.name(sibling).lowercased())
        }
    }

    /// Walks the tree matching `segments` from `index`, collecting nodes where all segments are consumed.
    private static func expand(node: NodeID, segments: [PatternSegment], index: Int, lens: TreeLens, into found: inout [NodeID]) {
        if index == segments.count { found.append(node); return }
        let tree = lens.tree
        switch segments[index] {
        case .anyDepth:
            expand(node: node, segments: segments, index: index + 1, lens: lens, into: &found)
            for child in tree.children(node) where lens.included[Int(child)] && tree.isDirectory(child) {
                expand(node: child, segments: segments, index: index, lens: lens, into: &found)
            }
        case .name(let spec):
            for child in tree.children(node) where lens.included[Int(child)] && matches(spec: spec, name: tree.name(child)) {
                expand(node: child, segments: segments, index: index + 1, lens: lens, into: &found)
            }
        }
    }
}
