import DYCore
import Foundation

/// Evaluates a `Query` over every node of a tree.
public enum QueryEngine {
    /// For each node, whether it passes the query. Only leaves are set; directories with children are false, because
    /// `TreeLens` consults leaves only. Path-like terms and `is:dir` / `is:package` also match everything beneath a
    /// matching directory. Returns nil if cancelled.
    public static func matches(_ query: Query, tree: FileTree, context: QueryContext, isCancelled: () -> Bool) -> [Bool]? {
        let count = tree.count
        var result = [Bool](repeating: false, count: count)
        guard count > 0 else { return result }
        let terms = query.terms.sorted { cost($0.test) < cost($1.test) }
        let inheriting = terms.indices.filter { isInheriting(terms[$0].test) }
        var bitOf = [Int](repeating: -1, count: terms.count)
        for (bit, term) in inheriting.enumerated() { bitOf[term] = bit }
        var masks = [UInt32](repeating: 0, count: inheriting.isEmpty ? 0 : count)
        let columns = tree.columns

        let cancelled: Bool = NameReader.with(tree) { names in
            for index in 0..<count {
                if index & 0xFFFF == 0, isCancelled() { return true }
                let parentMask: UInt32 = index > 0 && !masks.isEmpty ? masks[Int(columns.parent[index])] : 0
                if columns.childCount[index] > 0 {
                    guard !inheriting.isEmpty else { continue }
                    var mask = parentMask
                    for term in inheriting where mask & (1 << UInt32(bitOf[term])) == 0 {
                        if ownTest(terms[term].test, node: index, names: names, tree: tree, columns: columns, context: context) { mask |= 1 << UInt32(bitOf[term]) }
                    }
                    masks[index] = mask
                    continue
                }
                var passes = true
                for position in terms.indices {
                    let bit = bitOf[position]
                    let value = bit >= 0 && parentMask & (1 << UInt32(bit)) != 0
                        || ownTest(terms[position].test, node: index, names: names, tree: tree, columns: columns, context: context)
                    if value == terms[position].negated { passes = false; break }
                }
                result[index] = passes
            }
            return false
        }
        if cancelled { return nil }
        return result
    }

    /// Whether a term's truth carries down from a directory to its contents.
    private static func isInheriting(_ test: Query.Test) -> Bool {
        switch test {
        case .path, .flag(.directory), .flag(.package): true
        default: false
        }
    }

    /// Rough evaluation cost, so cheap terms run first.
    private static func cost(_ test: Query.Test) -> Int {
        switch test {
        case .size, .age, .opened, .kind, .mark, .safe, .flag: 0
        case .ext, .name: 1
        case .path: 2
        case .pathSlash: 3
        }
    }

    /// Evaluates a term against one node alone, ignoring ancestors.
    private static func ownTest(_ test: Query.Test, node: Int, names: NameReader, tree: FileTree, columns: FileTreeColumns, context: QueryContext) -> Bool {
        switch test {
        case .size(let comparison, let limit):
            return comparison == .greater ? columns.allocated[node] > limit : columns.allocated[node] < limit
        case .age(let comparison, let seconds):
            return compare(Int64(context.now) - Int64(columns.modified[node]), comparison, seconds)
        case .opened(let comparison, let seconds):
            return compare(Int64(context.now) - Int64(columns.accessed[node]), comparison, seconds)
        case .kind(let kinds):
            return kinds.contains(columns.kind[node])
        case .ext(let list):
            return { (name: UnsafeBufferPointer<UInt8>) in
                guard let dot = name.lastIndex(of: 46), dot > 0, dot < name.count - 1 else { return false }
                let suffix = UnsafeBufferPointer(rebasing: name[(dot + 1)...])
                return list.contains { equalsIgnoringCase(suffix, $0) }
            }(names.name(node))
        case .name(let needle):
            return contains(names.name(node), needle)
        case .path(let needle):
            return contains(names.name(node), needle)
        case .pathSlash(let needle):
            return Array(tree.path(NodeID(node)).lowercased().utf8).withUnsafeBufferPointer { contains($0, needle) }
        case .flag(let flag):
            let flags = columns.flags[node]
            switch flag {
            case .directory: return flags & NodeFlags.directory.rawValue != 0
            case .package: return flags & NodeFlags.package.rawValue != 0
            case .clone: return flags & (NodeFlags.cloneDuplicate.rawValue | NodeFlags.mayShareBlocks.rawValue) != 0
            case .hardlink: return flags & NodeFlags.hardlinkDuplicate.rawValue != 0
            case .dataless: return flags & NodeFlags.dataless.rawValue != 0
            }
        case .mark(let mark):
            return (context.decisions.isEmpty ? 0 : context.decisions[node]) == mark
        case .safe(let tier):
            return (context.safety.isEmpty ? 0 : context.safety[node]) == tier
        }
    }

    /// Compares an age in seconds with a limit.
    @inline(__always) private static func compare(_ age: Int64, _ comparison: Query.Comparison, _ limit: Int64) -> Bool {
        comparison == .greater ? age > limit : age < limit
    }

    /// Whether `haystack` equals `lowerNeedle` ignoring ASCII case.
    private static func equalsIgnoringCase(_ haystack: UnsafeBufferPointer<UInt8>, _ lowerNeedle: [UInt8]) -> Bool {
        guard haystack.count == lowerNeedle.count else { return false }
        for index in 0..<haystack.count where Glob.lower(haystack[index]) != lowerNeedle[index] { return false }
        return true
    }

    /// Whether `haystack` contains `lowerNeedle`, ignoring ASCII case, without allocating.
    private static func contains(_ haystack: UnsafeBufferPointer<UInt8>, _ lowerNeedle: [UInt8]) -> Bool {
        let length = lowerNeedle.count
        if length == 0 { return true }
        guard haystack.count >= length else { return false }
        let first = lowerNeedle[0]
        var start = 0
        let last = haystack.count - length
        while start <= last {
            if Glob.lower(haystack[start]) == first {
                var offset = 1
                while offset < length, Glob.lower(haystack[start + offset]) == lowerNeedle[offset] { offset += 1 }
                if offset == length { return true }
            }
            start += 1
        }
        return false
    }
}
