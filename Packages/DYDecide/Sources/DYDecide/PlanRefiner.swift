import DYCore
import Foundation

/// Measures how many bytes deleting a path would free right now. A seam so tests never touch real files.
public protocol ReclaimProbing: Sendable {
    /// The bytes that removing everything at `path` would free, or nil when they can't be measured.
    func privateBytes(path: String) -> UInt64?
}

extension RemovalPlanner {
    /// Replaces each item's scan-time figure with a measured one.
    ///
    /// A probed item takes the measured bytes (at most its allocated size) and is a floor only when blocks are shared,
    /// since the other holders may also go. Where the probe fails the item keeps its figure and is not called a floor,
    /// so "frees at least" is only stated for figures that were checked. Returns `plan` unchanged if cancelled.
    public static func refine(_ plan: RemovalPlan, probe: ReclaimProbing, isCancelled: @Sendable () -> Bool) async -> RemovalPlan {
        var items = plan.items
        for index in items.indices {
            if isCancelled() { return plan }
            await Task.yield()
            let path = items[index].id
            if let measured = probe.privateBytes(path: path) {
                items[index].reclaimable = min(measured, items[index].bytes)
                items[index].reclaimIsLowerBound = items[index].reclaimable < items[index].bytes
            } else {
                items[index].reclaimIsLowerBound = false
            }
        }
        var refined = plan
        refined.items = items
        refined.totalReclaimable = items.reduce(0) { $0 &+ $1.reclaimable }
        refined.estimateIsLowerBound = items.contains { $0.reclaimIsLowerBound }
        return refined
    }
}
