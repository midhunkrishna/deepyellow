import DYCore
import Foundation

/// Which timestamp places a file on the age axis.
public enum FieldClock: Sendable { case modified, accessed }

/// Points for the age-against-size scatter.
public struct FieldData: Sendable {
    /// `x`: log10 of age in days, `y`: log10 of bytes.
    public var positions: [SIMD2<Float>]
    /// `FileKind` raw value per point.
    public var kinds: [UInt8]
    public var nodes: [NodeID]
    public var ageRange: ClosedRange<Float>
    public var sizeRange: ClosedRange<Float>
}

/// Computes scatter data.
public enum FieldEngine {
    /// The youngest age plotted, in days, so brand-new files stay on the log axis.
    private static let minimumAgeDays = 0.1

    /// Plots the visible non-empty files beneath `under`. Keeps every file when there are at most `maxPoints`;
    /// otherwise keeps the largest files and a deterministic sample of the rest.
    public static func compute(lens: TreeLens, under: NodeID, clock: FieldClock, maxPoints: Int) -> FieldData {
        let inside = Subtree.membership(of: under, in: lens.tree)
        var candidates: [Int] = []
        for index in Int(max(under, 0))..<lens.tree.count where inside[index] && lens.size[index] > 0 && Subtree.isVisibleFile(index, lens: lens) {
            candidates.append(index)
        }
        let kept = select(candidates, sizes: lens.size, limit: max(maxPoints, 0))
        return build(kept, lens: lens, clock: clock)
    }

    /// Chooses which candidates to plot.
    private static func select(_ candidates: [Int], sizes: [UInt64], limit: Int) -> [Int] {
        guard candidates.count > limit else { return candidates }
        let largeLimit = limit / 2
        let byNode = candidates.sorted { sizes[$0] != sizes[$1] ? sizes[$0] > sizes[$1] : $0 < $1 }
        let large = Array(byNode.prefix(largeLimit))
        let rest = Array(byNode.dropFirst(largeLimit))
        let room = limit - large.count
        guard room > 0, !rest.isEmpty else { return large }
        let cutoff = UInt64(Double(room) / Double(rest.count) * Double(UInt32.max))
        var sample = rest.filter { UInt64(hash($0)) <= cutoff }
        if sample.count > room { sample = Array(sample.prefix(room)) }
        return large + sample
    }

    /// A fixed 32-bit mix of a node id, so sampling is repeatable.
    private static func hash(_ value: Int) -> UInt32 {
        var x = UInt64(truncatingIfNeeded: value) &* 0x9E3779B97F4A7C15
        x = (x ^ (x >> 30)) &* 0xBF58476D1CE4E5B9
        x = (x ^ (x >> 27)) &* 0x94D049BB133111EB
        return UInt32(truncatingIfNeeded: x >> 32)
    }

    /// Converts chosen nodes to plot data.
    private static func build(_ nodes: [Int], lens: TreeLens, clock: FieldClock) -> FieldData {
        let columns = lens.tree.columns
        let now = lens.tree.meta.scannedAt.timeIntervalSince1970
        var positions: [SIMD2<Float>] = []
        positions.reserveCapacity(nodes.count)
        var kinds: [UInt8] = [], ids: [NodeID] = []
        for node in nodes {
            let stamp = clock == .modified ? columns.modified[node] : columns.accessed[node]
            let days = max((now - Double(stamp)) / 86_400, minimumAgeDays)
            positions.append(SIMD2(Float(log10(days)), Float(log10(Double(lens.size[node])))))
            kinds.append(columns.kind[node])
            ids.append(NodeID(node))
        }
        return FieldData(positions: positions, kinds: kinds, nodes: ids,
                         ageRange: range(positions.map(\.x)), sizeRange: range(positions.map(\.y)))
    }

    /// The span of a set of values, or 0...1 when empty.
    private static func range(_ values: [Float]) -> ClosedRange<Float> {
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        return low...high
    }
}
