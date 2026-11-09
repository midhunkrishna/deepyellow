import DYCore
import Foundation

/// Why a rule file was refused, naming the file, the rule and the problem.
public struct RulesError: Error, CustomStringConvertible, Equatable {
    /// The file name, or nil when the problem is not tied to one file.
    public let file: String?
    /// The rule id, or nil when the problem is with the file or folder as a whole.
    public let ruleID: String?
    public let problem: String

    /// Creates an error.
    public init(file: String? = nil, ruleID: String? = nil, problem: String) {
        self.file = file
        self.ruleID = ruleID
        self.problem = problem
    }

    /// A readable message of the form `file: rule-id: problem`, leaving out the parts that are nil.
    public var description: String { [file, ruleID, problem].compactMap { $0 }.joined(separator: ": ") }
}

/// One section of the rule book, in file order.
public struct RuleSection: Equatable {
    public let title: String
    public let intro: String
    public let rules: [ReclaimRule]

    /// Creates a section.
    public init(title: String, intro: String, rules: [ReclaimRule]) {
        self.title = title
        self.intro = intro
        self.rules = rules
    }
}

/// Reads the reclaim rules from the JSON files in the `rules` folder.
public enum RuleFiles {
    /// Decodes and validates one rule file; throws `RulesError` naming the file, rule id and problem.
    public static func decode(_ data: Data, file: String, home: String) throws -> RuleSection {
        let parsed: RuleFileJSON
        do {
            parsed = try JSONDecoder().decode(RuleFileJSON.self, from: data)
        } catch {
            throw RulesError(file: file, problem: "not valid rules JSON: \(error)")
        }
        guard parsed.version == 1 else { throw RulesError(file: file, problem: "unsupported version \(parsed.version)") }
        guard let section = parsed.section, filled(section.title), filled(section.intro) else {
            throw RulesError(file: file, problem: "section title or intro is missing or empty")
        }
        var seen = Set<String>()
        let rules = try parsed.rules.map { entry in
            try validate(entry, file: file, home: home)
            guard seen.insert(entry.id).inserted else { throw RulesError(file: file, ruleID: entry.id, problem: "duplicate id") }
            return makeRule(entry)
        }
        return RuleSection(title: section.title ?? "", intro: section.intro ?? "", rules: rules)
    }

    /// Loads every *.json in the folder in file-name order; also refuses duplicate ids across files and an empty folder.
    public static func load(directory: URL, home: String) throws -> [RuleSection] {
        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".json") }.sorted()
        } catch {
            throw RulesError(problem: "cannot read the rules folder \(directory.path): \(error.localizedDescription)")
        }
        guard !names.isEmpty else { throw RulesError(problem: "no rule files in \(directory.path)") }
        var owner: [String: String] = [:]
        return try names.map { name in
            let data: Data
            do {
                data = try Data(contentsOf: directory.appendingPathComponent(name))
            } catch {
                throw RulesError(file: name, problem: "cannot read the file: \(error.localizedDescription)")
            }
            let section = try decode(data, file: name, home: home)
            for rule in section.rules {
                if let first = owner[rule.id] {
                    throw RulesError(file: name, ruleID: rule.id, problem: "duplicate id, also in \(first)")
                }
                owner[rule.id] = name
            }
            return section
        }
    }

    /// The folder the app reads: $DEEPYELLOW_RULES if set, else Bundle.main.resourceURL/rules; in DEBUG builds only,
    /// falls back to the repo's rules/ (found from #filePath) when the bundle has none.
    public static func defaultDirectory(filePath: String = #filePath) -> URL {
        if let override = ProcessInfo.processInfo.environment["DEEPYELLOW_RULES"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let bundled = (Bundle.main.resourceURL ?? URL(fileURLWithPath: "/nonexistent")).appendingPathComponent("rules", isDirectory: true)
        #if DEBUG
        if !FileManager.default.fileExists(atPath: bundled.path) {
            var url = URL(fileURLWithPath: filePath)
            for _ in 0..<5 { url.deleteLastPathComponent() }
            return url.appendingPathComponent("rules", isDirectory: true)
        }
        #endif
        return bundled
    }

    private struct RuleFileJSON: Decodable {
        let version: Int
        let section: Section?
        let rules: [Entry]
    }

    private struct Section: Decodable {
        let title: String?
        let intro: String?
    }

    private struct Evidence: Decodable {
        let method: String?
        let appVersion: String?
        let macOSVersion: String?
        let measuredOn: String?
        let observed: String?
    }

    private struct Entry: Decodable {
        let id: String
        let title: String?
        let pattern: String?
        let tier: String?
        let whatItIs: String?
        let consequence: String?
        let sideCondition: String?
        let cleanupCommand: String?
        let ownerBundleIDs: [String]?
        let source: String?
        let evidence: Evidence?
    }

    private static let methods: Set<String> = ["relaunch-test", "vendor-doc", "location", "research"]
    private static let tiers: [String: SafetyTier] = ["safe": .safe, "rebuild": .rebuild, "review": .review, "never": .never]

    /// True when the text holds something other than whitespace.
    private static func filled(_ text: String?) -> Bool {
        text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    /// Checks one entry against every validation rule, throwing on the first problem.
    private static func validate(_ entry: Entry, file: String, home: String) throws {
        func fail(_ problem: String) -> RulesError { RulesError(file: file, ruleID: entry.id, problem: problem) }
        guard filled(entry.id) else { throw fail("id is empty") }
        let required: [(String, String?)] = [("title", entry.title), ("pattern", entry.pattern), ("tier", entry.tier),
                                             ("whatItIs", entry.whatItIs), ("consequence", entry.consequence)]
        for (name, value) in required where !filled(value) { throw fail("\(name) is missing or empty") }
        if let source = entry.source, !filled(source) { throw fail("source is empty (use null for none)") }
        guard let owners = entry.ownerBundleIDs, owners.allSatisfy(filled) else {
            throw fail("ownerBundleIDs is missing or has an empty entry")
        }
        guard let tier = tiers[entry.tier ?? ""] else { throw fail("unknown tier '\(entry.tier ?? "")'") }
        for part in (entry.pattern ?? "").components(separatedBy: " || ") where CompiledPattern(pattern: part, home: home) == nil {
            throw fail("pattern does not compile: '\(part)'")
        }
        try validateEvidence(entry.evidence, tier: tier, fail: fail)
    }

    /// Checks the evidence block: a known method, the measurement fields for relaunch tests, and a strong enough method for the tier.
    private static func validateEvidence(_ evidence: Evidence?, tier: SafetyTier, fail: (String) -> RulesError) throws {
        guard let evidence else { throw fail("evidence is missing") }
        guard filled(evidence.method) else { throw fail("evidence.method is missing or empty") }
        let method = evidence.method ?? ""
        guard methods.contains(method) else { throw fail("unknown evidence.method '\(method)'") }
        if method == "relaunch-test" {
            let fields: [(String, String?)] = [("appVersion", evidence.appVersion), ("macOSVersion", evidence.macOSVersion),
                                               ("measuredOn", evidence.measuredOn), ("observed", evidence.observed)]
            for (name, value) in fields where !filled(value) { throw fail("evidence.\(name) is missing or empty") }
        }
        if (tier == .safe || tier == .rebuild) && method == "location" {
            throw fail("\(tier == .safe ? "safe" : "rebuild") rules need evidence.method relaunch-test, vendor-doc or research")
        }
    }

    /// Builds the `ReclaimRule` for an entry that passed validation.
    private static func makeRule(_ e: Entry) -> ReclaimRule {
        ReclaimRule(id: e.id, title: e.title ?? "", pattern: e.pattern ?? "", tier: tiers[e.tier ?? ""] ?? .review,
                    whatItIs: e.whatItIs ?? "", consequence: e.consequence ?? "",
                    sideCondition: filled(e.sideCondition) ? e.sideCondition : nil,
                    cleanupCommand: filled(e.cleanupCommand) ? e.cleanupCommand : nil,
                    ownerBundleIDs: e.ownerBundleIDs ?? [], source: e.source)
    }
}
