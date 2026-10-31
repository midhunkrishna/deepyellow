import Foundation
import DYCore

/// One thing a plan would move to the Trash.
public struct PlanItem: Identifiable, Sendable {
    /// The item's absolute path.
    public var id: String
    public var node: NodeID
    /// Bytes on disk the item occupies.
    public var bytes: UInt64
    /// Bytes that moving it frees once the Trash is emptied. At most `bytes`.
    public var reclaimable: UInt64
    /// What the item looked like at scan time. The executor compares this with the disk just before moving.
    public var fingerprint: Fingerprint
    /// True when blocks may be shared with a clone or snapshot, so `reclaimable` is a floor.
    public var reclaimIsLowerBound: Bool

    /// Creates a plan item.
    public init(id: String, node: NodeID, bytes: UInt64, reclaimable: UInt64, fingerprint: Fingerprint,
                reclaimIsLowerBound: Bool) {
        self.id = id
        self.node = node
        self.bytes = bytes
        self.reclaimable = reclaimable
        self.fingerprint = fingerprint
        self.reclaimIsLowerBound = reclaimIsLowerBound
    }
}

/// A path the user asked to remove that the planner refused, and why.
public struct BlockedItem: Sendable, Equatable {
    public var path: String
    public var reason: String

    /// Creates a blocked entry.
    public init(path: String, reason: String) {
        self.path = path
        self.reason = reason
    }
}

/// The exact list of roots to move to the Trash, what is kept inside them, and what was refused.
public struct RemovalPlan: Sendable {
    /// Minimal roots: never a parent together with its child.
    public var items: [PlanItem]
    /// Keep or later paths that sit inside a split directory and stay where they are.
    public var protected: [String]
    public var blocked: [BlockedItem]
    public var totalBytes: UInt64
    public var totalReclaimable: UInt64
    /// True when at least one item's figure is a floor, so the total may be stated only as "frees at least".
    public var estimateIsLowerBound: Bool

    /// Creates a plan. Totals default to the sums over `items`, and the lower-bound flag to whether any item is a floor.
    public init(items: [PlanItem] = [], protected: [String] = [], blocked: [BlockedItem] = [],
                totalBytes: UInt64? = nil, totalReclaimable: UInt64? = nil, estimateIsLowerBound: Bool? = nil) {
        self.items = items
        self.protected = protected
        self.blocked = blocked
        self.totalBytes = totalBytes ?? items.reduce(0) { $0 &+ $1.bytes }
        self.totalReclaimable = totalReclaimable ?? items.reduce(0) { $0 &+ $1.reclaimable }
        self.estimateIsLowerBound = estimateIsLowerBound ?? items.contains { $0.reclaimIsLowerBound }
    }
}
