import Foundation

/// A case-insensitive (ASCII) wildcard pattern over one path component. `*` matches any run, `?` any single byte.
struct Glob: Sendable {
    /// The pattern bytes, lowercased.
    let bytes: [UInt8]
    /// Whether the pattern contains `*` or `?`.
    let hasWildcard: Bool

    /// Compiles a component pattern.
    init(_ text: String) {
        bytes = Array(text.utf8).map(Glob.lower)
        hasWildcard = bytes.contains(42) || bytes.contains(63)
    }

    /// The first pattern byte, or nil when the pattern is empty or starts with a wildcard.
    var literalFirstByte: UInt8? {
        guard let first = bytes.first, first != 42, first != 63 else { return nil }
        return first
    }

    /// ASCII lowercase of one byte.
    @inline(__always) static func lower(_ byte: UInt8) -> UInt8 { byte >= 65 && byte <= 90 ? byte | 0x20 : byte }

    /// Whether the pattern matches the whole of `name`, without allocating.
    func matches(_ name: UnsafeBufferPointer<UInt8>) -> Bool {
        if !hasWildcard {
            guard name.count == bytes.count else { return false }
            for index in 0..<name.count where Glob.lower(name[index]) != bytes[index] { return false }
            return true
        }
        var p = 0, n = 0, star = -1, mark = 0
        while n < name.count {
            if p < bytes.count, bytes[p] == 42 {
                star = p; mark = n; p += 1
            } else if p < bytes.count, bytes[p] == 63 || bytes[p] == Glob.lower(name[n]) {
                p += 1; n += 1
            } else if star >= 0 {
                p = star + 1; mark += 1; n = mark
            } else {
                return false
            }
        }
        while p < bytes.count, bytes[p] == 42 { p += 1 }
        return p == bytes.count
    }
}
