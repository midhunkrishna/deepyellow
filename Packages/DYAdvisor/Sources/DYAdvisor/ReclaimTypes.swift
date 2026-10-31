import DYCore
import Foundation

/// One piece of advice about a place on disk: what it is, how safe it is to remove and what removal costs.
///
/// `pattern` grammar (case-insensitive, `*` matches any run of characters inside one path segment):
/// - `~/...` is relative to the home folder; `/...` is absolute.
/// - `**` as a middle segment matches zero or more folders.
/// - `**/name` at the start matches `name` anywhere in the tree (`**/.yarn/cache` matches a path suffix).
/// - A segment may list alternatives with `|` and exclusions with `&!`, for example `*.sqlite&!*cache*`.
/// - Several full paths may be joined with ` || `.
/// - A trailing ` if-sibling:a|b` only matches when the node has a sibling named `a` or `b`.
public struct ReclaimRule: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let pattern: String
    public let tier: SafetyTier
    /// One plain-words sentence on what the item is.
    public let whatItIs: String
    /// One plain-words sentence on what the user loses or waits for if it is removed.
    public let consequence: String
    /// Conditions to show the user, such as "Quit Xcode first".
    public let sideCondition: String?
    /// A command to display. This module never runs it.
    public let cleanupCommand: String?
    public let ownerBundleIDs: [String]
    /// Where the claim comes from, as recorded in the research notes.
    public let source: String?

    /// Creates a rule.
    public init(id: String, title: String, pattern: String, tier: SafetyTier, whatItIs: String, consequence: String,
                sideCondition: String? = nil, cleanupCommand: String? = nil, ownerBundleIDs: [String] = [],
                source: String? = nil) {
        self.id = id
        self.title = title
        self.pattern = pattern
        self.tier = tier
        self.whatItIs = whatItIs
        self.consequence = consequence
        self.sideCondition = sideCondition
        self.cleanupCommand = cleanupCommand
        self.ownerBundleIDs = ownerBundleIDs
        self.source = source
    }
}

/// All places in a scan that one rule applies to, with their combined size.
public struct ReclaimFamily: Identifiable, Sendable {
    public var id: String { rule.id }
    public let rule: ReclaimRule
    /// The nodes the rule matched directly. Everything beneath them inherits the rule.
    public let nodes: [NodeID]
    /// Bytes on disk under the matched nodes, excluding parts claimed by a more specific rule.
    public let bytes: UInt64
    /// Bytes that deleting would free right away. Zero for tiers that are never offered.
    public let reclaimable: UInt64
    public let files: UInt64
    /// Most recent modification time beneath the matched nodes, in seconds since 1970.
    public let newestModified: Int32

    /// Creates a family.
    public init(rule: ReclaimRule, nodes: [NodeID], bytes: UInt64, reclaimable: UInt64, files: UInt64, newestModified: Int32) {
        self.rule = rule
        self.nodes = nodes
        self.bytes = bytes
        self.reclaimable = reclaimable
        self.files = files
        self.newestModified = newestModified
    }
}

/// The result of matching rules against a scan.
public struct ReclaimReport: Sendable {
    /// Ordered by tier (safe first, never last), then by bytes descending.
    public let families: [ReclaimFamily]
    /// `SafetyTier` raw value per node, with inheritance resolved. Has `tree.count` elements.
    public let nodeTier: [UInt8]
    let nodeRule: [Int32]
    let rules: [ReclaimRule]

    /// Creates a report from resolved per-node results.
    init(families: [ReclaimFamily], nodeTier: [UInt8], nodeRule: [Int32], rules: [ReclaimRule]) {
        self.families = families
        self.nodeTier = nodeTier
        self.nodeRule = nodeRule
        self.rules = rules
    }

    /// The rule that governs a node, or nil when none applies (or the node is protected without a rule).
    public func rule(for id: NodeID, tree: FileTree) -> ReclaimRule? {
        guard id >= 0, Int(id) < nodeRule.count else { return nil }
        let index = nodeRule[Int(id)]
        return index >= 0 ? rules[Int(index)] : nil
    }
}
