import DYCore
import Foundation

/// A parsed query: terms joined by AND. See `Query.parse` for the grammar.
public struct Query: Sendable, Equatable {
    /// How a numeric term compares.
    enum Comparison: Sendable, Equatable { case greater, less }

    /// Node properties tested by `is:`.
    enum Flag: Sendable, Equatable { case directory, clone, hardlink, package, dataless }

    /// One test on a node.
    enum Test: Sendable, Equatable {
        case size(Comparison, UInt64)
        case age(Comparison, Int64)
        case opened(Comparison, Int64)
        case kind(Set<UInt8>)
        case ext([[UInt8]])
        case name([UInt8])
        /// Lowercase needle without `/`, matched against the node's name or any ancestor's name.
        case path([UInt8])
        /// Lowercase needle containing `/`, matched against the full path of leaves.
        case pathSlash([UInt8])
        case flag(Flag)
        case mark(UInt8)
        case safe(UInt8)
    }

    /// A test, possibly negated.
    struct Term: Sendable, Equatable {
        var negated: Bool
        var test: Test
    }

    /// The most terms honoured; further terms are reported in `errors`.
    static let maxTerms = 24

    /// The text the query was parsed from.
    public private(set) var text: String
    /// Descriptions of terms that could not be understood. They are ignored when matching.
    public private(set) var errors: [String]
    var terms: [Term]

    /// True when there is nothing to filter on.
    public var isEmpty: Bool { terms.isEmpty }

    /// Parses `size> size<`, `age> age<` (modified), `opened> opened<` (accessed), `kind:`, `ext:a,b`, `name:`, `path:`,
    /// `is:dir|clone|hardlink|package|dataless`, `mark:keep|remove|later|none`, `safe:safe|rebuild|review|never`
    /// and bare words (name or path). `-` negates a term. Never fails: malformed terms go in `errors`.
    public static func parse(_ text: String) -> Query {
        var query = Query(text: text, errors: [], terms: [])
        for token in tokenize(text) {
            var word = token
            var negated = false
            if word.hasPrefix("-"), word.count > 1 { negated = true; word.removeFirst() }
            do {
                let test = try parseTest(word)
                if query.terms.count >= maxTerms {
                    query.errors.append("too many terms: \(token)")
                } else {
                    query.terms.append(Term(negated: negated, test: test))
                }
            } catch let error as ParseError {
                query.errors.append(error.message + ": " + token)
            } catch {
                query.errors.append("invalid term: " + token)
            }
        }
        return query
    }

    private struct ParseError: Error { let message: String }

    /// Splits on whitespace, keeping double-quoted runs together.
    private static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quoted = false
        for character in text {
            if character == "\"" { quoted.toggle(); continue }
            if character.isWhitespace, !quoted {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    /// Parses one non-negated term into a test.
    private static func parseTest(_ word: String) throws -> Test {
        for (prefix, build) in comparisonPrefixes {
            if word.hasPrefix(prefix) {
                return try build(String(word.dropFirst(prefix.count)))
            }
        }
        if let colon = word.firstIndex(of: ":") {
            let key = word[..<colon].lowercased()
            let value = String(word[word.index(after: colon)...])
            if key.allSatisfy(\.isLetter) {
                return try parseKeyed(key: key, value: value)
            }
        }
        return needle(word)
    }

    /// The `key>` and `key<` forms.
    private static let comparisonPrefixes: [(String, (String) throws -> Test)] = [
        ("size>", { .size(.greater, try parseSize($0)) }), ("size<", { .size(.less, try parseSize($0)) }),
        ("age>", { .age(.greater, try parseDuration($0)) }), ("age<", { .age(.less, try parseDuration($0)) }),
        ("opened>", { .opened(.greater, try parseDuration($0)) }), ("opened<", { .opened(.less, try parseDuration($0)) }),
    ]

    /// The `key:value` forms.
    private static func parseKeyed(key: String, value: String) throws -> Test {
        guard !value.isEmpty else { throw ParseError(message: "missing value") }
        let lowered = value.lowercased()
        switch key {
        case "kind":
            var kinds = Set<UInt8>()
            for part in lowered.split(separator: ",") {
                guard let kind = FileKind.allCases.first(where: { kindNames($0).contains(String(part)) }) else {
                    throw ParseError(message: "unknown kind")
                }
                kinds.insert(kind.rawValue)
            }
            return .kind(kinds)
        case "ext":
            let list = lowered.split(separator: ",").map { Array(String($0).trimmingPrefix(".").utf8) }
            guard !list.isEmpty else { throw ParseError(message: "missing value") }
            return .ext(list)
        case "name": return .name(Array(lowered.utf8))
        case "path": return needle(value)
        case "is":
            let flags: [String: Flag] = ["dir": .directory, "clone": .clone, "hardlink": .hardlink, "package": .package, "dataless": .dataless]
            guard let flag = flags[lowered] else { throw ParseError(message: "unknown property") }
            return .flag(flag)
        case "mark":
            let marks: [String: Decision] = ["keep": .keep, "remove": .remove, "later": .later, "none": .none]
            guard let mark = marks[lowered] else { throw ParseError(message: "unknown mark") }
            return .mark(mark.rawValue)
        case "safe":
            let tiers: [String: SafetyTier] = ["safe": .safe, "rebuild": .rebuild, "review": .review, "never": .never]
            guard let tier = tiers[lowered] else { throw ParseError(message: "unknown safety") }
            return .safe(tier.rawValue)
        default:
            throw ParseError(message: "unknown term")
        }
    }

    /// Names accepted for a kind in `kind:`.
    private static func kindNames(_ kind: FileKind) -> [String] {
        switch kind {
        case .video: ["video", "videos"]
        case .image: ["image", "images"]
        case .audio: ["audio"]
        case .document: ["document", "documents", "doc", "docs"]
        case .code: ["code", "data"]
        case .application: ["application", "applications", "app", "apps", "library", "libraries"]
        case .archive: ["archive", "archives", "disk", "disks"]
        case .other: ["other"]
        }
    }

    /// A path or bare-word needle.
    private static func needle(_ word: String) -> Test {
        let bytes = Array(word.lowercased().utf8)
        return bytes.contains(47) ? .pathSlash(bytes) : .path(bytes)
    }

    /// Splits `1.5gb` into a number and a lowercase unit.
    private static func splitNumber(_ text: String) throws -> (Double, String) {
        let digits = text.prefix { $0.isNumber || $0 == "." }
        guard let number = Double(digits), number >= 0 else { throw ParseError(message: "bad number") }
        return (number, text.dropFirst(digits.count).lowercased())
    }

    /// Parses a decimal size such as `100mb`. A bare number is bytes.
    static func parseSize(_ text: String) throws -> UInt64 {
        let (number, unit) = try splitNumber(text)
        let units: [String: Double] = ["": 1, "b": 1, "kb": 1e3, "mb": 1e6, "gb": 1e9, "tb": 1e12]
        guard let scale = units[unit] else { throw ParseError(message: "bad size unit") }
        return UInt64(min(number * scale, 1.8e19))
    }

    /// Parses a duration such as `1y` into seconds. A bare number is days; `m` is a 30-day month.
    static func parseDuration(_ text: String) throws -> Int64 {
        let (number, unit) = try splitNumber(text)
        let units: [String: Double] = ["": 86_400, "s": 1, "h": 3_600, "d": 86_400, "w": 604_800, "m": 2_592_000, "y": 31_536_000]
        guard let scale = units[unit] else { throw ParseError(message: "bad time unit") }
        return Int64(min(number * scale, 1e12))
    }
}

/// Per-node state the query needs beyond the tree.
public struct QueryContext: Sendable {
    /// Effective decision raw values per node, or empty for none.
    public var decisions: [UInt8]
    /// `SafetyTier` raw values per node, or empty for none.
    public var safety: [UInt8]
    /// Reference time for `age` and `opened`, in seconds since 1970.
    public var now: Int32

    /// Creates a context.
    public init(decisions: [UInt8] = [], safety: [UInt8] = [], now: Int32 = Int32(Date().timeIntervalSince1970)) {
        self.decisions = decisions
        self.safety = safety
        self.now = now
    }
}
